/**
 * Consistency tests for ./store.js — the Admin-SDK Firestore adapter.
 *
 * Run with: node --test ai/store.test.js  (from functions/).
 *
 * `FirestoreStore` cannot be unit-tested without an emulator, so these check
 * the one thing that IS statically checkable and that actually broke: the
 * collection names.
 *
 * ## The bug this exists for
 *
 * `listBodyWeights` read `bodyWeights`. Every writer — the client's
 * `FirestoreBodyWeightRepository`, and the rule declaring it — uses
 * `bodyWeightEntries`. So the read hit a collection nothing has ever written
 * and returned `[]` forever.
 *
 * What made it survive is that it failed **silently**: "this user has logged
 * no weigh-ins" is a legitimate state that every consumer downstream handles
 * gracefully, so the coach simply lost its measured-maintenance calibration
 * and its current weight and fell back to estimates, with nothing anywhere
 * looking wrong. A typo'd collection name has no failure mode in Firestore —
 * reads succeed and return nothing — which is exactly why it needs a test that
 * doesn't depend on noticing.
 *
 * ## What this proves, and what it doesn't
 *
 * PROVES: every collection `store.js` names is one the app actually declares.
 * DOESN'T: that the FIELDS match, or that the client writes what the server
 * expects. Those need the emulator. This is the cheap check that would have
 * caught the real bug, not a substitute for integration coverage.
 */

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");

const storeSource = readFileSync(join(__dirname, "store.js"), "utf8");
const rulesSource =
  readFileSync(join(__dirname, "..", "..", "..", "firestore.rules"), "utf8");

/** Every `collection("x")` literal in store.js. */
const collectionsUsed = [
  ...storeSource.matchAll(/\.collection\("([^"]+)"\)/g),
].map((m) => m[1]);

/**
 * Every non-wildcard path segment named by a `match` in firestore.rules —
 * which is exactly the set of collection names the app declares, including
 * nested ones like `messages` and `pendingActions`.
 */
const collectionsDeclared = new Set(
    [...rulesSource.matchAll(/match\s+\/([^\s{]*(?:\{[^}]*\}[^\s{]*)*)\s*\{/g)]
        .flatMap((m) => m[1].split("/"))
        .filter((seg) => seg && !seg.startsWith("{")),
);

test("store.js reads at least one collection (the parser still works)", () => {
  // Guards the test itself: if the regex ever stops matching, the assertions
  // below would pass vacuously and this file would quietly stop protecting
  // anything.
  assert.ok(
      collectionsUsed.length >= 10,
      `expected store.js to name many collections, found ${collectionsUsed.length}`,
  );
  assert.ok(
      collectionsDeclared.size >= 15,
      `expected firestore.rules to declare many collections, found ` +
      `${collectionsDeclared.size}`,
  );
});

test("every collection store.js touches is declared in firestore.rules", () => {
  const undeclared = [...new Set(collectionsUsed)]
      .filter((name) => !collectionsDeclared.has(name));
  assert.deepEqual(
      undeclared,
      [],
      "store.js reads collection(s) that no rule declares — either a typo " +
      "(the `bodyWeights` bug) or a collection missing its rule + rule test: " +
      undeclared.join(", "),
  );
});

test("weigh-ins come from bodyWeightEntries, the collection clients write", () => {
  // Pinned by name rather than only by the general check above, because this
  // is the specific regression and the general check would also pass if
  // someone "fixed" it by adding a rule for the wrong collection.
  const body = storeSource.split("async listBodyWeights(uid) {")[1] || "";
  assert.match(
      body.split("}")[0],
      /\.collection\("bodyWeightEntries"\)/,
      "listBodyWeights must read `bodyWeightEntries`",
  );
  assert.ok(
      !/\.collection\("bodyWeights"\)/.test(storeSource),
      "`bodyWeights` is not a collection anything writes",
  );
});

// --- The daily chat cap counts chat turns only -------------------------------

/**
 * The smallest Admin-SDK look-alike `getTodayUsageTotals` needs: one aiUsage
 * query returning `docs`.
 * @param {!Array<!Object>} docs
 * @return {!Object}
 */
function fakeUsageDb(docs) {
  const snap = {forEach: (fn) => docs.forEach((d) => fn({data: () => d}))};
  return {
    collection: () => ({
      doc: () => ({
        collection: () => ({where: () => ({get: async () => snap})}),
      }),
    }),
  };
}

test("the chat cap ignores other features' usage and failed turns", async () => {
  const {FirestoreStore} = require("./store");
  const store = new FirestoreStore(fakeUsageDb([
    {tokensIn: 100, tokensOut: 10}, // legacy chat turn (no feature)
    {feature: "chat", status: "ok", tokensIn: 50, tokensOut: 5},
    {feature: "diet_import", status: "ok", tokensIn: 90000, tokensOut: 4000},
    {feature: "transcribe", status: "ok", tokensIn: 300, tokensOut: 20},
    {feature: "chat", status: "error", tokensIn: 0, tokensOut: 0},
  ]));
  const totals = await store.getTodayUsageTotals("u", "2026-09-23");
  assert.deepEqual(totals, {turns: 2, tokens: 165});
});

test("the chat cap counts fresh tokens — cache reads of ZIVO's own prompt " +
    "don't eat the allowance", async () => {
  const {FirestoreStore} = require("./store");
  // The real shape of 2026-09-24: 11 turns, ~84% of input cache reads.
  const turn = {feature: "chat", status: "ok", tokensIn: 51180,
    cacheReadTokens: 42787, tokensOut: 534};
  const store = new FirestoreStore(fakeUsageDb(Array(11).fill(turn)));
  const totals = await store.getTodayUsageTotals("u", "2026-09-24");
  assert.equal(totals.turns, 11);
  assert.equal(totals.tokens, 11 * (51180 - 42787 + 534));
  // Counted the old way this was 568,854 — over the 500K ceiling.
  assert.ok(totals.tokens < 500000);
});
