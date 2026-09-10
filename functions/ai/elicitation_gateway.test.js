/**
 * Offline tests for the Ask elicitation flow: the gateway's `ask_choice`
 * branch in `runAiTurn`. `store` is an in-memory fake and `callModel` is
 * scripted, so this runs under plain `node --test` — no Anthropic SDK, no
 * emulator. (Mirrors `mutations_gateway.test.js`'s harness, trimmed to what a
 * question needs.)
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {runAiTurn} = require("./gateway");

const UID = "user-1";
const CONVERSATION_ID = "conv-1";

/**
 * A deterministic, strictly-increasing clock.
 * @param {number} startMs
 * @return {function(): !Date}
 */
function makeClock(startMs) {
  let t = startMs;
  return () => new Date(t++);
}

/**
 * A minimal fake `store` that records appended messages.
 * @return {!Object}
 */
function makeStore() {
  const messages = [];
  return {
    messages,
    appendMessage: async (uid, cid, message) => {
      messages.push(message);
      return `msg-${messages.length}`;
    },
    touchConversation: async () => {},
    getTodayUsageTotals: async () => ({turns: 0, tokens: 0}),
    getRecentMessages: async () => [],
    logUsage: async () => {},
  };
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

test("ask_choice ends the turn with a choice_request card (no write path)", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    toolUse("ask_choice", {
      prompt: "Which goal are you chasing?",
      options: [
        {value: "gain", label: "Gain weight"},
        {value: "lose", label: "Lose fat"},
      ],
    }),
    textResponse("should not be reached"),
  ]);

  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "help me with my body", now: makeClock(1000),
  });

  assert.equal(result.status, "awaiting-input");
  assert.ok(result.requestId, "a requestId is returned");
  assert.equal(result.actionId, null, "a question is not a write proposal");
  // The loop stopped after the single tool_use response — the question ends it.
  assert.equal(callModel.callCount(), 1);

  const card = store.messages.find((m) => m.kind === "choice_request");
  assert.ok(card, "a choice_request message was appended");
  assert.equal(card.requestId, result.requestId);
  assert.equal(card.status, "pending");
  assert.equal(card.content, "Which goal are you chasing?");
  assert.deepEqual(card.fields.options, [
    {value: "gain", label: "Gain weight"},
    {value: "lose", label: "Lose fat"},
  ]);
  assert.equal(card.fields.allowMultiple, false);
});

test("an invalid ask_choice is fed back as a tool error, not shown", async () => {
  const store = makeStore();
  // First call: a bad question (one option). It should NOT end the turn — the
  // error is fed back and the model recovers with text on the next call.
  const callModel = scriptedModel([
    toolUse("ask_choice", {prompt: "Pick", options: ["only one"]}),
    textResponse("Okay, here's my answer instead."),
  ]);

  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "go", now: makeClock(1000),
  });

  assert.equal(result.status, "ok");
  assert.equal(result.assistantText, "Okay, here's my answer instead.");
  assert.equal(callModel.callCount(), 2, "the model was re-called after the error");
  assert.equal(
      store.messages.find((m) => m.kind === "choice_request"), undefined,
      "no half-formed question card was shown");
});

test("request_input ends the turn with an input_request form card", async () => {
  const store = makeStore();
  const callModel = scriptedModel([
    toolUse("request_input", {
      prompt: "Give me a couple of details first",
      fields: [
        {key: "heightCm", label: "Height", type: "number", unit: "cm"},
        {key: "weightKg", label: "Weight", type: "number", unit: "kg"},
      ],
    }),
    textResponse("should not be reached"),
  ]);

  const result = await runAiTurn({
    store, callModel, uid: UID, conversationId: CONVERSATION_ID,
    message: "help me gain weight", now: makeClock(1000),
  });

  assert.equal(result.status, "awaiting-input");
  assert.ok(result.requestId);
  assert.equal(result.actionId, null);
  assert.equal(callModel.callCount(), 1);

  const card = store.messages.find((m) => m.kind === "input_request");
  assert.ok(card, "an input_request message was appended");
  assert.equal(card.requestId, result.requestId);
  assert.equal(card.status, "pending");
  assert.equal(card.content, "Give me a couple of details first");
  assert.equal(card.fields.fields.length, 2);
  assert.equal(card.fields.fields[0].key, "heightCm");
  assert.equal(card.fields.fields[0].unit, "cm");
});

test("emits an awaiting_input phase event", async () => {
  const store = makeStore();
  const phases = [];
  await runAiTurn({
    store,
    callModel: scriptedModel([
      toolUse("ask_choice", {prompt: "A or B?", options: ["A", "B"]}),
    ]),
    onEvent: (e) => {
      if (e.type === "phase") phases.push(e.phase);
    },
    uid: UID, conversationId: CONVERSATION_ID,
    message: "go", now: makeClock(1000),
  });
  assert.ok(phases.includes("awaiting_input"));
});
