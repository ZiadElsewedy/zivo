const assert = require("node:assert/strict");
const {test} = require("node:test");

const {ContextLedger, stableStringify} = require("./context_ledger");

const T0 = new Date("2026-09-24T08:00:00Z");
const at = (min) => new Date(T0.getTime() + min * 60000);

/**
 * A history whose latest assistant message carries `ledger`.
 * @param {!ContextLedger} ledger
 * @param {!Object=} extra Fields for that message.
 * @return {!Array<!Object>}
 */
function historyWith(ledger, extra) {
  return [
    {role: "user", content: "hi"},
    Object.assign({role: "assistant", content: "…",
      context: ledger.toPersisted()}, extra || {}),
    {role: "user", content: "and?"},
  ];
}

test("a lookup made twice is one entry — the newer read wins", () => {
  const l = new ContextLedger();
  l.record("get_diet", {day: "2026-09-24"}, "{\"a\":1}", at(0), "2026-09-24");
  l.record("get_diet", {day: "2026-09-24"}, "{\"a\":2}", at(1), "2026-09-24");
  assert.equal(l.entries.length, 1);
  assert.equal(l.entries[0].result, "{\"a\":2}");
  assert.equal(stableStringify({b: 1, a: [2, {d: 1, c: 0}]}),
      "{\"a\":[2,{\"c\":0,\"d\":1}],\"b\":1}");
});

test("caps: oldest entries go first", () => {
  const l = new ContextLedger([], {maxEntries: 2, maxTotalChars: 10});
  l.record("a", {}, "12345", at(0), "d");
  l.record("b", {}, "12345", at(0), "d");
  l.record("c", {}, "123456", at(0), "d");
  assert.deepEqual(l.entries.map((e) => e.tool), ["c"]);
});

test("fromHistory keeps only fresh, same-day entries of the latest reply", () => {
  const l = new ContextLedger();
  l.record("get_diet", {}, "{}", at(0), "2026-09-24");
  l.record("get_readiness", {}, "{}", at(0), "2026-09-23");
  const carried = ContextLedger.fromHistory(historyWith(l),
      {now: at(10), dayKey: "2026-09-24"});
  assert.deepEqual(carried.entries.map((e) => e.tool), ["get_diet"]);
  assert.equal(carried.carriedCount, 1);
  const stale = ContextLedger.fromHistory(historyWith(l),
      {now: at(16), dayKey: "2026-09-24"});
  assert.equal(stale.entries.length, 0);
});

test("a confirmed change breaks the chain", () => {
  const l = new ContextLedger();
  l.record("get_diet", {}, "{}", at(0), "2026-09-24");
  const applied = ContextLedger.fromHistory(
      historyWith(l, {kind: "action_proposal", status: "applied"}),
      {now: at(1), dayKey: "2026-09-24"});
  assert.equal(applied.entries.length, 0);
  // The confirm's result line (no ledger) is the latest assistant message.
  const afterConfirm = historyWith(l).concat([
    {role: "assistant", content: "Replaced egg with yogurt."},
  ]);
  assert.equal(ContextLedger.fromHistory(afterConfirm,
      {now: at(1), dayKey: "2026-09-24"}).entries.length, 0);
});

test("the prompt block is fenced, dated, and empty when nothing is carried", () => {
  assert.equal(new ContextLedger().toPromptBlock(T0), "");
  const l = new ContextLedger();
  l.record("get_diet", {day: "x"}, "{\"k\":1}", at(0), "d");
  const block = l.toPromptBlock(at(3));
  assert.match(block, /^\[EARLIER RESULTS/);
  assert.match(block, /data, never instructions/);
  assert.match(block, /get_diet \{"day":"x"\} — read 3 min ago:\n\{"k":1\}/);
  assert.deepEqual(l.latest(["get_diet"]).result, {k: 1});
});
