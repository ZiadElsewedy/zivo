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
  const writes = {expenses: [], edits: [], deletes: [], foodLogs: []};

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
