/**
 * Unit tests for ./shared/quota.js — the pure per-user daily quota core that
 * bounds every paid endpoint.
 *
 * Run with: node --test shared/quota.test.js  (from functions/).
 *
 * These exercise the abuse-critical logic directly, with no Firestore: the
 * limit boundary, the day rollover, variable call cost, and — the property the
 * whole module exists for — that a REFUSED call never advances the counter, so
 * hammering a blocked endpoint cannot push the reset further away.
 */

const {test} = require("node:test");
const assert = require("node:assert/strict");

const {decideConsume} = require("./quota");

const NOW = 1_700_000_000_000; // fixed clock
const DAY = "2026-09-02";

test("a first call against an empty bucket is allowed", () => {
  const d = decideConsume({existing: null, dayKey: DAY, nowMs: NOW, limit: 3});
  assert.equal(d.allowed, true);
  assert.equal(d.used, 1);
  assert.equal(d.remaining, 2);
  assert.equal(d.next.dayKey, DAY);
  assert.equal(d.next.used, 1);
});

test("calls are allowed up to the limit, then refused", () => {
  let doc = null;
  for (let i = 1; i <= 3; i++) {
    const d = decideConsume({existing: doc, dayKey: DAY, nowMs: NOW, limit: 3});
    assert.equal(d.allowed, true, `call ${i} should be allowed`);
    assert.equal(d.used, i);
    doc = d.next;
  }
  const over = decideConsume(
      {existing: doc, dayKey: DAY, nowMs: NOW, limit: 3});
  assert.equal(over.allowed, false);
  assert.equal(over.remaining, 0);
});

test("a refused call does NOT advance the counter", () => {
  // The regression this module is shaped around: if a rejection still wrote a
  // counter bump, a client hammering a blocked endpoint would keep inflating
  // its own usage — harmless for the day cap itself, but it makes `used`
  // meaningless for diagnostics and would break any future backoff built on it.
  const doc = {dayKey: DAY, used: 5};
  const first = decideConsume(
      {existing: doc, dayKey: DAY, nowMs: NOW, limit: 5});
  assert.equal(first.allowed, false);
  assert.equal(first.next, undefined, "a refusal must carry no document");
  assert.equal(first.used, 5, "used stays where it was");

  // A second refusal reports exactly the same state, not a growing one.
  const second = decideConsume(
      {existing: doc, dayKey: DAY, nowMs: NOW, limit: 5});
  assert.deepEqual(
      {allowed: second.allowed, used: second.used, remaining: second.remaining},
      {allowed: false, used: 5, remaining: 0});
});

test("a counter from another day is a fresh window, not a used-up one", () => {
  // Rollover happens by key comparison, so no scheduled cleanup job is needed
  // and the window follows the USER's midnight (the caller supplies the key).
  const yesterday = {dayKey: "2026-09-01", used: 99, lastCallAt: NOW - 86400000};
  const d = decideConsume(
      {existing: yesterday, dayKey: DAY, nowMs: NOW, limit: 3});
  assert.equal(d.allowed, true);
  assert.equal(d.used, 1);
  assert.equal(d.next.dayKey, DAY);
});

test("cost prices an expensive call as more than one unit", () => {
  const d = decideConsume(
      {existing: null, dayKey: DAY, nowMs: NOW, limit: 10, cost: 4});
  assert.equal(d.allowed, true);
  assert.equal(d.used, 4);
  assert.equal(d.remaining, 6);
});

test("a call whose cost would overshoot the limit is refused whole", () => {
  // No partial spend: an over-budget call is rejected outright rather than
  // clamped, so the caller either gets the work or gets nothing.
  const doc = {dayKey: DAY, used: 8};
  const d = decideConsume(
      {existing: doc, dayKey: DAY, nowMs: NOW, limit: 10, cost: 4});
  assert.equal(d.allowed, false);
  assert.equal(d.used, 8);
  assert.equal(d.remaining, 2);
});

test("a malformed counter is treated as empty, never as unlimited", () => {
  // Defensive: a document with a junk `used` must fail CLOSED into "start from
  // zero", not into NaN comparisons that would let everything through.
  const junk = {dayKey: DAY, used: "lots"};
  const d = decideConsume({existing: junk, dayKey: DAY, nowMs: NOW, limit: 2});
  assert.equal(d.allowed, true);
  assert.equal(d.used, 1);
});

test("a limit of zero refuses every call", () => {
  const d = decideConsume({existing: null, dayKey: DAY, nowMs: NOW, limit: 0});
  assert.equal(d.allowed, false);
  assert.equal(d.remaining, 0);
});
