/**
 * Per-instance execution registry for the plan importers — the server half of
 * the client's `executionId`. It does two jobs, both keyed by
 * `${uid}:${executionId}`:
 *
 *  1. **Idempotency.** One expensive model run per attempt. A duplicated
 *     invocation — a client/transport retry, or the buffered fallback the
 *     client fires when a `.stream()` connection can't be parsed (the Functions
 *     emulator, a dropped SSE) — attaches to the SAME in-flight/settled run
 *     instead of paying for a second whole-document extraction. This is what
 *     stops "one import billed twice".
 *
 *  2. **Cancellation.** Each run gets an `AbortController` the `aiCancelImport`
 *     callable trips, so pressing X aborts the in-flight generation regardless
 *     of transport (a buffered `.call()` can't be cancelled client-side, and
 *     the emulator can't stream) — the cancel is a separate request, not a
 *     connection close.
 *
 * In-memory is enough for the common cases: a warm instance (a fast client
 * retry lands there) and the emulator's single instance. Cross-instance dedup
 * or cancel would need a shared store (Firestore) — deferred until logs show
 * it's needed. Entries are dropped shortly after they settle so this can't grow
 * without bound.
 */

const TTL_MS = 5 * 60 * 1000;

/** @type {!Map<string, {promise: !Promise<*>}>} */
const inflight = new Map();
/** @type {!Map<string, !AbortController>} */
const controllers = new Map();

/**
 * The registry key for a user's import attempt, or null when there is no
 * executionId (an old client) — such a call runs normally, just without dedup
 * or cancellation.
 * @param {string} uid
 * @param {(string|undefined)} executionId
 * @return {?string}
 */
function importKey(uid, executionId) {
  return executionId ? `${uid}:${executionId}` : null;
}

/**
 * Runs [run] exactly once per [key], returning the shared result to any later
 * caller with the same key. [run] receives an `AbortSignal` that
 * [cancelImport] trips. With a null [key] there is nothing to dedup or cancel,
 * so [run] is called with a fresh, never-tripped signal.
 * @param {?string} key
 * @param {function(!AbortSignal): !Promise<T>} run
 * @return {!Promise<T>}
 * @template T
 */
function runImportOnce(key, run) {
  if (!key) return run(new AbortController().signal);

  const existing = inflight.get(key);
  if (existing) return existing.promise;

  const controller = new AbortController();
  controllers.set(key, controller);
  const promise = Promise.resolve().then(() => run(controller.signal));
  inflight.set(key, {promise});

  const cleanup = () => {
    controllers.delete(key);
    // Keep the settled result briefly so a buffered fallback arriving just
    // after can still retrieve it, then drop it.
    setTimeout(() => {
      const cur = inflight.get(key);
      if (cur && cur.promise === promise) inflight.delete(key);
    }, TTL_MS).unref?.();
  };
  promise.then(cleanup, cleanup);
  return promise;
}

/**
 * Aborts the run registered under [key], if one is in flight. Returns whether a
 * run was found to cancel (false is normal — it may have finished, or be on
 * another instance).
 * @param {?string} key
 * @return {boolean}
 */
function cancelImport(key) {
  if (!key) return false;
  const controller = controllers.get(key);
  if (!controller) return false;
  controller.abort();
  return true;
}

/**
 * Test-only: clears both registries so one test's runs can't leak into the
 * next.
 */
function _resetImportRuntime() {
  inflight.clear();
  controllers.clear();
}

module.exports = {
  importKey,
  runImportOnce,
  cancelImport,
  _resetImportRuntime,
};
