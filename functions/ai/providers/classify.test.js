/**
 * Offline unit tests for `./classify.js` — the predicate that decides whether
 * a provider error is worth failing over (a real provider failure) or should
 * be rethrown (a 4xx the provider deliberately rejected).
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {isProviderFailure} = require("./classify");

/**
 * @param {number} status
 * @return {!Error} An error carrying that HTTP status, like an SDK API error.
 */
function apiError(status) {
  const err = new Error(`HTTP ${status}`);
  err.status = status;
  return err;
}

test("5xx, 429, and no-status errors are provider failures (fail over)", () => {
  assert.equal(isProviderFailure(apiError(500)), true);
  assert.equal(isProviderFailure(apiError(503)), true);
  assert.equal(isProviderFailure(apiError(429)), true); // rate limit / quota
  assert.equal(isProviderFailure(new Error("ECONNRESET")), true); // no status
});

test("a timeout / abort is a provider failure", () => {
  const abort = new Error("aborted");
  abort.name = "AbortError";
  assert.equal(isProviderFailure(abort), true);
  assert.equal(isProviderFailure(new Error("Request timed out")), true);
});

test("a 4xx (other than 429) is NOT a provider failure (rethrow, don't mask)", () => {
  assert.equal(isProviderFailure(apiError(400)), false); // bad request / schema
  assert.equal(isProviderFailure(apiError(401)), false); // bad key
  assert.equal(isProviderFailure(apiError(404)), false);
  assert.equal(isProviderFailure(apiError(422)), false);
});
