/**
 * Offline tests for the prefetch (`prefetch.js`): which turns get a read run
 * before the first model call, and what the turn does with it.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {prefetchFor, namesOtherDay} = require("./prefetch");
const {ContextLedger} = require("./context_ledger");
const {runAiTurn} = require("./turn");

const NOW = new Date(Date.UTC(2026, 8, 26, 12));

/**
 * A ledger holding the given (tool, input) lookups.
 * @param {!Array<!Array>} entries
 * @return {!ContextLedger}
 */
function ledgerWith(entries) {
  const ledger = new ContextLedger([]);
  for (const [tool, input] of entries) {
    ledger.record(tool, input || {}, "{}", NOW, "2026-09-26");
  }
  return ledger;
}

const plan = (routed, message, extra) => prefetchFor(Object.assign({
  routed, message: message || "", ledger: ledgerWith([]),
}, extra || {}));

test("a confident diet turn prefetches today's get_diet", () => {
  for (const reason of ["keywords", "entry_point", "continuity"]) {
    assert.deepEqual(plan({intent: "diet", reason}, "protein left?"),
        {tool: "get_diet", input: {}});
  }
});

test("no prefetch when the ledger already holds today's diet state", () => {
  for (const held of [["get_today"], ["get_diet"]]) {
    assert.equal(plan({intent: "diet", reason: "keywords"}, "what's left?",
        {ledger: ledgerWith([held])}), null);
  }
  // A past day's read is not today's state.
  assert.deepEqual(plan({intent: "diet", reason: "keywords"}, "what's left?",
      {ledger: ledgerWith([["get_diet", {day: "2026-09-25"}]])}),
  {tool: "get_diet", input: {}});
});

test("no prefetch for a question about another day", () => {
  for (const m of ["what did I eat yesterday?", "my diet last week",
    "كلت ايه امبارح", "الدايت الاسبوع ده", "akalt eh embare7"]) {
    assert.ok(namesOtherDay(m), m);
    assert.equal(plan({intent: "diet", reason: "keywords"}, m), null, m);
  }
  assert.ok(!namesOtherDay("how much protein is left today?"));
});

test("the readiness entry point prefetches get_readiness; other training " +
    "turns guess nothing", () => {
  assert.deepEqual(plan({intent: "training", reason: "entry_point"}, "why?",
      {entryPoint: "readiness"}), {tool: "get_readiness", input: {}});
  assert.deepEqual(plan({intent: "training", reason: "keywords"},
      "should I train hard?", {entryPoint: " Readiness "}),
  {tool: "get_readiness", input: {}});
  assert.equal(plan({intent: "training", reason: "entry_point"}, "why?",
      {entryPoint: "readiness",
        ledger: ledgerWith([["get_readiness"]])}), null);
  assert.equal(plan({intent: "training", reason: "keywords"}, "bench?"),
      null);
  assert.equal(plan({intent: "training", reason: "entry_point"}, "hm",
      {entryPoint: "workout"}), null);
});

test("a training decision about today prefetches get_readiness — the call " +
    "plus the training facts it must be grounded in", () => {
  for (const m of ["should I go to the gym today?", "أروح الجيم النهارده؟",
    "اتمرن ولا اريح النهارده؟"]) {
    assert.deepEqual(plan({intent: "training", reason: "keywords"}, m),
        {tool: "get_readiness", input: {}}, m);
  }
  // Not a decision, or not about today: nothing guessed.
  assert.equal(plan({intent: "training", reason: "keywords"},
      "what did I train last week?"), null);
  assert.equal(plan({intent: "training", reason: "keywords"},
      "should I have trained yesterday?"), null);
  // Already read this conversation: not read again.
  assert.equal(plan({intent: "training", reason: "keywords"},
      "should I train today?",
      {ledger: ledgerWith([["get_readiness"]])}), null);
});

test("ambiguous, general, money and bound picks never prefetch", () => {
  assert.equal(plan({intent: "ambiguous", reason: "no_signal"}, "hm"), null);
  assert.equal(plan({intent: "general", reason: "general"}, "hi"), null);
  assert.equal(plan({intent: "money", reason: "keywords"}, "spent?"), null);
  assert.equal(plan({intent: "diet", reason: "bound_choice"}, "Feta"), null);
  assert.equal(prefetchFor({routed: null, message: "", ledger: ledgerWith([])}),
      null);
});

// ---- In a turn ------------------------------------------------------------

/**
 * An in-memory store with just enough diet and training data for the reads.
 * @param {!Object=} overrides
 * @return {!Object}
 */
function makeStore(overrides) {
  const messages = [];
  const logged = [];
  return Object.assign({
    messages,
    logged,
    reads: [],
    appendMessage: async (uid, conv, m) => {
      messages.push(m);
    },
    touchConversation: async () => {},
    getTodayUsageTotals: async () => ({turns: 0, tokens: 0}),
    getRecentMessages: async () =>
      messages.map((m) => Object.assign({}, m)),
    findMessageByClientTurnId: async () => null,
    logUsage: async (uid, doc) => {
      logged.push(doc);
    },
    getActiveDietPlan: async function() {
      this.reads.push("getActiveDietPlan");
      return null;
    },
    listDietEntries: async () => [],
    listFoodLogs: async () => [],
    getDietTargets: async () => ({kcal: 2200, proteinG: 150}),
    listWorkouts: async () => [],
    listWorkoutSessions: async () => [],
    listSleepNights: async () => [],
    listBodyWeights: async () => [],
    getActiveWorkoutPlan: async () => null,
    listExerciseAliases: async () => [],
  }, overrides || {});
}

/**
 * A provider replaying `steps`, recording every request.
 * @param {!Array<!Object>} steps
 * @return {!Object}
 */
function scriptedProvider(steps) {
  const requests = [];
  let i = 0;
  return {
    requests,
    generate: async (req) => {
      requests.push(JSON.parse(JSON.stringify(req)));
      return Object.assign({provider: "anthropic", model: "claude-sonnet-5",
        modelKey: "claude-sonnet"}, steps[Math.min(i++, steps.length - 1)]);
    },
  };
}

const answer = (text) => ({
  stopReason: "end",
  content: [{type: "text", text, raw: {type: "text", text}}],
  usage: {inputTokens: 5, outputTokens: 5, cacheReadTokens: 0,
    cacheWriteTokens: 0},
});

const run = (store, provider, message, extra) => runAiTurn(Object.assign({
  store, provider, uid: "user-1", conversationId: "conv-1", message,
  now: () => NOW, clientClock: {offsetMinutes: 0},
}, extra || {}));

/**
 * @param {!Object} provider
 * @return {string} The first request's last (user) message text.
 */
const firstUserText = (provider) =>
  provider.requests[0].messages.at(-1).content;

test("a diet question reaches the model with today's plan already read — " +
    "one model call, recorded as prefetched and carried on", async () => {
  const store = makeStore();
  const provider = scriptedProvider([answer("Plenty left for today.")]);
  const events = [];
  const result = await run(store, provider, "how much protein do I have left?",
      {onEvent: (e) => events.push(e)});

  assert.equal(result.status, "ok");
  assert.equal(provider.requests.length, 1);
  const sent = firstUserText(provider);
  assert.match(sent, /^\[EARLIER RESULTS/);
  assert.match(sent, /• get_diet \{\} — read just now:/);
  assert.ok(sent.endsWith("how much protein do I have left?"));

  const doc = store.logged[0];
  assert.equal(doc.intent, "diet");
  assert.equal(doc.prefetched.length, 1);
  assert.equal(doc.prefetched[0].name, "get_diet");
  assert.equal(doc.prefetched[0].status, "ok");
  assert.ok(doc.prefetched[0].resultChars > 0);
  assert.equal(doc.contextCarried, 0, "nothing came from an earlier turn");

  // The user sees the read, and the next turn can reuse it.
  assert.deepEqual(events.filter((e) => e.type === "step"), [
    {type: "step", tool: "get_diet", status: "running"},
    {type: "step", tool: "get_diet", status: "ok"},
  ]);
  const reply = store.messages.at(-1);
  assert.deepEqual(reply.activity, [{tool: "get_diet", status: "ok"}]);
  assert.deepEqual(reply.context.entries.map((e) => e.tool), ["get_diet"]);

  // The follow-up carries it rather than reading again.
  const next = scriptedProvider([answer("Carbs look fine too.")]);
  await run(store, next, "and carbs?");
  assert.equal(store.reads.length, 1, "no second plan read");
  assert.equal(store.logged[1].prefetched, undefined);
});

test("a failed prefetch is dropped: the turn runs, the model can still read",
    async () => {
      const store = makeStore({
        getActiveDietPlan: async () => {
          throw new Error("firestore down");
        },
      });
      const provider = scriptedProvider([answer("Let me try again later.")]);
      const result = await run(store, provider, "what's my next meal?");
      assert.equal(result.status, "ok");
      assert.doesNotMatch(firstUserText(provider), /EARLIER RESULTS/);
      assert.equal(store.logged[0].prefetched[0].status, "error");
      assert.deepEqual(store.messages.at(-1).activity,
          [{tool: "get_diet", status: "error"}]);
    });

test("Ask opened from Readiness: an unlabelled 'why?' routes training and " +
    "arrives with the readiness call", async () => {
  const store = makeStore();
  const provider = scriptedProvider([answer("Sleep was short.")]);
  await run(store, provider, "why?", {entryPoint: "readiness"});
  const doc = store.logged[0];
  assert.equal(doc.intent, "training");
  assert.equal(doc.intentReason, "entry_point");
  assert.equal(doc.prefetched[0].name, "get_readiness");
  assert.match(firstUserText(provider), /• get_readiness \{\}/);
});

test("a general or ambiguous turn runs no read before the model", async () => {
  for (const message of ["hi", "how am I doing?"]) {
    const store = makeStore();
    const provider = scriptedProvider([answer("ok")]);
    await run(store, provider, message);
    assert.equal(store.logged[0].prefetched, undefined, message);
    assert.equal(store.reads.length, 0, message);
  }
});
