/**
 * End-to-end regression tests for what a STREAMING turn puts on screen:
 * a real router (`../routing/router.js`) over a Gemini-shaped fake provider,
 * the real turn loop, and a client mirror that applies the streamed events
 * the way the app does (`delta` appends, `replace` swaps the text).
 *
 * The bug these pin: a reply that started streaming ("أيوه، بناءً على…"),
 * then — mid-answer — started over from its first word, both copies on
 * screen at once.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {runAiTurn} = require("./turn");
const {generate} = require("../routing/router");
const {ProviderRegistry} = require("../providers/registry");

const UID = "user-1";
const CONV = "conv-1";
const OPENING = "أيوه، بناءً على";

/** @return {!Object} An in-memory store whose history reads back. */
function makeStore() {
  const messages = [];
  return {
    messages,
    appendMessage: async (uid, conv, m) => {
      messages.push(m);
    },
    touchConversation: async () => {},
    getTodayUsageTotals: async () => ({turns: 0, tokens: 0}),
    getRecentMessages: async (uid, conv, limit) =>
      messages.slice(-limit).map((m) => Object.assign({}, m)),
    findMessageByClientTurnId: async () => null,
    logUsage: async () => {},
    listWorkouts: async () => [],
    listWorkoutSessions: async () => [],
  };
}

const USAGE = {inputTokens: 10, outputTokens: 5, cacheReadTokens: 0,
  cacheWriteTokens: 0};

/**
 * A Gemini-shaped provider: each script entry is one `generate` call —
 * `{chunks, fail?}` streams `chunks` through `onText`, then either throws a
 * transient (503) failure or resolves to the text (plus `toolUse`, if set).
 * @param {!Array<!Object>} script
 * @return {!Object}
 */
function geminiScript(script) {
  let i = 0;
  return {
    generate: async (req, opts) => {
      const step = script[i++];
      const text = [];
      for (const c of step.chunks) {
        text.push(c);
        if (opts && opts.onText) opts.onText(c);
      }
      if (step.fail) {
        const err = new Error("stream interrupted");
        err.status = 503;
        throw err;
      }
      const content = [{type: "text", text: text.join("")}];
      if (step.toolUse) {
        content.push({type: "tool_use", id: "call-1", name: step.toolUse,
          input: {}, raw: {functionCall: {name: step.toolUse, args: {}}}});
      }
      return {stopReason: step.toolUse ? "tool_use" : "end", content,
        usage: USAGE};
    },
  };
}

/**
 * Runs one streamed turn on Gemini through the real router.
 * @param {!Object} gemini
 * @param {{streamReplace: (boolean|undefined), stream: (boolean|undefined)}=}
 *   opts
 * @return {!Promise<{frames: !Array<string>, saved: string}>}
 */
async function runStreamed(gemini, opts = {}) {
  const registry = new ProviderRegistry().register("gemini", gemini);
  const provider = {
    generate: (req, genOpts) => generate(registry, "chat", req,
        Object.assign({retryBackoffMs: [0]}, genOpts),
        {preferModel: "gemini-flash"}),
  };
  const store = makeStore();
  let screen = "";
  const frames = [];
  await runAiTurn({
    store,
    provider,
    stream: opts.stream !== false,
    streamReplace: opts.streamReplace !== false,
    onEvent: (e) => {
      if (e.type === "delta") screen += e.text;
      else if (e.type === "replace") screen = e.text;
      else return;
      frames.push(screen);
    },
    uid: UID,
    conversationId: CONV,
    message: "should I train today?",
    now: () => new Date("2026-09-26T09:00:00Z"),
  });
  const saved = store.messages.filter((m) => m.role === "assistant")
      .map((m) => m.content).join("\n");
  return {frames, saved};
}

/**
 * @param {string} s
 * @return {number} How many times the reply's opening appears in `s`.
 */
const openings = (s) => s.split(OPENING).length - 1;

test("REGRESSION: the first Gemini stream fails mid-answer and is retried — " +
    "the screen never shows the reply starting over", async () => {
  const gemini = geminiScript([
    {chunks: [OPENING, " جدولك،", " آخر تمرين كان"], fail: true},
    {chunks: [OPENING, " جدولك،", " آخر تمرين كان من يومين.",
      " اتمرن Pull النهارده."]},
  ]);
  const {frames, saved} = await runStreamed(gemini);
  for (const frame of frames) {
    assert.equal(openings(frame), 1, `restarted on screen: ${frame}`);
  }
  const expected = `${OPENING} جدولك، آخر تمرين كان من يومين. اتمرن Pull النهارده.`;
  assert.equal(frames[frames.length - 1], expected);
  assert.equal(saved, expected, "what streamed is what was saved");
});

test("REGRESSION: a lead-in written before a lookup and restated after it " +
    "appears once — on screen and in the saved reply", async () => {
  const gemini = geminiScript([
    {chunks: [`${OPENING} جدولك،`], toolUse: "get_workouts"},
    {chunks: [`${OPENING} جدولك، `, "اتمرن Pull النهارده."]},
  ]);
  const {frames, saved} = await runStreamed(gemini);
  for (const frame of frames) assert.equal(openings(frame), 1, frame);
  assert.equal(saved, `${OPENING} جدولك، اتمرن Pull النهارده.`);
  assert.equal(frames[frames.length - 1], saved);
});

test("a buffered turn drops a restated lead-in from the saved reply too",
    async () => {
      const gemini = geminiScript([
        {chunks: [`${OPENING} جدولك،`], toolUse: "get_workouts"},
        {chunks: [`${OPENING} جدولك، اتمرن Pull النهارده.`]},
      ]);
      const {saved} = await runStreamed(gemini, {stream: false});
      assert.equal(saved, `${OPENING} جدولك، اتمرن Pull النهارده.`);
    });

test("normal token-by-token streaming is unchanged: deltas only, the saved " +
    "text matches, a real lead-in keeps its own paragraph", async () => {
  const gemini = geminiScript([
    {chunks: ["Let me check", " your training."], toolUse: "get_workouts"},
    {chunks: ["Yes", " — train", " today."]},
  ]);
  const {frames, saved} = await runStreamed(gemini);
  assert.equal(saved, "Let me check your training.\n\nYes — train today.");
  assert.equal(frames[frames.length - 1], saved);
  for (let i = 1; i < frames.length; i++) {
    assert.ok(frames[i].startsWith(frames[i - 1]), "never rewinds");
  }
});
