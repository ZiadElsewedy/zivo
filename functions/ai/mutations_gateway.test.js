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
  const writes = {expenses: []};

  const store = {
    messages,
    pendingActions,
    writes,
    appendMessage: async (uid, cid, message) => {
      messages.push(message);
      return `msg-${messages.length}`;
    },
    touchConversation: async () => {},
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
