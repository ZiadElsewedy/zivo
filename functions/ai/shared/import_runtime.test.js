/**
 * Offline unit tests for `./import_runtime.js` — the per-instance idempotency +
 * cancellation registry behind the plan importers. No network, no Firebase.
 */

const assert = require("node:assert/strict");
const {test, afterEach} = require("node:test");

const {
  importKey,
  runImportOnce,
  cancelImport,
  _resetImportRuntime,
} = require("./import_runtime");

afterEach(() => _resetImportRuntime());

test("importKey is null without an executionId (no dedup/cancel), else uid:id", () => {
  assert.equal(importKey("u1", undefined), null);
  assert.equal(importKey("u1", ""), null);
  assert.equal(importKey("u1", "e1"), "u1:e1");
});

test("runImportOnce runs the model exactly once for a shared key", async () => {
  let runs = 0;
  const run = async () => {
    runs++;
    await new Promise((r) => setTimeout(r, 10));
    return {ok: true, n: runs};
  };
  const key = importKey("u1", "e1");
  // Two concurrent invocations (e.g. the stream call + the buffered fallback).
  const [a, b] = await Promise.all([
    runImportOnce(key, run),
    runImportOnce(key, run),
  ]);
  assert.equal(runs, 1); // one model run, not two
  assert.deepEqual(a, b); // both got the same result
});

test("a settled result is retrievable by a later duplicate (buffered salvage)", async () => {
  let runs = 0;
  const run = async () => {
    runs++;
    return {ok: true};
  };
  const key = importKey("u1", "e2");
  await runImportOnce(key, run);
  // The stream failed to parse; the client retries buffered on the same id.
  const again = await runImportOnce(key, run);
  assert.equal(runs, 1);
  assert.deepEqual(again, {ok: true});
});

test("a null key never dedups — each call runs", async () => {
  let runs = 0;
  const run = async () => (runs++, {ok: true});
  await runImportOnce(null, run);
  await runImportOnce(null, run);
  assert.equal(runs, 2);
});

test("cancelImport aborts the in-flight run's signal", async () => {
  const key = importKey("u1", "e3");
  let sawAbort = false;
  const started = runImportOnce(key, (signal) =>
    new Promise((resolve) => {
      signal.addEventListener("abort", () => {
        sawAbort = true;
        resolve({ok: false, aborted: true});
      });
    }),
  );
  // Give the run a tick to register its listener.
  await new Promise((r) => setTimeout(r, 5));
  assert.equal(cancelImport(key), true);
  const result = await started;
  assert.equal(sawAbort, true);
  assert.deepEqual(result, {ok: false, aborted: true});
});

test("cancelImport returns false when there is no live run (or no key)", () => {
  assert.equal(cancelImport(null), false);
  assert.equal(cancelImport("u1:nope"), false);
});
