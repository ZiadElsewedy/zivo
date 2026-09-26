/**
 * Offline tests for the history the model reads (`./messages.js`
 * selectHistory) and the context ledger's budget + scope filter
 * (`./context_ledger.js`).
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {selectHistory} = require("./messages");
const {ContextLedger, DEFAULT_LEDGER_CONFIG} = require("./context_ledger");

const CFG = {charBudget: 1000, verbatimMessages: 4, olderReplyChars: 100};
const NOW = new Date(Date.UTC(2026, 8, 26, 12));

/**
 * Alternating user/assistant messages, oldest first.
 * @param {number} n
 * @param {number=} replyChars Length of each assistant reply.
 * @return {!Array<!Object>}
 */
function conversation(n, replyChars = 50) {
  return Array.from({length: n}, (_, i) => ({
    role: i % 2 === 0 ? "user" : "assistant",
    content: i % 2 === 0 ? `question ${i}` : `${i}:` + "r".repeat(replyChars),
    createdAt: new Date(NOW.getTime() - (n - i) * 60000),
  }));
}

test("the current turn's message is left out — by clientTurnId", () => {
  const history = conversation(4).concat([{role: "user",
    content: "what now?", clientTurnId: "t-9", createdAt: NOW}]);
  const {messages} = selectHistory(history,
      {clientTurnId: "t-9", content: "what now?", createdAt: NOW}, CFG);
  assert.equal(messages.filter((m) => m.content === "what now?").length, 0);
  assert.equal(messages.length, 4);
});

test("the current turn's message is left out — without a clientTurnId, by " +
    "its exact content and timestamp", () => {
  const history = conversation(2).concat(
      [{role: "user", content: "what now?", createdAt: NOW}]);
  const {messages} = selectHistory(history,
      {content: "what now?", createdAt: NOW}, CFG);
  assert.deepEqual(messages.map((m) => m.content),
      ["question 0", "1:" + "r".repeat(50)]);
});

test("the history budget is respected beyond the protected newest messages",
    () => {
      const history = conversation(16, 300);
      const {messages, stats} = selectHistory(history,
          {content: "x", createdAt: NOW}, CFG);
      // The newest 4 are always verbatim…
      const last4 = history.slice(-4).map((m) => m.content);
      assert.deepEqual(messages.slice(-4).map((m) => m.content), last4);
      // …and everything together stays within the budget once they fit.
      const total = messages.reduce((n, m) => n + m.content.length, 0);
      assert.equal(total, stats.chars);
      assert.ok(total <= CFG.charBudget, `total ${total}`);
      assert.ok(stats.dropped > 0);
      assert.equal(messages[0].role, "user", "history starts with the user");
    });

test("older replies are shortened, never user messages or open cards", () => {
  const long = "L".repeat(500);
  const history = [
    {role: "user", content: "U".repeat(300), createdAt: NOW},
    {role: "assistant", content: long, createdAt: NOW},
    {role: "assistant", content: "Pick one", kind: "choice_request",
      status: "pending", fields: {options: [{label: "A", value: "a"},
        {label: "B", value: "b"}]}, createdAt: NOW},
    ...conversation(4),
  ];
  const {messages, stats} = selectHistory(history,
      {content: "x", createdAt: NOW}, {charBudget: 5000, verbatimMessages: 4,
        olderReplyChars: 100});
  const byStart = (p) => messages.find((m) => m.content.startsWith(p));
  assert.equal(byStart("U").content.length, 300, "user words kept whole");
  assert.match(byStart("L").content, /^L{100}… \[earlier reply shortened\]$/);
  assert.match(byStart("Pick one").content, /1\. A \(value: a\)/,
      "a pending choice keeps its options");
  assert.equal(stats.shortened, 1);
});

test("the newest exchange is kept even when it alone exceeds the budget", () => {
  const history = conversation(4, 3000);
  const {messages} = selectHistory(history, {content: "x", createdAt: NOW},
      CFG);
  assert.equal(messages.length, 4);
});

test("a history that would start with a reply drops that reply", () => {
  const history = conversation(6).slice(1); // starts with an assistant
  const {messages} = selectHistory(history, {content: "x", createdAt: NOW},
      {charBudget: 10000, verbatimMessages: 10, olderReplyChars: 100});
  assert.equal(messages[0].role, "user");
});

test("the ledger budget is ~8K characters and is respected", () => {
  assert.equal(DEFAULT_LEDGER_CONFIG.maxTotalChars, 8000);
  const ledger = new ContextLedger([]);
  for (let i = 0; i < 6; i++) {
    ledger.record(`get_${i}`, {i}, "x".repeat(3000), NOW, "2026-09-26");
  }
  assert.ok(ledger.chars <= 8000, `${ledger.chars}`);
  assert.equal(ledger.entries[ledger.entries.length - 1].tool, "get_5",
      "the newest lookup survives");
});

test("the ledger keeps only the lookups of the turn's area", () => {
  const ledger = new ContextLedger([
    {tool: "get_diet", input: "{}", result: "{}", at: 1, dayKey: null},
    {tool: "get_readiness", input: "{}", result: "{}", at: 2, dayKey: null},
  ]);
  const dropped = ledger.retainTools(new Set(["get_readiness"]));
  assert.equal(dropped, 1);
  assert.deepEqual(ledger.entries.map((e) => e.tool), ["get_readiness"]);
  assert.equal(ledger.carriedCount, 1);
});
