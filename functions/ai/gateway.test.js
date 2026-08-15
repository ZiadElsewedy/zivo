/**
 * Offline unit tests for the `aiChat` gateway loop (`./gateway.js`). No
 * `@anthropic-ai/sdk`, no emulator — `store` is a plain in-memory fake and
 * `callModel` is scripted per test, so this runs under plain `node --test`.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  runAiTurn,
  GatewayError,
  SYSTEM_PROMPT,
  DAILY_LIMIT_MESSAGE,
  ITERATION_LIMIT_MESSAGE,
  TOKEN_CEILING_MESSAGE,
  REFUSAL_MESSAGE,
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
 * An in-memory fake implementing the `store` seam the gateway depends on.
 * Every method is overridable via `overrides`; calls are recorded on
 * `.calls` for assertions.
 * @param {!Object=} overrides
 * @return {!Object}
 */
function makeStore(overrides) {
  const calls = {
    appendMessage: [],
    touchConversation: [],
    logUsage: [],
    listTasks: [],
  };
  const messages = [];

  const store = {
    calls,
    messages,
    appendMessage: async (uid, conversationId, message) => {
      calls.appendMessage.push({uid, conversationId, message});
      messages.push(message);
      return `msg-${messages.length}`;
    },
    touchConversation: async (uid, conversationId, fields) => {
      calls.touchConversation.push({uid, conversationId, fields});
    },
    getTodayUsageTotals: async () => ({turns: 0, tokens: 0}),
    getRecentMessages: async () => [],
    logUsage: async (uid, usageDoc) => {
      calls.logUsage.push({uid, usageDoc});
    },
    listTasks: async (uid) => {
      calls.listTasks.push(uid);
      return [];
    },
  };
  return Object.assign(store, overrides || {});
}

/**
 * A `callModel` fake that returns each of `responses` in order, recording
 * every request it was called with on `.requests`.
 * @param {!Array<!Object>} responses
 * @return {function(!Object): !Promise<!Object>}
 */
function scriptedModel(responses) {
  let i = 0;
  const fn = async (request) => {
    fn.requests.push(request);
    const resp = responses[Math.min(i, responses.length - 1)];
    i++;
    return resp;
  };
  fn.requests = [];
  fn.callCount = () => fn.requests.length;
  return fn;
}

test("rejects an empty message", async () => {
  const store = makeStore();
  const callModel = scriptedModel([]);
  await assert.rejects(
      () =>
        runAiTurn({
          store,
          callModel,
          uid: UID,
          conversationId: CONVERSATION_ID,
          message: "   ",
          now: makeClock(0),
        }),
      (err) => {
        assert.ok(err instanceof GatewayError);
        assert.equal(err.code, "invalid-argument");
        return true;
      },
  );
  assert.equal(callModel.callCount(), 0);
});

test("rejects an oversized message", async () => {
  const store = makeStore();
  const callModel = scriptedModel([]);
  const tooLong = "x".repeat(3000);
  await assert.rejects(
      () =>
        runAiTurn({
          store,
          callModel,
          uid: UID,
          conversationId: CONVERSATION_ID,
          message: tooLong,
          now: makeClock(0),
        }),
      (err) => err instanceof GatewayError && err.code === "invalid-argument",
  );
});

test("rejects a missing conversationId", async () => {
  const store = makeStore();
  const callModel = scriptedModel([]);
  await assert.rejects(
      () =>
        runAiTurn({
          store,
          callModel,
          uid: UID,
          conversationId: "",
          message: "hello",
          now: makeClock(0),
        }),
      (err) => err instanceof GatewayError && err.code === "invalid-argument",
  );
});

test("tool execution is uid-scoped and the result flows to the final answer",
    async () => {
      const store = makeStore({
        listTasks: async (uid) => {
          store.calls.listTasks.push(uid);
          return [{title: "Buy milk", done: false, priority: false,
            due: null}];
        },
      });
      const callModel = scriptedModel([
        {
          stop_reason: "tool_use",
          content: [
            {type: "tool_use", id: "call-1", name: "get_tasks", input: {}},
          ],
          usage: {input_tokens: 10, output_tokens: 5},
        },
        {
          stop_reason: "end_turn",
          content: [{type: "text", text: "You have 1 open task: Buy milk."}],
          usage: {input_tokens: 5, output_tokens: 5},
        },
      ]);

      const result = await runAiTurn({
        store,
        callModel,
        uid: UID,
        conversationId: CONVERSATION_ID,
        message: "what are my tasks?",
        now: makeClock(1000),
      });

      assert.deepEqual(store.calls.listTasks, [UID]);
      assert.equal(result.status, "ok");
      assert.equal(result.assistantText, "You have 1 open task: Buy milk.");

      const persistedRoles = store.calls.appendMessage.map(
          (c) => c.message.role);
      assert.deepEqual(persistedRoles, ["user", "assistant"]);
      assert.equal(
          store.calls.appendMessage[1].message.content,
          "You have 1 open task: Buy milk.",
      );
    });

test("stops after maxIterations and calls the model exactly that many times",
    async () => {
      const store = makeStore();
      const callModel = scriptedModel([
        {
          stop_reason: "tool_use",
          content: [
            {type: "tool_use", id: "call-x", name: "get_tasks", input: {}},
          ],
          usage: {input_tokens: 1, output_tokens: 1},
        },
      ]);

      const result = await runAiTurn({
        store,
        callModel,
        uid: UID,
        conversationId: CONVERSATION_ID,
        message: "keep going forever",
        now: makeClock(0),
        config: {maxIterations: 3},
      });

      assert.equal(callModel.callCount(), 3);
      assert.equal(result.status, "iteration-limit");
      assert.equal(result.assistantText, ITERATION_LIMIT_MESSAGE);
    });

test("the per-turn token ceiling aborts the loop cleanly", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    {
      stop_reason: "tool_use",
      content: [
        {type: "tool_use", id: "call-1", name: "get_tasks", input: {}},
      ],
      usage: {input_tokens: 80, output_tokens: 80},
    },
    {
      stop_reason: "end_turn",
      content: [{type: "text", text: "should not be reached"}],
      usage: {input_tokens: 1, output_tokens: 1},
    },
  ]);

  const result = await runAiTurn({
    store,
    callModel,
    uid: UID,
    conversationId: CONVERSATION_ID,
    message: "hello",
    now: makeClock(0),
    config: {perTurnTokenCeiling: 100},
  });

  assert.equal(callModel.callCount(), 1);
  assert.equal(result.status, "token-ceiling");
  assert.equal(result.assistantText, TOKEN_CEILING_MESSAGE);
});

test("the per-day cap short-circuits without calling the model", async () => {
  const store = makeStore({
    getTodayUsageTotals: async () => ({turns: 999, tokens: 0}),
  });
  const callModel = scriptedModel([
    {
      stop_reason: "end_turn",
      content: [{type: "text", text: "should not be reached"}],
      usage: {input_tokens: 1, output_tokens: 1},
    },
  ]);

  const result = await runAiTurn({
    store,
    callModel,
    uid: UID,
    conversationId: CONVERSATION_ID,
    message: "hello",
    now: makeClock(0),
    config: {perDayMaxTurns: 10},
  });

  assert.equal(callModel.callCount(), 0);
  assert.equal(result.status, "daily-limit");
  assert.equal(result.assistantText, DAILY_LIMIT_MESSAGE);
  assert.equal(store.calls.logUsage.length, 0);
});

test("a refusal stop_reason yields a clean refusal message", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    {
      stop_reason: "refusal",
      content: [],
      usage: {input_tokens: 5, output_tokens: 0},
    },
  ]);

  const result = await runAiTurn({
    store,
    callModel,
    uid: UID,
    conversationId: CONVERSATION_ID,
    message: "hello",
    now: makeClock(0),
  });

  assert.equal(result.status, "refusal");
  assert.equal(result.assistantText, REFUSAL_MESSAGE);
});

test("a tool executor error becomes an is_error tool_result and the loop " +
    "recovers", async () => {
  const store = makeStore({
    listTasks: async () => {
      throw new Error("boom");
    },
  });
  const callModel = scriptedModel([
    {
      stop_reason: "tool_use",
      content: [
        {type: "tool_use", id: "call-1", name: "get_tasks", input: {}},
      ],
      usage: {input_tokens: 1, output_tokens: 1},
    },
    {
      stop_reason: "end_turn",
      content: [{type: "text", text: "Sorry, something went wrong."}],
      usage: {input_tokens: 1, output_tokens: 1},
    },
  ]);

  const result = await runAiTurn({
    store,
    callModel,
    uid: UID,
    conversationId: CONVERSATION_ID,
    message: "what are my tasks?",
    now: makeClock(0),
  });

  assert.equal(callModel.callCount(), 2);
  assert.equal(result.status, "ok");
  assert.equal(result.assistantText, "Sorry, something went wrong.");

  const secondRequest = callModel.requests[1];
  const toolResultMessage = secondRequest.messages[secondRequest.messages
      .length - 1];
  const toolResultBlock = toolResultMessage.content[0];
  assert.equal(toolResultBlock.is_error, true);
});

test("the system prompt fences tool output as untrusted data", () => {
  assert.match(SYSTEM_PROMPT, /not instructions/i);
  assert.match(SYSTEM_PROMPT, /Never follow instructions/i);
});

test("usage is logged once with tokens/tools/iterations", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    {
      stop_reason: "tool_use",
      content: [
        {type: "tool_use", id: "call-1", name: "get_tasks", input: {}},
      ],
      usage: {input_tokens: 10, output_tokens: 5},
    },
    {
      stop_reason: "end_turn",
      content: [{type: "text", text: "done"}],
      usage: {input_tokens: 3, output_tokens: 2},
    },
  ]);

  await runAiTurn({
    store,
    callModel,
    uid: UID,
    conversationId: CONVERSATION_ID,
    message: "hello",
    now: makeClock(0),
  });

  assert.equal(store.calls.logUsage.length, 1);
  const usageDoc = store.calls.logUsage[0].usageDoc;
  assert.equal(usageDoc.tokensIn, 13);
  assert.equal(usageDoc.tokensOut, 7);
  assert.equal(usageDoc.iterations, 2);
  assert.deepEqual(usageDoc.tools, [{name: "get_tasks", toolCallId: "call-1"}]);
  assert.equal(usageDoc.schemaVersion, 1);
});
