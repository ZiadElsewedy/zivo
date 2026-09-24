/**
 * Offline tests for the V2 mutation flow (ADR-003): the gateway's propose
 * branch (`runAiTurn`) plus `confirmAction` / `cancelAction`. `store` is an
 * in-memory fake and `callModel` is scripted, so this runs under plain
 * `node --test` — no Anthropic SDK, no emulator.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  runAiTurn,
  confirmAction,
  cancelAction,
  GatewayError,
} = require("./gateway");

const UID = "user-1";
const CONVERSATION_ID = "conv-1";

/**
 * A deterministic, strictly-increasing clock starting at `startMs`.
 * @param {number} startMs
 * @return {function(): !Date}
 */
function makeClock(startMs) {
  let t = startMs;
  return () => new Date(t++);
}

/**
 * A fake `store` that records appended messages, pending actions (keyed by
 * actionId), and any entity writes.
 * @param {!Object=} overrides
 * @return {!Object}
 */
function makeStore(overrides) {
  const messages = [];
  const pendingActions = new Map();
  const writes = {
    expenses: [], edits: [], deletes: [], foodLogs: [], customFoods: [],
    planDays: [],
  };

  const store = {
    messages,
    pendingActions,
    writes,
    appendMessage: async (uid, cid, message) => {
      messages.push(message);
      return `msg-${messages.length}`;
    },
    touchConversation: async () => {},
    getActiveDietPlan: async () => null,
    listDietEntries: async () => [],
    getTodayUsageTotals: async () => ({turns: 0, tokens: 0}),
    getRecentMessages: async () => [],
    logUsage: async () => {},
    createPendingAction: async (uid, cid, action) => {
      // Store a copy with Date timestamps, as the real store returns.
      pendingActions.set(action.actionId, Object.assign({}, action));
    },
    getPendingAction: async (uid, cid, actionId) => {
      const a = pendingActions.get(actionId);
      return a ? Object.assign({}, a) : null;
    },
    getActivePendingAction: async (uid, cid, nowDate) => {
      const nowMs = nowDate.getTime();
      for (const a of pendingActions.values()) {
        if (a.status === "pending" &&
            (!a.expiresAt || a.expiresAt.getTime() > nowMs)) {
          return Object.assign({}, a);
        }
      }
      return null;
    },
    markPendingAction: async (uid, cid, actionId, status) => {
      const a = pendingActions.get(actionId);
      if (a) a.status = status;
    },
    markProposalMessage: async (uid, cid, actionId, status) => {
      const m = messages.find(
          (x) => x.kind === "action_proposal" && x.actionId === actionId);
      if (m) m.status = status;
    },
    createExpense: async (uid, e) => writes.expenses.push(e),
    updateExpense: async (uid, id, patch) =>
      writes.edits.push({uid, id, patch}),
    deleteExpense: async (uid, id) => writes.deletes.push({uid, id}),
    // Phase 6 (log_food). No custom foods by default, so resolution falls
    // through to the real bundled catalog the resolver reads.
    listCustomFoods: async () => [],
    writeFoodLog: async (uid, entries) => writes.foodLogs.push(...entries),
    saveCustomFood: async (uid, data) => writes.customFoods.push(data),
    savePlanDays: async (uid, planId, days) =>
      writes.planDays.push({uid, planId, days}),
    // Question cards are messages with a requestId (as in store.js).
    getChoiceRequest: async (uid, cid, requestId) => {
      const m = messages.find((x) => x.requestId === requestId);
      return m ? Object.assign({selectedValue: null}, m) : null;
    },
    markChoiceAnswered: async (uid, cid, requestId, value) => {
      const m = messages.find((x) => x.requestId === requestId);
      if (m) Object.assign(m, {status: "answered", selectedValue: value});
    },
  };
  return Object.assign(store, overrides || {});
}

/**
 * A `callModel` fake returning each of `responses` in order.
 * @param {!Array<!Object>} responses
 * @return {function(!Object): !Promise<!Object>}
 */
function scriptedModel(responses) {
  let i = 0;
  const fn = async (request) => {
    fn.requests.push(request);
    return responses[Math.min(i++, responses.length - 1)];
  };
  fn.requests = [];
  fn.callCount = () => fn.requests.length;
  return fn;
}

/**
 * A model response that calls one tool.
 * @param {string} name
 * @param {!Object} input
 * @param {string=} id
 * @return {!Object}
 */
function toolUse(name, input, id = "tool-1") {
  return {
    stop_reason: "tool_use",
    content: [{type: "tool_use", id, name, input}],
    usage: {input_tokens: 10, output_tokens: 5},
  };
}

/**
 * A plain text (end_turn) model response.
 * @param {string} text
 * @return {!Object}
 */
function textResponse(text) {
  return {
    stop_reason: "end_turn",
    content: [{type: "text", text}],
    usage: {input_tokens: 5, output_tokens: 5},
  };
}

test("a valid mutating call proposes (no write) and ends the turn", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    toolUse("create_expense", {amountMinor: 1200, category: "coffee"}),
    textResponse("should not be reached"),
  ]);

  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "log 12 EGP on coffee", now: makeClock(1000),
  });

  assert.equal(result.status, "proposed");
  assert.ok(result.actionId, "an actionId is returned");
  // The loop stopped after the single tool_use response.
  assert.equal(callModel.callCount(), 1);
  // Exactly one pending action, still pending, and NO entity write happened.
  assert.equal(store.pendingActions.size, 1);
  assert.equal(store.pendingActions.get(result.actionId).status, "pending");
  assert.equal(store.writes.expenses.length, 0);
  // An action_proposal message was appended (plus the user message), carrying
  // the pending status the client renders the card from.
  const proposal = store.messages.find((m) => m.kind === "action_proposal");
  assert.ok(proposal);
  assert.equal(proposal.actionKind, "create_expense");
  assert.equal(proposal.actionId, result.actionId);
  assert.equal(proposal.status, "pending");
  // Carries the TTL so the client can render the card expired once it lapses.
  assert.ok(proposal.expiresAt instanceof Date);
});

test("a second proposal is blocked while one is already pending (no duplicate)", async () => {
  const store = makeStore();

  // Turn 1: propose an expense — one pending action, one card.
  const first = await runAiTurn({
    store,
    callModel: scriptedModel(
        [toolUse("create_expense", {amountMinor: 500, category: "other"})]),
    uid: UID, conversationId: CONVERSATION_ID,
    message: "log 5 EGP", now: makeClock(1000),
  });
  assert.equal(first.status, "proposed");
  assert.equal(store.pendingActions.size, 1);

  // Turn 2: the user types "confirm"; the model re-proposes the same expense.
  // The gateway must suppress it — no second pending action, no second card.
  const second = await runAiTurn({
    store,
    callModel: scriptedModel(
        [toolUse("create_expense", {amountMinor: 500, category: "other"})]),
    uid: UID, conversationId: CONVERSATION_ID,
    message: "confirm", now: makeClock(2000),
  });
  assert.equal(second.status, "proposal-blocked");
  assert.equal(second.actionId, null);
  assert.equal(store.pendingActions.size, 1, "still exactly one pending action");
  // Only one action_proposal card exists across both turns.
  const cards = store.messages.filter((m) => m.kind === "action_proposal");
  assert.equal(cards.length, 1);
  // The blocked turn steered the user back to the existing card.
  const lastAssistant = store.messages.filter((m) => m.role === "assistant").pop();
  assert.match(lastAssistant.content, /already got a suggestion waiting/);

  // Confirming the one action writes exactly one expense — no duplicate.
  await confirmAction({
    store, uid: UID, conversationId: CONVERSATION_ID,
    actionId: first.actionId, now: makeClock(3000),
  });
  assert.equal(store.writes.expenses.length, 1);
});

test("confirm/cancel flip the action_proposal message status (survives reopen)", async () => {
  // Confirm path → the card message becomes 'applied'.
  const applied = makeStore();
  const confirmTurn = await runAiTurn({
    store: applied,
    callModel: scriptedModel(
        [toolUse("create_expense", {amountMinor: 1200, category: "food"})]),
    uid: UID, conversationId: CONVERSATION_ID,
    message: "log an expense", now: makeClock(1000),
  });
  await confirmAction({
    store: applied, uid: UID, conversationId: CONVERSATION_ID,
    actionId: confirmTurn.actionId, now: makeClock(2000),
  });
  const appliedCard = applied.messages.find((m) => m.kind === "action_proposal");
  assert.equal(appliedCard.status, "applied");

  // Cancel path → the card message becomes 'cancelled'.
  const cancelled = makeStore();
  const cancelTurn = await runAiTurn({
    store: cancelled,
    callModel: scriptedModel(
        [toolUse("create_expense", {amountMinor: 1200, category: "food"})]),
    uid: UID, conversationId: CONVERSATION_ID,
    message: "log an expense", now: makeClock(1000),
  });
  await cancelAction({
    store: cancelled, uid: UID, conversationId: CONVERSATION_ID,
    actionId: cancelTurn.actionId, now: makeClock(2000),
  });
  const cancelledCard =
      cancelled.messages.find((m) => m.kind === "action_proposal");
  assert.equal(cancelledCard.status, "cancelled");
});

test("invalid mutating input is fed back so the model can self-correct", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    // Missing required category → validation fails.
    toolUse("create_expense", {amountMinor: 1200}),
    textResponse("I need the category to log that."),
  ]);

  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "log 12 EGP", now: makeClock(1000),
  });

  // No proposal persisted; the model got a chance to fix it (2 calls).
  assert.equal(result.status, "ok");
  assert.equal(store.pendingActions.size, 0);
  assert.equal(callModel.callCount(), 2);
  // The second call carried a tool_result with is_error back to the model.
  const secondCallMessages = callModel.requests[1].messages;
  const toolResult = secondCallMessages
      .flatMap((m) => Array.isArray(m.content) ? m.content : [])
      .find((b) => b && b.type === "tool_result");
  assert.ok(toolResult && toolResult.is_error);
});

test("confirmAction performs the write and is idempotent", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    toolUse("create_expense", {amountMinor: 1200, category: "coffee"}),
  ]);
  const {actionId} = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "log 12 EGP on coffee", now: makeClock(1000),
  });

  const confirmed = await confirmAction({
    store, uid: UID, conversationId: CONVERSATION_ID, actionId,
    now: makeClock(2000),
  });
  assert.equal(confirmed.status, "applied");
  assert.equal(store.writes.expenses.length, 1);
  assert.equal(store.writes.expenses[0].id, actionId);
  assert.equal(store.writes.expenses[0].amountMinor, 1200);
  assert.equal(store.pendingActions.get(actionId).status, "applied");
  assert.match(confirmed.assistantText, /Logged expense/);

  // Re-confirm: idempotent — no second write.
  const again = await confirmAction({
    store, uid: UID, conversationId: CONVERSATION_ID, actionId,
    now: makeClock(3000),
  });
  assert.equal(again.status, "already-applied");
  assert.equal(store.writes.expenses.length, 1);
});

test("create_custom_food proposes then confirm writes exactly those figures", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    toolUse("create_custom_food", {
      name: "BreadWay Whole Wheat Toast",
      kcalPer100g: 247,
      proteinPer100g: 9,
      carbsPer100g: 41,
      fatPer100g: 3.5,
    }),
  ]);

  const {actionId} = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "save that as a custom food", now: makeClock(1000),
  });
  assert.equal(store.writes.customFoods.length, 0, "nothing written before confirm");

  const confirmed = await confirmAction({
    store, uid: UID, conversationId: CONVERSATION_ID, actionId,
    now: makeClock(2000),
  });
  assert.equal(confirmed.status, "applied");
  assert.equal(store.writes.customFoods.length, 1);
  const saved = store.writes.customFoods[0];
  assert.equal(saved.id, actionId);
  assert.equal(saved.name, "BreadWay Whole Wheat Toast");
  assert.equal(saved.kcalPer100g, 247);
  assert.equal(saved.proteinPer100g, 9);
  assert.equal(saved.carbsPer100g, 41);
  assert.equal(saved.fatPer100g, 3.5);
  assert.match(confirmed.assistantText, /Saved "BreadWay Whole Wheat Toast"/);
});

// A plan with one every-day slot, so it resolves on any date.
const DIET_PLAN = {
  name: "Cut",
  status: "active",
  days: [{
    weekday: null,
    label: "Every day",
    meals: [
      {id: "lunch-2", label: "Lunch", items: []},
      {id: "dinner-3", label: "Dinner", items: []},
    ],
  }],
};

/**
 * A `makeStore` whose active diet plan is DIET_PLAN.
 * @param {!Object=} overrides Extra store methods, as `makeStore` takes them.
 * @return {!Object}
 */
function dietStore(overrides) {
  return makeStore(Object.assign(
      {getActiveDietPlan: async () => DIET_PLAN}, overrides || {}));
}

test("confirmAction applies mark_meal_eaten through the store", async () => {
  const writes = {entries: []};
  const store = dietStore({
    setDietEntry: async (uid, dayKey, mealId, eaten) => {
      writes.entries.push({uid, dayKey, mealId, eaten});
    },
  });
  const callModel = scriptedModel([
    // The model claims the meal is called "Brunch"; the plan says "Lunch".
    toolUse("mark_meal_eaten",
        {mealId: "lunch-2", label: "Brunch", date: "2026-08-17T00:00:00.000Z"}),
  ]);
  const {actionId} = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "I had lunch", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });

  const confirmed = await confirmAction({
    store, uid: UID, conversationId: CONVERSATION_ID, actionId,
    now: makeClock(2000),
  });
  assert.equal(confirmed.status, "applied");
  assert.deepEqual(writes.entries, [{
    uid: UID, dayKey: "2026-08-17", mealId: "lunch-2", eaten: true,
  }]);
  // The card and the result line name the meal the PLAN names, not the one
  // the model remembered.
  assert.match(confirmed.assistantText, /Marked Lunch eaten/);
});

test("a meal id that isn't in the plan never becomes a proposal", async () => {
  // `validate` can only prove the id is a string — and a string is exactly
  // what a model can invent. Before the verify hook, a hallucinated id sailed
  // through Confirm and wrote an orphan dietEntries doc: invisible in the app,
  // and quietly wrong in every "meals eaten" count afterwards.
  const writes = {entries: []};
  const store = dietStore({
    setDietEntry: async (...args) => {
      writes.entries.push(args);
    },
  });
  const callModel = scriptedModel([
    toolUse("mark_meal_eaten", {mealId: "second-breakfast", label: "Brunch"}),
    {
      stop_reason: "end_turn",
      content: [{type: "text", text: "I couldn't find that meal in your plan."}],
      usage: {input_tokens: 1, output_tokens: 1},
    },
  ]);

  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "mark my second breakfast eaten", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });

  assert.equal(result.status, "ok");
  assert.equal(result.actionId, null);
  assert.equal(store.pendingActions.size, 0);
  assert.deepEqual(writes.entries, []);

  // The rejection goes back to the model as a tool error it can correct from,
  // and names the ids that DO exist rather than just saying no.
  const followUp = callModel.requests[1];
  const toolResult = followUp.messages[followUp.messages.length - 1].content[0];
  assert.equal(toolResult.is_error, true);
  assert.match(toolResult.content, /second-breakfast/);
  assert.match(toolResult.content, /lunch-2/);
});

test("mark_meal_eaten is refused when there is no active plan", async () => {
  const store = makeStore(); // getActiveDietPlan → null
  const callModel = scriptedModel([
    toolUse("mark_meal_eaten", {mealId: "lunch-2", label: "Lunch"}),
    {
      stop_reason: "end_turn",
      content: [{type: "text", text: "You don't have an active diet plan."}],
      usage: {input_tokens: 1, output_tokens: 1},
    },
  ]);

  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "mark lunch eaten", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });

  assert.equal(result.actionId, null);
  assert.equal(store.pendingActions.size, 0);
});

test("confirm re-checks the plan: a meal deleted after the proposal is " +
    "refused and writes nothing", async () => {
  // A proposal can wait an hour for a tap, and the plan can change in that
  // window. The write itself is the last moment the reference can be proven.
  const writes = {entries: []};
  let plan = DIET_PLAN;
  const store = makeStore({
    getActiveDietPlan: async () => plan,
    setDietEntry: async (...args) => {
      writes.entries.push(args);
    },
  });
  const callModel = scriptedModel([
    toolUse("mark_meal_eaten", {mealId: "lunch-2", label: "Lunch"}),
  ]);
  const {actionId} = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "I had lunch", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });
  assert.ok(actionId);

  // The user edits their plan; that meal is gone.
  plan = {
    name: "Cut",
    status: "active",
    days: [{weekday: null, label: "Every day", meals: [
      {id: "dinner-3", label: "Dinner", items: []},
    ]}],
  };

  await assert.rejects(
      () => confirmAction({
        store, uid: UID, conversationId: CONVERSATION_ID, actionId,
        now: makeClock(2000),
      }),
      (err) => err instanceof GatewayError &&
        err.code === "failed-precondition");
  assert.deepEqual(writes.entries, []);
  assert.equal(store.pendingActions.get(actionId).status, "pending");
});

/**
 * A fresh plan with one real item to replace, for replace_meal_item's tests.
 * A factory, not a shared constant: `applyProposedAction`'s
 * "replace_meal_item" case mutates `meal.items` in place before persisting it
 * (harmless in production, where every request re-fetches its own copy from
 * Firestore) — a shared object here would let one test's confirm silently
 * corrupt every later test's fixture.
 * @return {!Object}
 */
function itemPlan() {
  return {
    id: "plan-1",
    name: "Cut",
    status: "active",
    days: [{
      weekday: null,
      label: "Every day",
      meals: [{
        id: "dinner-3",
        label: "Dinner",
        items: [
          {name: "Chicken", quantity: 200, unit: "g", calories: 330,
            proteinG: 62, carbsG: 0, fatG: 7},
        ],
      }],
    }],
  };
}

test("replace_meal_item: propose then confirm swaps exactly that item", async () => {
  const store = dietStore({getActiveDietPlan: async () => itemPlan()});
  const callModel = scriptedModel([
    toolUse("replace_meal_item", {
      mealId: "dinner-3", itemIndex: 0, itemName: "Chicken",
      foodId: "usda:171477", quantity: 200, unit: "g",
    }),
  ]);

  const {actionId} = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "swap the chicken for something else", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });
  assert.ok(actionId);
  assert.equal(store.writes.planDays.length, 0, "nothing written before confirm");

  const confirmed = await confirmAction({
    store, uid: UID, conversationId: CONVERSATION_ID, actionId,
    now: makeClock(2000),
  });
  assert.equal(confirmed.status, "applied");
  assert.equal(store.writes.planDays.length, 1);
  const write = store.writes.planDays[0];
  assert.equal(write.planId, "plan-1");
  const newItem = write.days[0].meals[0].items[0];
  assert.notEqual(newItem.name, "Chicken");
  // Priced through the real catalog, not the model's own arithmetic.
  assert.equal(newItem.estimated, false);
  assert.ok(newItem.calories > 0);
  assert.match(confirmed.assistantText, /^Replaced Chicken with/);
});

test("replace_meal_item: a stale item reference is refused, not swapped", async () => {
  // `validate` can only prove itemIndex/itemName are the right TYPES — a
  // model can still invent or misremember either. Before verify, a stale
  // reference would silently overwrite whatever item is actually there.
  const store = dietStore({getActiveDietPlan: async () => itemPlan()});
  const callModel = scriptedModel([
    toolUse("replace_meal_item", {
      mealId: "dinner-3", itemIndex: 0, itemName: "Salmon", // not what's there
      foodId: "usda:171477", quantity: 200, unit: "g",
    }),
    {
      stop_reason: "end_turn",
      content: [{type: "text", text: "That item isn't there any more."}],
      usage: {input_tokens: 1, output_tokens: 1},
    },
  ]);

  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "swap the salmon", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });
  assert.equal(result.actionId, null);
  assert.equal(store.pendingActions.size, 0);
  assert.equal(store.writes.planDays.length, 0);
});

test("replace_meal_item: an unresolvable replacement food is refused", async () => {
  const store = dietStore({getActiveDietPlan: async () => itemPlan()});
  const callModel = scriptedModel([
    toolUse("replace_meal_item", {
      mealId: "dinner-3", itemIndex: 0, itemName: "Chicken",
      query: "koshari", quantity: 1, unit: "bowl", // notFound in the catalog
    }),
    {
      stop_reason: "end_turn",
      content: [{type: "text", text: "I can't find that food."}],
      usage: {input_tokens: 1, output_tokens: 1},
    },
  ]);

  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "swap the chicken for koshari", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });
  assert.equal(result.actionId, null);
  assert.equal(store.pendingActions.size, 0);
  assert.equal(store.writes.planDays.length, 0);
});

test("replace_meal_item: confirm re-checks the item — edited after the " +
    "proposal is refused and writes nothing", async () => {
  let plan = itemPlan();
  const store = dietStore({getActiveDietPlan: async () => plan});
  const callModel = scriptedModel([
    toolUse("replace_meal_item", {
      mealId: "dinner-3", itemIndex: 0, itemName: "Chicken",
      foodId: "usda:171477", quantity: 200, unit: "g",
    }),
  ]);
  const {actionId} = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "swap the chicken", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });
  assert.ok(actionId);

  // The user edits the item themselves before confirming.
  plan = {
    id: "plan-1",
    name: "Cut",
    status: "active",
    days: [{weekday: null, label: "Every day", meals: [{
      id: "dinner-3",
      label: "Dinner",
      items: [{name: "Turkey", quantity: 200, unit: "g", calories: 300,
        proteinG: 55, carbsG: 0, fatG: 5}],
    }]}],
  };

  await assert.rejects(
      () => confirmAction({
        store, uid: UID, conversationId: CONVERSATION_ID, actionId,
        now: makeClock(2000),
      }),
      (err) => err instanceof GatewayError &&
        err.code === "failed-precondition");
  assert.equal(store.writes.planDays.length, 0);
  assert.equal(store.pendingActions.get(actionId).status, "pending");
});

test("edit_expense: propose then confirm patches only the changed fields", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    toolUse("edit_expense", {
      expenseId: "exp-42",
      label: "coffee 40.00 EGP",
      amountMinor: 6000,
    }),
  ]);
  const {actionId, status} = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "change that coffee to 60", now: makeClock(1000),
  });
  // Proposing writes nothing — it only persists a pending action + card.
  assert.equal(status, "proposed");
  assert.equal(store.writes.edits.length, 0);
  const card = store.messages.find((m) => m.kind === "action_proposal");
  assert.equal(card.actionKind, "edit_expense");

  const confirmed = await confirmAction({
    store, uid: UID, conversationId: CONVERSATION_ID, actionId,
    now: makeClock(2000),
  });
  assert.equal(confirmed.status, "applied");
  // Exactly the id and the single changed field reach the store — no
  // category/currency/note keys the model never set.
  assert.deepEqual(store.writes.edits, [{
    uid: UID, id: "exp-42", patch: {amountMinor: 6000},
  }]);
  assert.match(confirmed.assistantText, /Updated expense · coffee 40\.00 EGP/);
});

test("delete_expense: propose then confirm removes exactly that id", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    toolUse("delete_expense", {
      expenseId: "exp-7",
      label: "transport 30.00 EGP",
      amountMinor: 3000,
      currency: "EGP",
      category: "transport",
    }),
  ]);
  const {actionId, status} = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "delete that transport expense", now: makeClock(1000),
  });
  assert.equal(status, "proposed");
  assert.equal(store.writes.deletes.length, 0);

  const confirmed = await confirmAction({
    store, uid: UID, conversationId: CONVERSATION_ID, actionId,
    now: makeClock(2000),
  });
  assert.equal(confirmed.status, "applied");
  assert.deepEqual(store.writes.deletes, [{uid: UID, id: "exp-7"}]);
  assert.match(
      confirmed.assistantText, /Deleted expense · transport 30\.00 EGP/);
});

test("confirmAction on an expired action refuses and writes nothing", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    toolUse("create_expense", {amountMinor: 700, category: "other"}),
  ]);
  const {actionId} = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "log 7 EGP", now: makeClock(0),
    // 1ms TTL so it's already expired at confirm time.
    config: {pendingActionTtlMs: 1},
  });

  await assert.rejects(
      () => confirmAction({
        store, uid: UID, conversationId: CONVERSATION_ID, actionId,
        now: makeClock(10000),
      }),
      (err) => {
        assert.ok(err instanceof GatewayError);
        assert.equal(err.code, "failed-precondition");
        return true;
      },
  );
  assert.equal(store.writes.expenses.length, 0);
  assert.equal(store.pendingActions.get(actionId).status, "expired");
});

test("cancelAction marks cancelled and writes nothing", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    toolUse("create_expense", {amountMinor: 1200, category: "coffee"}),
  ]);
  const {actionId} = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "log a coffee", now: makeClock(1000),
  });

  const cancelled = await cancelAction({
    store, uid: UID, conversationId: CONVERSATION_ID, actionId,
    now: makeClock(2000),
  });
  assert.equal(cancelled.status, "cancelled");
  assert.equal(store.pendingActions.get(actionId).status, "cancelled");
  assert.equal(store.writes.expenses.length, 0);
});

test("confirmAction on an unknown action is not-found", async () => {
  const store = makeStore();
  await assert.rejects(
      () => confirmAction({
        store, uid: UID, conversationId: CONVERSATION_ID, actionId: "nope",
        now: makeClock(1000),
      }),
      (err) => {
        assert.ok(err instanceof GatewayError);
        assert.equal(err.code, "not-found");
        return true;
      },
  );
});

// --- Phase 6: log_food (propose→confirm), numbers computed server-side ------

test("log_food computes nutrition server-side; the model supplies no calories",
    async () => {
      const store = makeStore();
      // The model names foods and amounts only — NO kcal/macros anywhere.
      const callModel = scriptedModel([
        toolUse("log_food", {items: [
          {foodId: "usda:171477", quantity: 200, unit: "g"},
        ]}),
      ]);
      const {actionId, status} = await runAiTurn({
        store, callModel, uid: UID, conversationId: CONVERSATION_ID,
        message: "I ate 200g of chicken breast", now: makeClock(1000),
        clientClock: {offsetMinutes: 0},
      });
      // Proposing writes nothing.
      assert.equal(status, "proposed");
      assert.equal(store.writes.foodLogs.length, 0);
      const card = store.messages.find((m) => m.kind === "action_proposal");
      assert.equal(card.actionKind, "log_food");
      // The card already carries the server-computed total (330 kcal), so the
      // user sees a real number before confirming.
      assert.equal(card.fields.totalKcal, 330);

      const confirmed = await confirmAction({
        store, uid: UID, conversationId: CONVERSATION_ID, actionId,
        now: makeClock(2000),
      });
      assert.equal(confirmed.status, "applied");
      assert.equal(store.writes.foodLogs.length, 1);
      const entry = store.writes.foodLogs[0];
      assert.equal(entry.foodId, "usda:171477");
      assert.equal(entry.kcal, 330); // 165/100g × 200g, computed, not claimed
      assert.equal(entry.origin, "logged");
      assert.equal(entry.estimated, false);
      assert.equal(entry.source, "usdaFdc");
      // Doc id derives from the actionId, so re-confirm overwrites.
      assert.equal(entry.id, `${actionId}__0`);
      assert.match(confirmed.assistantText, /Logged/);
    });

test("log_food is idempotent on double-confirm", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    toolUse("log_food",
        {items: [{foodId: "usda:171477", quantity: 100, unit: "g"}]}),
  ]);
  const {actionId} = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "log 100g chicken", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });
  await confirmAction({
    store, uid: UID, conversationId: CONVERSATION_ID, actionId,
    now: makeClock(2000),
  });
  const again = await confirmAction({
    store, uid: UID, conversationId: CONVERSATION_ID, actionId,
    now: makeClock(3000),
  });
  assert.equal(again.status, "already-applied");
  // The second confirm re-uses the same doc id — no duplicate row.
  assert.equal(store.writes.foodLogs.length, 1);
});

test("an ambiguous food never becomes a log_food proposal", async () => {
  // Raw vs cooked rice is a ~3x fork; choosing for the user would be a guess.
  // The refusal goes back to the model, naming the candidates it can pick from.
  const store = makeStore();
  const callModel = scriptedModel([
    toolUse("log_food",
        {items: [{query: "rice white long-grain regular", quantity: 100,
          unit: "g"}]}),
    textResponse("Did you mean raw or cooked rice?"),
  ]);
  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "I ate 100g of rice", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });
  assert.equal(result.status, "ok");
  assert.equal(result.actionId, null);
  assert.equal(store.pendingActions.size, 0);
  assert.equal(store.writes.foodLogs.length, 0);
  // The model got a correctable error listing the foodIds it can choose.
  const followUp = callModel.requests[1];
  const toolResult = followUp.messages[followUp.messages.length - 1].content[0];
  assert.equal(toolResult.is_error, true);
  assert.match(toolResult.content, /differ in calories/);
  assert.match(toolResult.content, /usda:/);
});

test("a not-found food is refused with a custom-food hint, not logged",
    async () => {
      const store = makeStore();
      const callModel = scriptedModel([
        toolUse("log_food",
            {items: [{query: "koshari", quantity: 1, unit: "bowl"}]}),
        textResponse("That's not in the catalog — want to define it?"),
      ]);
      const result = await runAiTurn({
        store, callModel, uid: UID, conversationId: CONVERSATION_ID,
        message: "I ate a bowl of koshari", now: makeClock(1000),
        clientClock: {offsetMinutes: 0},
      });
      assert.equal(result.actionId, null);
      assert.equal(store.writes.foodLogs.length, 0);
      const followUp = callModel.requests[1];
      const toolResult =
          followUp.messages[followUp.messages.length - 1].content[0];
      assert.equal(toolResult.is_error, true);
      assert.match(toolResult.content, /custom food/);
    });

test("a unit the food can't be measured in is refused with the ones that work",
    async () => {
      // 100ml of olive oil is not 100g; no density is assumed.
      const store = makeStore();
      const callModel = scriptedModel([
        toolUse("log_food", {items: [
          {query: "oil olive salad or cooking", quantity: 100, unit: "ml"},
        ]}),
        textResponse("How much by weight?"),
      ]);
      const result = await runAiTurn({
        store, callModel, uid: UID, conversationId: CONVERSATION_ID,
        message: "I had 100ml of olive oil", now: makeClock(1000),
        clientClock: {offsetMinutes: 0},
      });
      assert.equal(result.actionId, null);
      assert.equal(store.writes.foodLogs.length, 0);
      const followUp = callModel.requests[1];
      const toolResult =
          followUp.messages[followUp.messages.length - 1].content[0];
      assert.equal(toolResult.is_error, true);
      assert.match(toolResult.content, /Measures that work/);
    });

test("log_food logs a multi-item meal as one batch", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    toolUse("log_food", {items: [
      {query: "egg whole raw fresh", quantity: 100, unit: "g"},
      {foodId: "usda:171477", quantity: 150, unit: "g"},
    ]}),
  ]);
  const {actionId} = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "eggs and chicken", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });
  await confirmAction({
    store, uid: UID, conversationId: CONVERSATION_ID, actionId,
    now: makeClock(2000),
  });
  // Two entries, both written, each with a distinct actionId-derived doc id.
  assert.equal(store.writes.foodLogs.length, 2);
  assert.deepEqual(
      store.writes.foodLogs.map((e) => e.id),
      [`${actionId}__0`, `${actionId}__1`]);
});

// --- Phase 7: the reply is validated against the diet state it read ---------

/**
 * A store whose diet reads describe a known day: a 2,200 kcal fat-loss target
 * and 1,180 kcal logged. So `get_diet` yields consumed 1180 / remaining 1020,
 * and the coaching findings say exactly that — the ground truth the reply is
 * checked against.
 * @param {!Object=} overrides
 * @return {!Object}
 */
function coachStore(overrides) {
  return makeStore(Object.assign({
    getActiveDietPlan: async () => DIET_PLAN,
    getDietTargets: async () => ({
      goal: "fatLoss", calories: 2200, proteinG: 160,
      carbsG: null, fatG: null, source: "manual",
    }),
    listFoodLogs: async () => [{
      foodId: "usda:171477", foodName: "Chicken breast", quantity: 200,
      unit: "g", grams: 200, kcal: 1180, proteinG: 90, carbsG: 120, fatG: 35,
      source: "usdaFdc", sourceRef: "171477", origin: "logged", estimated: false,
    }],
    listFoodLogRange: async () => [],
  }, overrides || {}));
}

test("a reply that contradicts the diet numbers falls back to findings text",
    async () => {
      const store = coachStore();
      const callModel = scriptedModel([
        toolUse("get_diet", {}),
        textResponse("Great work — you've eaten about 1,850 calories today."),
      ]);
      const result = await runAiTurn({
        store, callModel, uid: UID, conversationId: CONVERSATION_ID,
        message: "how am I doing on food?", now: makeClock(1000),
        clientClock: {offsetMinutes: 0},
      });
      assert.equal(result.status, "validated-fallback");
      assert.equal(result.validation.ok, false);
      assert.ok(result.validation.codes.includes("numeric_contradiction"));
      // The persisted reply is the deterministic findings text, not the wrong
      // one the model produced.
      assert.match(result.assistantText, /1180 of 2200 kcal so far/);
      const persisted =
          store.messages.filter((m) => m.role === "assistant").pop();
      assert.match(persisted.content, /1180 of 2200/);
    });

test("an accurate reply passes validation untouched", async () => {
  const store = coachStore();
  const accurate =
    "You're at about 1,180 calories so far, so roughly 1,020 left against " +
    "your 2,200 target.";
  const callModel = scriptedModel([
    toolUse("get_diet", {}),
    textResponse(accurate),
  ]);
  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "how am I doing?", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });
  assert.equal(result.status, "ok");
  assert.equal(result.validation.ok, true);
  assert.equal(result.assistantText, accurate);
});

test("a sub-floor calorie recommendation is intercepted for safety", async () => {
  const store = coachStore();
  const callModel = scriptedModel([
    toolUse("get_diet", {}),
    textResponse("To speed up fat loss, aim for around 900 calories a day."),
  ]);
  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "how do I lose faster?", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });
  assert.equal(result.status, "safety-intercept");
  assert.equal(result.validation.safe, false);
  assert.match(result.assistantText, /doctor or a registered dietitian/);
});

test("a turn that reads no diet data is never validated", async () => {
  // No get_diet/get_today ran, so there is no state to check against — the
  // reply passes through with no validation record.
  const store = makeStore();
  const callModel = scriptedModel([textResponse("Sure — happy to help!")]);
  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "hi", now: makeClock(1000),
  });
  assert.equal(result.status, "ok");
  assert.equal(result.validation, null);
});

// ---- DISCOVER → CHOOSE → MUTATE (meal replacement) --------------------------

const MOLOKHIA_PLAN = {
  name: "Cut",
  status: "active",
  days: [{
    weekday: null,
    label: "Every day",
    meals: [{
      id: "lunch-1",
      label: "Lunch",
      items: [
        {name: "Molokhia", quantity: 250, unit: "g", calories: 70,
          proteinG: 5, carbsG: 8, fatG: 2},
        {name: "Rice", quantity: 150, unit: "g", calories: 195,
          proteinG: 4, carbsG: 42, fatG: 0.5},
      ],
    }],
  }],
};

/**
 * A store holding MOLOKHIA_PLAN with the diet reads get_diet needs stubbed
 * empty.
 * @param {!Object=} overrides
 * @return {!Object}
 */
function molokhiaStore(overrides) {
  return makeStore(Object.assign({
    getActiveDietPlan: async () => MOLOKHIA_PLAN,
    getDietTargets: async () => null,
    getBodyProfile: async () => null,
    getDateOfBirthMs: async () => null,
    listBodyWeights: async () => [],
    listDietEntries: async () => [],
    listFoodLogs: async () => [],
    listFoodLogRange: async () => [],
  }, overrides || {}));
}

const MOLOKHIA_CANDIDATES = {
  mealId: "lunch-1", itemIndex: 0, itemName: "Molokhia",
  candidates: [{name: "green beans"}, {name: "zucchini"}, {name: "okra"}],
};

test("'I don't want molokhia': search offers options, a same-turn replace is " +
    "refused, and the turn ends on the user's choice — nothing proposed",
async () => {
  const store = molokhiaStore();
  const callModel = scriptedModel([
    toolUse("get_diet", {}, "t-diet"),
    toolUse("search_food_alternatives", MOLOKHIA_CANDIDATES, "t-search"),
    // The model tries to pick for the user…
    toolUse("replace_meal_item", {
      mealId: "lunch-1", itemIndex: 0, itemName: "Molokhia",
      foodId: "usda:169961", quantity: 200, unit: "g",
    }, "t-replace"),
    // …is told to ask instead, and does.
    toolUse("ask_choice", {
      prompt: "ممكن تستبدل الملوخية بـ:",
      // Referenced by the names the search priced (a value it never returned
      // would be dropped); the model's own subtitle figures are ignored.
      options: [
        {value: "green beans", label: "فاصوليا خضراء", subtitle: "1 kcal"},
        {value: "zucchini", label: "كوسة"},
        {value: "okra", label: "بامية"},
      ],
    }, "t-ask"),
  ]);
  const events = [];
  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "مش عايز ملوخية في الدايت", now: makeClock(1000),
    clientClock: {offsetMinutes: 0}, onEvent: (e) => events.push(e),
  });

  assert.equal(result.status, "awaiting-input");
  assert.equal(result.terminalState, "needs_user_input");
  assert.equal(result.actionId, null, "no change proposed during discovery");
  assert.equal(store.pendingActions.size, 0);
  // The refused proposal went back to the model as an error to act on.
  const afterReplace = callModel.requests[3].messages
      .flatMap((m) => Array.isArray(m.content) ? m.content : [])
      .find((b) => b.type === "tool_result" && b.tool_use_id === "t-replace");
  assert.equal(afterReplace.is_error, true);
  assert.match(afterReplace.content, /hasn't chosen yet/);
  // The user saw what ran: diet read, then the alternatives search.
  const steps = events.filter((e) => e.type === "step" && e.status === "ok")
      .map((e) => e.tool);
  assert.deepEqual(steps, ["get_diet", "search_food_alternatives"]);
  // The card carries the verified options: the model's labels, the server's
  // foodIds and figures, and the exact swap each one means.
  const card = store.messages.find((m) => m.kind === "choice_request");
  assert.deepEqual(card.fields.options.map((o) => o.label),
      ["فاصوليا خضراء", "كوسة", "بامية"]);
  for (const o of card.fields.options) {
    assert.notEqual(o.subtitle, "1 kcal");
    assert.match(o.subtitle, /^\d+ g · \d+ kcal · [\d.]+ g protein$/);
    assert.ok(Number.isFinite(o.metadata.kcal));
    const binding = card.bindings[o.value];
    assert.equal(binding.tool, "replace_meal_item");
    assert.equal(binding.input.foodId, o.value);
    assert.equal(binding.input.mealId, "lunch-1");
    assert.equal(binding.input.quantity, o.metadata.grams);
  }
});

test("'option 2' next turn: the model sees the numbered options and the " +
    "replacement is proposed for confirmation", async () => {
  const store = molokhiaStore({
    getRecentMessages: async () => [
      {role: "user", content: "مش عايز ملوخية في الدايت"},
      {role: "assistant", content: "ممكن تستبدل الملوخية بـ:",
        kind: "choice_request", status: "pending", fields: {options: [
          {value: "usda:169961", label: "فاصوليا خضراء",
            subtitle: "200 g · 70 kcal"},
          {value: "usda:169292", label: "كوسة", subtitle: "400 g · 60 kcal"},
        ]}},
    ],
  });
  const zucchini = require("../nutrition/meal_replacement")
      .pickWholeFood("zucchini", [], null);
  const callModel = scriptedModel([
    toolUse("get_diet", {}, "t-diet"),
    toolUse("replace_meal_item", {
      mealId: "lunch-1", itemIndex: 0, itemName: "Molokhia",
      foodId: zucchini.id, quantity: 400, unit: "g",
    }, "t-replace"),
  ]);
  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "اختار رقم 2", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });

  const history = callModel.requests[0].messages[1].content;
  assert.match(history, /Options shown to the user:/);
  assert.match(history, /2\. كوسة — 400 g · 60 kcal \(value: usda:169292\)/);
  assert.equal(result.status, "proposed");
  const pending = store.pendingActions.get(result.actionId);
  assert.equal(pending.status, "pending", "still needs the user's Confirm");
});

// ---- Structured choices: verified options → tap → resolve by id -------------

/**
 * A plan whose breakfast is eggs — the "I don't want egg" scenario — built
 * fresh per test, since a confirmed swap mutates the plan it's handed.
 * @return {!Object}
 */
function eggPlan() {
  return {
    id: "plan-1",
    name: "Cut",
    status: "active",
    days: [{
      weekday: null,
      label: "Every day",
      meals: [{
        id: "breakfast-1",
        label: "Breakfast",
        items: [
          {name: "Eggs", quantity: 2, unit: "piece", calories: 240,
            proteinG: 12, carbsG: 1, fatG: 10},
          {name: "Bread", quantity: 60, unit: "g", calories: 160,
            proteinG: 5, carbsG: 30, fatG: 2},
        ],
      }],
    }],
  };
}

/**
 * A store holding `plan` (default: a fresh eggPlan) with the diet reads
 * stubbed empty.
 * @param {!Object=} plan
 * @return {!Object}
 */
function eggStore(plan) {
  const p = plan || eggPlan();
  return makeStore({
    plan: p,
    getActiveDietPlan: async () => p,
    getDietTargets: async () => null,
    getBodyProfile: async () => null,
    getDateOfBirthMs: async () => null,
    listBodyWeights: async () => [],
    listDietEntries: async () => [],
    listFoodLogs: async () => [],
    listFoodLogRange: async () => [],
    findMessageByClientTurnId: async () => null,
  });
}

const EGG_SEARCH = {
  mealId: "breakfast-1", itemIndex: 0, itemName: "Eggs",
  candidates: [
    {name: "feta cheese"}, {name: "tuna salad"}, {name: "turkey breast"},
  ],
};

const FETA = "usda:173420";
const TUNA = "usda:175160";
const TURKEY = "usda:171501";

/**
 * Runs the discovery turn ("I don't want egg") to a choice card.
 * @param {!Object} store
 * @param {!Object=} lastResponse What the model does after the search.
 * @return {!Promise<!Object>} The turn result.
 */
async function discoverEggSwaps(store, lastResponse) {
  const callModel = scriptedModel([
    toolUse("get_diet", {}, "t-diet"),
    toolUse("search_food_alternatives", EGG_SEARCH, "t-search"),
    lastResponse || toolUse("ask_choice", {
      prompt: "I found 3 verified swaps that are close to the original " +
        "calories. Which one would you like?",
      options: [
        {value: FETA, label: "Feta cheese"},
        {value: TUNA, label: "Tuna salad"},
        {value: TURKEY, label: "Turkey breast"},
      ],
    }, "t-ask"),
  ]);
  return runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "I don't want to eat egg in my breakfast", now: makeClock(1000),
    clientClock: {offsetMinutes: 0},
  });
}

test("structured choices: verified swaps become a choice card with the " +
    "server's figures — and nothing is proposed or written", async () => {
  const store = eggStore();
  const result = await discoverEggSwaps(store);

  assert.equal(result.status, "awaiting-input");
  assert.ok(result.requestId);
  const card = store.messages.find((m) => m.kind === "choice_request");
  assert.equal(card.requestId, result.requestId);
  assert.deepEqual(card.fields.options, [
    {value: FETA, label: "Feta cheese",
      subtitle: "90 g · 239 kcal · 12.8 g protein",
      metadata: {grams: 90, kcal: 239, proteinG: 12.8, carbsG: 3.5,
        fatG: 19.4}},
    {value: TUNA, label: "Tuna salad",
      subtitle: "130 g · 243 kcal · 20.8 g protein",
      metadata: {grams: 130, kcal: 243, proteinG: 20.8, carbsG: 12.2,
        fatG: 12.1}},
    {value: TURKEY, label: "Turkey breast",
      subtitle: "190 g · 239 kcal · 42.2 g protein",
      metadata: {grams: 190, kcal: 239, proteinG: 42.2, carbsG: 0, fatG: 6.7}},
  ]);
  assert.deepEqual(card.bindings[TUNA], {
    tool: "replace_meal_item",
    input: {mealId: "breakfast-1", itemIndex: 0, itemName: "Eggs",
      foodId: TUNA, quantity: 130, unit: "g"},
  });
  // Mutation only after selection.
  assert.equal(store.pendingActions.size, 0);
  assert.equal(store.writes.planDays.length, 0);
});

test("structured choices: an option the search never verified is dropped, " +
    "not rendered", async () => {
  const store = eggStore();
  await discoverEggSwaps(store, toolUse("ask_choice", {
    prompt: "Which one?",
    options: [
      {value: FETA, label: "Feta cheese"},
      {value: "usda:000000", label: "Invented omelette", subtitle: "9 kcal"},
      {value: TURKEY, label: "Turkey breast"},
    ],
  }, "t-ask"));
  const card = store.messages.find((m) => m.kind === "choice_request");
  assert.deepEqual(card.fields.options.map((o) => o.value), [FETA, TURKEY]);
});

test("structured choices: a reply that lists the options as bullets still " +
    "ships the card, built from the verified options", async () => {
  const store = eggStore();
  const result = await discoverEggSwaps(store, textResponse(
      "I found 3 verified swaps close to the original calories:\n" +
      "- Feta cheese — 90 g\n- Tuna salad — 130 g\n- Turkey breast — 190 g"));

  assert.equal(result.status, "awaiting-input");
  const card = store.messages.find((m) => m.kind === "choice_request");
  assert.equal(card.content,
      "I found 3 verified swaps close to the original calories:");
  assert.deepEqual(card.fields.options.map((o) => o.value),
      [FETA, TUNA, TURKEY]);
  assert.ok(card.bindings[FETA]);
  // No second, plain-text copy of the list.
  assert.equal(store.messages.filter((m) =>
    m.role === "assistant" && !m.kind).length, 0);
});

test("structured choices: zero verified options → no card, a normal reply",
    async () => {
      const store2 = eggStore();
      const callModel = scriptedModel([
        toolUse("search_food_alternatives", Object.assign({}, EGG_SEARCH, {
          candidates: [{name: "zzqx unobtainium"}, {name: "qqzv nothing"}],
        }), "t-search"),
        textResponse("I couldn't find a swap I can price — what would you " +
          "like instead?"),
      ]);
      const r2 = await runAiTurn({
        store: store2, callModel, uid: UID, conversationId: CONVERSATION_ID,
        message: "I don't want egg", now: makeClock(1000),
        clientClock: {offsetMinutes: 0},
      });
      assert.equal(r2.status, "ok");
      assert.equal(r2.requestId, null);
      assert.equal(store2.messages.filter((m) =>
        m.kind === "choice_request").length, 0);
    });

test("structured choices: tapping an option resolves it by id and proposes " +
    "exactly that swap — no model call; confirm then writes it", async () => {
  const store = eggStore();
  const first = await discoverEggSwaps(store);
  const callModel = scriptedModel([textResponse("should not be reached")]);

  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    // Whatever the client displayed, the pick is the structured choice.
    message: "something the client displayed",
    choice: {requestId: first.requestId, value: TUNA},
    clientTurnId: "turn-2",
    now: makeClock(5000), clientClock: {offsetMinutes: 0},
  });

  assert.equal(callModel.callCount(), 0, "the model never guesses the pick");
  assert.equal(result.status, "proposed");
  assert.equal(result.terminalState, "needs_user_input");
  const user = store.messages.filter((m) => m.role === "user").pop();
  assert.equal(user.content, "Tuna salad", "the option's own label");
  assert.deepEqual(user.choice, {requestId: first.requestId, value: TUNA});
  const card = store.messages.find((m) => m.kind === "choice_request");
  assert.equal(card.status, "answered");
  assert.equal(card.selectedValue, TUNA);

  const pending = store.pendingActions.get(result.actionId);
  assert.equal(pending.tool, "replace_meal_item");
  assert.equal(pending.input.item.foodId, TUNA);
  assert.equal(pending.input.newItem.quantity, 130);
  assert.equal(store.writes.planDays.length, 0, "not written before confirm");

  await confirmAction({
    store, uid: UID, conversationId: CONVERSATION_ID,
    actionId: result.actionId, now: makeClock(9000),
  });
  assert.equal(store.writes.planDays.length, 1);
  const swapped = store.plan.days[0].meals[0].items[0];
  assert.equal(swapped.quantity, 130);
  assert.equal(swapped.calories, 243);
});

test("structured choices: an unknown option, an unknown card and a " +
    "re-answered card are rejected before anything is written", async () => {
  const store = eggStore();
  const first = await discoverEggSwaps(store);
  const before = store.messages.length;
  const turn = (choice) => runAiTurn({
    store, callModel: scriptedModel([textResponse("x")]), uid: UID,
    conversationId: CONVERSATION_ID, message: "pick", choice,
    now: makeClock(5000), clientClock: {offsetMinutes: 0},
  });

  await assert.rejects(turn({requestId: first.requestId, value: "usda:1"}),
      (e) => e instanceof GatewayError && e.code === "invalid-argument");
  await assert.rejects(turn({requestId: "no-such-card", value: FETA}),
      (e) => e instanceof GatewayError && e.code === "not-found");
  await assert.rejects(turn({requestId: first.requestId}),
      (e) => e instanceof GatewayError && e.code === "invalid-argument");
  assert.equal(store.messages.length, before, "nothing persisted");

  await turn({requestId: first.requestId, value: FETA});
  const after = store.messages.length;
  await assert.rejects(turn({requestId: first.requestId, value: TUNA}),
      (e) => e instanceof GatewayError && e.code === "failed-precondition");
  assert.equal(store.messages.length, after, "a stale card stays answered once");
  assert.equal(store.pendingActions.size, 1);
});

test("structured choices: a bound pick whose item moved hands the model the " +
    "pick and the failure instead of proposing a stale swap", async () => {
  const plan = eggPlan();
  const store = eggStore(plan);
  const first = await discoverEggSwaps(store);
  // The plan changes under the card.
  plan.days[0].meals[0].items.reverse();
  const callModel = scriptedModel([textResponse("Your breakfast changed — " +
    "want me to look again?")]);
  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "Feta cheese", choice: {requestId: first.requestId, value: FETA},
    now: makeClock(5000), clientClock: {offsetMinutes: 0},
  });
  assert.equal(result.status, "ok");
  assert.equal(store.pendingActions.size, 0);
  const sent = callModel.requests[0].messages.pop().content;
  assert.match(sent, /value=usda:173420/);
  assert.match(sent, /Proposing that change failed/);
});

test("structured choices are generic: an unbound question's pick reaches " +
    "the model as its exact option, across different scenarios", async () => {
  for (const scenario of [
    {prompt: "Which plan do you want?", options: [
      {value: "plan-cut", label: "Cut — 2,000 kcal"},
      {value: "plan-maintain", label: "Maintain"},
    ], pick: "plan-maintain"},
    {prompt: "Which version?", options: [
      {value: "recommended", label: "Recommended"},
      {value: "higher-protein", label: "Higher protein"},
      {value: "lower-calorie", label: "Lower calorie"},
    ], pick: "higher-protein"},
    {prompt: "Today's session?", options: [
      {value: "push", label: "Push day"},
      {value: "rest", label: "Rest"},
    ], pick: "rest"},
  ]) {
    const store = makeStore();
    const ask = await runAiTurn({
      store, callModel: scriptedModel([toolUse("ask_choice", {
        prompt: scenario.prompt, options: scenario.options,
      })]),
      uid: UID, conversationId: CONVERSATION_ID, message: "help me decide",
      now: makeClock(1000),
    });
    const card = store.messages.find((m) => m.kind === "choice_request");
    assert.equal(card.bindings, null, "a plain question binds no change");

    const callModel = scriptedModel([textResponse("Got it.")]);
    const answer = await runAiTurn({
      store, callModel, uid: UID, conversationId: CONVERSATION_ID,
      message: "ignored", choice: {requestId: ask.requestId,
        value: scenario.pick},
      now: makeClock(5000),
    });
    assert.equal(answer.status, "ok");
    const label = scenario.options.find((o) => o.value === scenario.pick).label;
    const sent = callModel.requests[0].messages.pop().content;
    assert.ok(sent.startsWith(label));
    assert.match(sent, new RegExp(`value=${scenario.pick}`));
    assert.equal(store.messages.filter((m) => m.role === "user").pop().content,
        label);
    assert.equal(store.pendingActions.size, 0);
  }
});
