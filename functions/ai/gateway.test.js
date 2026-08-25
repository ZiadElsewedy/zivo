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

test("empty thinking blocks are stripped from re-sent history; " +
    "signed non-empty ones are preserved", async () => {
  const store = makeStore({
    listTasks: async () => [],
  });
  // First response mixes an empty placeholder thinking block (as
  // claude-sonnet-5 emits, and the streaming SDK returns with an empty
  // signature) with a real signed one, before the tool_use.
  const callModel = scriptedModel([
    {
      stop_reason: "tool_use",
      content: [
        {type: "thinking", thinking: "", signature: ""},
        {type: "thinking", thinking: "real reasoning", signature: "sig-abc"},
        {type: "tool_use", id: "call-1", name: "get_tasks", input: {}},
      ],
      usage: {input_tokens: 10, output_tokens: 5},
    },
    {
      stop_reason: "end_turn",
      content: [{type: "text", text: "No open tasks."}],
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

  assert.equal(result.status, "ok");
  // The assistant message echoed back on the second call must NOT carry the
  // empty thinking block (the API rejects it), but MUST keep the signed one.
  const secondReq = callModel.requests[1];
  const assistantMsg = secondReq.messages.find((m) => m.role === "assistant");
  const thinkingBlocks = assistantMsg.content.filter(
      (b) => b.type === "thinking");
  assert.equal(thinkingBlocks.length, 1);
  assert.equal(thinkingBlocks[0].signature, "sig-abc");
  // Every thinking block re-sent has real content (none would fail the API).
  for (const m of secondReq.messages) {
    if (!Array.isArray(m.content)) continue;
    for (const b of m.content) {
      if (b.type === "thinking") assert.ok(b.thinking && b.thinking.length);
    }
  }
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
  assert.equal(usageDoc.schemaVersion, 2);
});

test("the tool schemas + system prompt are sent as a cached prefix", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    {
      stop_reason: "end_turn",
      content: [{type: "text", text: "hi"}],
      usage: {input_tokens: 5, output_tokens: 2},
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

  const req = callModel.requests[0];
  // System is a structured block array carrying the cache breakpoint (not a
  // bare string), so tools + system read back from cache after the first call.
  assert.ok(Array.isArray(req.system));
  assert.equal(req.system[0].text, SYSTEM_PROMPT);
  assert.deepEqual(req.system[0].cache_control, {type: "ephemeral"});
});

test("responseStyle 'balanced' (and an omitted/unrecognized value) adds " +
    "no second system block", async () => {
  for (const responseStyle of [undefined, "balanced", "garbage"]) {
    const store = makeStore();
    const callModel = scriptedModel([
      {
        stop_reason: "end_turn",
        content: [{type: "text", text: "hi"}],
        usage: {input_tokens: 5, output_tokens: 2},
      },
    ]);

    await runAiTurn({
      store,
      callModel,
      uid: UID,
      conversationId: CONVERSATION_ID,
      message: "hello",
      responseStyle,
      now: makeClock(0),
    });

    const req = callModel.requests[0];
    assert.equal(req.system.length, 1);
    assert.equal(req.system[0].text, SYSTEM_PROMPT);
  }
});

test("responseStyle 'concise'/'detailed' append an UNCACHED second system " +
    "block after SYSTEM_PROMPT — the cache breakpoint on element 0 is " +
    "untouched", async () => {
  for (const responseStyle of ["concise", "detailed"]) {
    const store = makeStore();
    const callModel = scriptedModel([
      {
        stop_reason: "end_turn",
        content: [{type: "text", text: "hi"}],
        usage: {input_tokens: 5, output_tokens: 2},
      },
    ]);

    await runAiTurn({
      store,
      callModel,
      uid: UID,
      conversationId: CONVERSATION_ID,
      message: "hello",
      responseStyle,
      now: makeClock(0),
    });

    const req = callModel.requests[0];
    assert.equal(req.system.length, 2);
    assert.equal(req.system[0].text, SYSTEM_PROMPT);
    assert.deepEqual(req.system[0].cache_control, {type: "ephemeral"});
    assert.equal(req.system[1].cache_control, undefined);
    assert.match(
        req.system[1].text,
        responseStyle === "concise" ? /short/i : /thorough/i,
    );
  }
});

test("cache read/write tokens are logged and priced at their discounts",
    async () => {
      const store = makeStore();
      const callModel = scriptedModel([
        {
          stop_reason: "end_turn",
          content: [{type: "text", text: "done"}],
          usage: {
            input_tokens: 100,
            output_tokens: 10,
            cache_creation_input_tokens: 2000,
            cache_read_input_tokens: 4000,
          },
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

      const usageDoc = store.calls.logUsage[0].usageDoc;
      // tokensIn is total input volume: 100 uncached + 2000 write + 4000 read.
      assert.equal(usageDoc.tokensIn, 6100);
      assert.equal(usageDoc.cacheWriteTokens, 2000);
      assert.equal(usageDoc.cacheReadTokens, 4000);
      // Cost applies the caching multipliers: uncached full, write 1.25x,
      // read 0.1x, output at the output rate.
      const inRate = 3 / 1000000;
      const outRate = 15 / 1000000;
      const expected =
        100 * inRate + 2000 * inRate * 1.25 + 4000 * inRate * 0.1 +
        10 * outRate;
      assert.ok(Math.abs(usageDoc.costUsd - expected) < 1e-12);
    });

test("a read-tool turn emits understanding → working → done phases plus " +
    "streamed text deltas", async () => {
  const store = makeStore({
    listTasks: async () => [{title: "Buy milk", done: false, priority: false,
      due: null}],
  });
  const responses = [
    {
      stop_reason: "tool_use",
      content: [{type: "tool_use", id: "call-1", name: "get_tasks", input: {}}],
      usage: {input_tokens: 10, output_tokens: 5},
    },
    {
      stop_reason: "end_turn",
      content: [{type: "text", text: "You have 1 open task."}],
      usage: {input_tokens: 5, output_tokens: 5},
    },
  ];
  // A streamModel that replays scripted responses, emitting each final text
  // block as two deltas so the delta path is exercised.
  let i = 0;
  const streamModel = async (request, onText) => {
    const resp = responses[Math.min(i, responses.length - 1)];
    i++;
    const text = (resp.content.find((b) => b.type === "text") || {}).text;
    if (text) {
      onText(text.slice(0, 4));
      onText(text.slice(4));
    }
    return resp;
  };

  const events = [];
  const result = await runAiTurn({
    store,
    streamModel,
    onEvent: (e) => events.push(e),
    uid: UID,
    conversationId: CONVERSATION_ID,
    message: "what are my tasks?",
    now: makeClock(0),
  });

  assert.equal(result.status, "ok");
  const phases = events.filter((e) => e.type === "phase").map((e) => e.phase);
  assert.deepEqual(phases, ["understanding", "working", "done"]);
  assert.equal(events[events.length - 1].status, "ok");

  const deltas = events.filter((e) => e.type === "delta").map((e) => e.text);
  assert.equal(deltas.join(""), "You have 1 open task.");
});

test("a turn with no tools emits no working phase", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    {
      stop_reason: "end_turn",
      content: [{type: "text", text: "Hi."}],
      usage: {input_tokens: 3, output_tokens: 1},
    },
  ]);
  const events = [];
  await runAiTurn({
    store,
    callModel,
    onEvent: (e) => events.push(e),
    uid: UID,
    conversationId: CONVERSATION_ID,
    message: "hi",
    now: makeClock(0),
  });
  const phases = events.filter((e) => e.type === "phase").map((e) => e.phase);
  assert.deepEqual(phases, ["understanding", "done"]);
});

test("a mutation turn emits a preparing_change phase before done", async () => {
  const store = makeStore({
    createPendingAction: async () => {},
    getActivePendingAction: async () => null,
  });
  const callModel = scriptedModel([
    {
      stop_reason: "tool_use",
      content: [{
        type: "tool_use",
        id: "call-1",
        name: "create_expense",
        input: {amountMinor: 1200, category: "coffee"},
      }],
      usage: {input_tokens: 8, output_tokens: 4},
    },
  ]);
  const events = [];
  const result = await runAiTurn({
    store,
    callModel,
    onEvent: (e) => events.push(e),
    uid: UID,
    conversationId: CONVERSATION_ID,
    message: "log 12 EGP on coffee",
    now: makeClock(0),
  });
  assert.equal(result.status, "proposed");
  const phases = events.filter((e) => e.type === "phase").map((e) => e.phase);
  assert.deepEqual(phases, ["understanding", "preparing_change", "done"]);
});

test("an oversized tool result is truncated before it re-enters the loop",
    async () => {
      const big = "y".repeat(20000);
      const store = makeStore({
        listTasks: async () => [{title: big, done: false, priority: false,
          due: null}],
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
          content: [{type: "text", text: "ok"}],
          usage: {input_tokens: 1, output_tokens: 1},
        },
      ]);

      await runAiTurn({
        store,
        callModel,
        uid: UID,
        conversationId: CONVERSATION_ID,
        message: "tasks?",
        now: makeClock(0),
        config: {maxToolResultChars: 6000},
      });

      const secondRequest = callModel.requests[1];
      const toolResultMessage = secondRequest.messages[
          secondRequest.messages.length - 1];
      const content = toolResultMessage.content[0].content;
      assert.ok(content.length < 6100);
      assert.match(content, /truncated \d+ characters/);
    });

test("clientTurnId replays an already-answered turn without re-running the model",
    async () => {
      const store = makeStore({
        findMessageByClientTurnId: async () =>
          ({role: "assistant", content: "earlier answer"}),
      });
      const callModel = scriptedModel([]);

      const result = await runAiTurn({
        store,
        callModel,
        uid: UID,
        conversationId: CONVERSATION_ID,
        message: "hello again",
        clientTurnId: "turn-1",
        now: makeClock(0),
      });

      // The completed turn is replayed verbatim — no model call, no writes.
      assert.equal(result.status, "replayed");
      assert.equal(result.assistantText, "earlier answer");
      assert.equal(callModel.callCount(), 0);
      assert.equal(store.calls.appendMessage.length, 0);
    });

test("clientTurnId with only a prior user message skips the duplicate append " +
    "but still runs the turn", async () => {
  const store = makeStore({
    findMessageByClientTurnId: async () =>
      ({role: "user", content: "hello"}),
  });
  const callModel = scriptedModel([({
    stop_reason: "end_turn",
    content: [{type: "text", text: "fresh answer"}],
    usage: {input_tokens: 5, output_tokens: 5},
  })]);

  const result = await runAiTurn({
    store,
    callModel,
    uid: UID,
    conversationId: CONVERSATION_ID,
    message: "hello",
    clientTurnId: "turn-2",
    now: makeClock(0),
  });

  // No duplicate user message; exactly one assistant answer appended.
  const appendedUsers =
      store.calls.appendMessage.filter((c) => c.message.role === "user");
  assert.equal(appendedUsers.length, 0);
  const appendedAssistants =
      store.calls.appendMessage.filter((c) => c.message.role === "assistant");
  assert.equal(appendedAssistants.length, 1);
  assert.equal(result.assistantText, "fresh answer");
});

test("without clientTurnId the gateway behaves as before (always appends)",
    async () => {
      const store = makeStore();
      const callModel = scriptedModel([({
        stop_reason: "end_turn",
        content: [{type: "text", text: "answer"}],
        usage: {input_tokens: 5, output_tokens: 5},
      })]);

      await runAiTurn({
        store,
        callModel,
        uid: UID,
        conversationId: CONVERSATION_ID,
        message: "hello",
        now: makeClock(0),
      });

      const appendedUsers =
          store.calls.appendMessage.filter((c) => c.message.role === "user");
      assert.equal(appendedUsers.length, 1);
    });
