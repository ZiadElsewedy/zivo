/**
 * Offline tests for what a turn hands the model and what it records about
 * it: intent-scoped tools and prompt, the history (the current message once),
 * the token ceiling, per-call usage and failed-turn records.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {runAiTurn} = require("./turn");
const {systemPromptFor} = require("./prompt/system_prompt");
const {CATALOG, PROMPT_VERSION} = require("./scope");
const {AiUnavailableError} = require("../providers/classify");
const {generate, stickyProvider} = require("../routing/router");
const {ProviderRegistry} = require("../providers/registry");
const {UsageMeter, buildUsageRecord} = require("../shared/usage_log");

const UID = "user-1";
const CONV = "conv-1";

/**
 * An in-memory store whose history reads back what was appended — like
 * Firestore, where the turn's own user message is written before history is
 * read.
 * @param {!Object=} overrides
 * @return {!Object}
 */
function makeStore(overrides) {
  const messages = [];
  const logged = [];
  return Object.assign({
    messages,
    logged,
    appendMessage: async (uid, conv, m) => {
      messages.push(m);
    },
    touchConversation: async () => {},
    getTodayUsageTotals: async () => ({turns: 0, tokens: 0}),
    getRecentMessages: async (uid, conv, limit) =>
      messages.slice(-limit).map((m) => Object.assign({}, m)),
    findMessageByClientTurnId: async () => null,
    logUsage: async (uid, doc) => {
      logged.push(doc);
    },
    listWorkouts: async () => [],
    listWorkoutSessions: async () => [],
  }, overrides || {});
}

/**
 * A router-shaped provider replaying `steps` — each a normalized response
 * minus the stamps, which it adds (Claude Sonnet) — recording every request.
 * A step that is a function is called instead (to throw).
 * @param {!Array<(!Object|function(): !Object)>} steps
 * @return {!Object}
 */
function scriptedProvider(steps) {
  const requests = [];
  let i = 0;
  return {
    requests,
    generate: async (req) => {
      requests.push(req);
      const step = steps[Math.min(i++, steps.length - 1)];
      if (typeof step === "function") return step();
      return Object.assign({provider: "anthropic", model: "claude-sonnet-5",
        modelKey: "claude-sonnet"}, step);
    },
  };
}

const toolUse = (name, input, usage) => ({
  stopReason: "tool_use",
  content: [{type: "tool_use", id: `c-${name}-${Math.random()}`, name,
    input: input || {}, raw: {type: "tool_use", name}}],
  usage: usage || {inputTokens: 10, outputTokens: 5, cacheReadTokens: 0,
    cacheWriteTokens: 0},
});
const answer = (text, usage) => ({
  stopReason: "end",
  content: [{type: "text", text, raw: {type: "text", text}}],
  usage: usage || {inputTokens: 5, outputTokens: 5, cacheReadTokens: 0,
    cacheWriteTokens: 0},
});

const run = (store, provider, message, extra) => runAiTurn(Object.assign({
  store, provider, uid: UID, conversationId: CONV, message,
  now: () => new Date(Date.UTC(2026, 8, 26, 12)),
}, extra || {}));

/**
 * How many times `text` appears across the request's messages.
 * @param {!Object} req
 * @param {string} text
 * @return {number}
 */
function occurrences(req, text) {
  return req.messages.filter((m) => typeof m.content === "string" &&
    m.content.includes(text)).length;
}

test("the current user message appears exactly once in the model input — " +
    "with a clientTurnId", async () => {
  const store = makeStore();
  store.messages.push(
      {role: "user", content: "earlier question", createdAt: new Date(0)},
      {role: "assistant", content: "earlier answer", createdAt: new Date(1)});
  const provider = scriptedProvider([answer("ok")]);
  await run(store, provider, "how am I doing overall?",
      {clientTurnId: "turn-1"});
  assert.equal(occurrences(provider.requests[0], "how am I doing overall?"), 1);
  assert.equal(occurrences(provider.requests[0], "earlier question"), 1);
  assert.equal(store.logged[0].context.historyMessages, 2);
});

test("the current user message appears exactly once — without a " +
    "clientTurnId, and on a retry of the same turn", async () => {
  const store = makeStore();
  const provider = scriptedProvider([answer("ok")]);
  await run(store, provider, "how am I doing overall?");
  assert.equal(occurrences(provider.requests[0], "how am I doing overall?"), 1);

  // A retry: the user message of this turn is already persisted.
  const retryStore = makeStore();
  retryStore.messages.push({role: "user", content: "how am I doing overall?",
    clientTurnId: "turn-2", createdAt: new Date(0)});
  retryStore.findMessageByClientTurnId = async () => retryStore.messages[0];
  const retryProvider = scriptedProvider([answer("ok")]);
  await run(retryStore, retryProvider, "how am I doing overall?",
      {clientTurnId: "turn-2"});
  assert.equal(
      occurrences(retryProvider.requests[0], "how am I doing overall?"), 1);
});

test("a training question exposes only training (+core) tools and the " +
    "training prompt, and logs the intent", async () => {
  const store = makeStore();
  const provider = scriptedProvider([answer("ok")]);
  await run(store, provider, "how is my bench progressing?");
  const req = provider.requests[0];
  const names = req.tools.map((t) => t.name);
  assert.ok(names.includes("get_exercise_analysis"));
  assert.ok(!names.includes("get_diet") && !names.includes("get_expenses"));
  assert.equal(req.system[0].text, systemPromptFor("training"));
  const doc = store.logged[0];
  assert.equal(doc.intent, "training");
  assert.equal(doc.intentReason, "keywords");
  assert.equal(doc.context.toolCount, names.length);
  assert.equal(doc.promptVersion, PROMPT_VERSION);
});

test("an ambiguous request still receives the full tool set and prompt",
    async () => {
      const store = makeStore();
      const provider = scriptedProvider([answer("ok")]);
      await run(store, provider, "how am I doing?");
      const req = provider.requests[0];
      assert.deepEqual(req.tools.map((t) => t.name),
          CATALOG.map((t) => t.name));
      assert.equal(req.system[0].text, systemPromptFor("ambiguous"));
      assert.equal(store.logged[0].intent, "ambiguous");
    });

test("load_tools widens a mis-routed turn: the next step gets the area's " +
    "tools and prompt", async () => {
  const store = makeStore();
  const provider = scriptedProvider([
    toolUse("load_tools", {area: "training"}),
    toolUse("get_workouts"),
    answer("You trained once."),
  ]);
  const result = await run(store, provider, "hello");
  assert.equal(result.status, "ok");
  const [first, second] = provider.requests;
  assert.ok(!first.tools.some((t) => t.name === "get_workouts"));
  assert.ok(second.tools.some((t) => t.name === "get_workouts"));
  assert.equal(second.system[0].text, systemPromptFor("training"));
  const doc = store.logged[0];
  assert.equal(doc.intent, "general");
  assert.deepEqual(doc.expandedTo, ["training"]);
  assert.equal(doc.unexposedToolCalls, undefined, "get_workouts was exposed");
  // load_tools is not a lookup the user sees.
  assert.deepEqual(store.messages.at(-1).activity,
      [{tool: "get_workouts", status: "ok"}]);
});

test("the token ceiling does not count cache reads once per call — a " +
    "multi-step tool flow over a cached prefix runs every step", async () => {
  // Each step re-reads a 20K cached prefix. Summed per call (the old rule)
  // that passed 50K after the third call and forced the fourth to answer.
  const usage = {inputTokens: 100, outputTokens: 50, cacheReadTokens: 20000,
    cacheWriteTokens: 0};
  const store = makeStore();
  const provider = scriptedProvider([
    toolUse("get_workouts", {}, usage),
    toolUse("get_last_workout", {}, usage),
    toolUse("get_training_analysis", {}, usage),
    toolUse("get_readiness", {}, usage),
    answer("Here's the picture.", usage),
  ]);
  const result = await run(store, provider, "how is my training going?");
  assert.equal(result.status, "ok");
  assert.equal(provider.requests.length, 5);
  for (const req of provider.requests) {
    assert.equal(req.toolChoice, undefined, "no step was forced to answer");
    // Each step marks its tail so the next step reads it back from cache.
    assert.equal(req.cacheTail, "ephemeral");
  }
  assert.equal(store.logged[0].cacheReadTokens, 100000);
});

test("the token ceiling still ends a turn whose CONTEXT outgrows it",
    async () => {
      const store = makeStore();
      const provider = scriptedProvider([
        toolUse("get_workouts", {}, {inputTokens: 1000, outputTokens: 50,
          cacheReadTokens: 60000, cacheWriteTokens: 0}),
        answer("From what I read…"),
      ]);
      await run(store, provider, "how is my training going?");
      assert.equal(provider.requests[1].toolChoice, "none");
      // The forced final step has no follow-up to read its tail back.
      assert.equal(provider.requests[0].cacheTail, "ephemeral");
      assert.equal(provider.requests[1].cacheTail, undefined);
    });

test("per-call usage aggregates exactly into the turn's totals, with tool " +
    "result sizes and the context breakdown", async () => {
  const store = makeStore();
  const provider = scriptedProvider([
    toolUse("get_workouts", {}, {inputTokens: 300, outputTokens: 40,
      cacheReadTokens: 12000, cacheWriteTokens: 0}),
    answer("done", {inputTokens: 500, outputTokens: 60, cacheReadTokens: 12000,
      cacheWriteTokens: 900}),
  ]);
  await run(store, provider, "how is my training going?");
  const doc = store.logged[0];
  const sum = (f) => doc.perCall.reduce((n, c) => n + c[f], 0);
  assert.equal(doc.perCall.length, 2);
  assert.equal(sum("inputTokens"), doc.uncachedTokensIn);
  assert.equal(sum("cacheReadTokens"), doc.cacheReadTokens);
  assert.equal(sum("cacheWriteTokens"), doc.cacheWriteTokens);
  assert.equal(sum("outputTokens"), doc.tokensOut);
  assert.deepEqual(doc.perCall.map((c) => c.stopReason), ["tool_use", "end"]);
  assert.ok(doc.perCall.every((c) => typeof c.latencyMs === "number"));
  const t = doc.perCall[0].tools[0];
  assert.equal(t.name, "get_workouts");
  assert.equal(t.status, "ok");
  assert.ok(t.resultChars > 0);
  assert.equal(doc.context.toolResultChars, t.resultChars);
  for (const k of ["systemChars", "toolDefChars", "historyMessages",
    "historyChars", "ledgerChars", "userChars"]) {
    assert.equal(typeof doc.context[k], "number", k);
  }
  // Sizes only — no text of the prompt, the message or the result.
  assert.doesNotMatch(JSON.stringify(doc), /how is my training going/);
});

test("a turn whose selected provider fails carries a full failed usage " +
    "record naming that provider", async () => {
  const store = makeStore();
  const provider = scriptedProvider([
    toolUse("get_workouts"),
    () => {
      const err = new AiUnavailableError("quota",
          [{provider: "gemini", model: "gemini-flash-latest", kind: "quota"}]);
      err.tries = [{provider: "gemini", model: "gemini-flash-latest",
        ok: false, kind: "quota", latencyMs: 12}];
      throw err;
    },
  ]);
  const err = await run(store, provider, "how is my training going?")
      .then(() => null, (e) => e);
  assert.ok(err instanceof AiUnavailableError);
  const doc = err.turnUsage;
  assert.equal(doc.status, "error");
  assert.equal(doc.errorKind, "quota");
  assert.equal(doc.terminalState, "provider_error");
  assert.equal(doc.failedProvider, "gemini");
  assert.equal(doc.failedModel, "gemini-flash-latest");
  assert.equal(doc.perCall.length, 1, "the step that did answer is kept");
  assert.equal(doc.tokensIn, 10);
  assert.equal(doc.intent, "training");
  assert.deepEqual(doc.failedTries.map((t) => t.kind), ["quota"]);
  assert.equal(store.logged.length, 0, "the callable logs it, once");
});

test("a malformed request (bad_request) through the router is logged as a " +
    "failed request, not lost", async () => {
  const anthropic = {generate: async () => {
    const e = new Error("messages.0.content: field required");
    e.status = 400;
    throw e;
  }};
  const registry = new ProviderRegistry().register("anthropic", anthropic);
  const meter = new UsageMeter();
  const provider = meter.wrap(stickyProvider(registry, "diet_generate", {}));
  await assert.rejects(() => provider.generate({maxTokens: 1, messages: []}));
  assert.ok(meter.used);
  const record = buildUsageRecord({feature: "diet_generate", meter,
    dayKey: "2026-09-26", startedAt: new Date(0), finishedAt: new Date(5),
    error: Object.assign(new Error("x"), {status: 400})});
  assert.equal(record.status, "error");
  assert.equal(record.errorKind, "bad_request");
  assert.equal(record.failedProvider, "anthropic");
  assert.equal(record.failedModel, "claude-sonnet-5");
});

test("a metered request records one perCall row per model call", async () => {
  const gemini = {generate: async () => ({stopReason: "end", content: [],
    usage: {inputTokens: 7, outputTokens: 3, cacheReadTokens: 2,
      cacheWriteTokens: 0}})};
  const registry = new ProviderRegistry().register("gemini", gemini);
  const meter = new UsageMeter();
  const provider = meter.wrap({generate: (req, opts) => generate(registry,
      "diet_generate", req, opts, {preferModel: "gemini-flash"})});
  await provider.generate({maxTokens: 1, messages: []});
  const record = buildUsageRecord({feature: "diet_generate", meter,
    dayKey: "2026-09-26", startedAt: new Date(0), finishedAt: new Date(5)});
  assert.equal(record.schemaVersion, 7);
  assert.equal(record.perCall.length, 1);
  assert.equal(record.perCall[0].provider, "gemini");
  assert.equal(record.perCall[0].inputTokens, 7);
  assert.equal(record.provider, "gemini");
});

test("the reasoning plan is fixed for every step of the turn and logged; " +
    "off, it sends nothing new", async () => {
  const store = makeStore();
  const provider = scriptedProvider([toolUse("get_workouts"), answer("ok")]);
  await run(store, provider, "how is my bench progressing?",
      {config: {reasoning: {mode: "auto"}}});
  assert.deepEqual(provider.requests.map((r) => [r.modelKey, r.reasoning]),
      [["claude-sonnet", "high"], ["claude-sonnet", "high"]]);
  assert.deepEqual(store.logged[0].reasoning, {tier: "deep",
    model: "claude-sonnet", level: "high", reason: "decision"});

  const lookup = makeStore();
  const lookupProvider = scriptedProvider([answer("hey!")]);
  await run(lookup, lookupProvider, "hi", {config: {reasoning: {mode: "auto"}}});
  assert.equal(lookupProvider.requests[0].modelKey, "claude-haiku");
  assert.equal(lookupProvider.requests[0].reasoning, "low");

  const off = makeStore();
  const offProvider = scriptedProvider([answer("ok")]);
  await run(off, offProvider, "how is my bench progressing?");
  assert.equal(offProvider.requests[0].modelKey, undefined);
  assert.equal(offProvider.requests[0].reasoning, undefined);
  assert.equal(off.logged[0].reasoning, null);
});

test("a forced plan (the eval's variants) applies to every turn; a Gemini " +
    "user gets no Claude plan", async () => {
  const store = makeStore();
  const provider = scriptedProvider([answer("ok")]);
  await run(store, provider, "hi", {config: {reasoning: {mode: "off",
    override: {model: "claude-sonnet", level: "low"}}}});
  assert.equal(provider.requests[0].modelKey, "claude-sonnet");
  assert.equal(provider.requests[0].reasoning, "low");

  const gemini = makeStore();
  const geminiProvider = scriptedProvider([answer("ok")]);
  await run(gemini, geminiProvider, "hi", {model: "gemini-flash-latest",
    config: {reasoning: {mode: "auto"}}});
  assert.equal(geminiProvider.requests[0].modelKey, undefined);
  assert.equal(gemini.logged[0].reasoning, null);
});
