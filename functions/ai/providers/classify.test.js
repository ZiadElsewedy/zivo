/**
 * Offline unit tests for `./classify.js` — the predicate that decides whether
 * a provider error is worth failing over (a real provider failure) or should
 * be rethrown (a 4xx the provider deliberately rejected).
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  isProviderFailure,
  classifyProviderError,
  isTransientFailure,
  canFallBackFor,
} = require("./classify");

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

test("a plain 400/422 is NOT a provider failure (rethrow, don't mask)", () => {
  assert.equal(isProviderFailure(apiError(400)), false); // bad request / schema
  assert.equal(isProviderFailure(apiError(422)), false);
});

test("the provider refusing to serve US falls back: key, billing, model", () => {
  assert.equal(classifyProviderError(apiError(401)), "auth");
  assert.equal(classifyProviderError(apiError(403)), "auth");
  assert.equal(classifyProviderError(apiError(402)), "billing");
  assert.equal(classifyProviderError(apiError(404)), "model_unavailable");
  for (const s of [401, 402, 403, 404]) {
    assert.equal(isProviderFailure(apiError(s)), true, String(s));
  }
});

test("Anthropic's out-of-credit 400 is billing, not a bad request", () => {
  const err = apiError(400);
  err.message = "400 {\"type\":\"error\",\"error\":{\"type\":" +
    "\"invalid_request_error\",\"message\":\"Your credit balance is too " +
    "low to access the Anthropic API. Please go to Plans & Billing.\"}}";
  assert.equal(classifyProviderError(err), "billing");
});

test("Gemini quota exhaustion and a bad Gemini key are classified", () => {
  const quota = apiError(429);
  quota.message = "{\"error\":{\"status\":\"RESOURCE_EXHAUSTED\"}}";
  assert.equal(classifyProviderError(quota), "quota");
  const key = apiError(400);
  key.message = "API key not valid. Please pass a valid API key.";
  assert.equal(classifyProviderError(key), "auth");
});

test("overload and plain rate limits are their own kinds", () => {
  assert.equal(classifyProviderError(apiError(529)), "overloaded");
  assert.equal(classifyProviderError(apiError(429)), "rate_limit");
  assert.equal(classifyProviderError(apiError(500)), "server");
});

test("Gemini's real free-tier 429 is QUOTA, not billing — even though its " +
    "text mentions billing", () => {
  // Verbatim shape of the production error (Cloud Logging, 2026-09-24).
  const err = apiError(429);
  err.message = JSON.stringify({error: {code: 429, message:
    "You exceeded your current quota, please check your plan and billing " +
    "details. For more information on this error, head to: " +
    "https://ai.google.dev/gemini-api/docs/rate-limits.\n* Quota exceeded " +
    "for metric: generativelanguage.googleapis.com/" +
    "generate_content_free_tier_requests, limit: 20, model: " +
    "gemini-3.8-flash\nPlease retry in 15.769637942s.",
  status: "RESOURCE_EXHAUSTED"}});
  assert.equal(classifyProviderError(err), "quota");
  assert.equal(isTransientFailure("quota"), false, "no same-provider retry");
  assert.equal(canFallBackFor("quota"), true, "but the other provider runs");
});

test("Anthropic out of credit stays billing; only bad_request can't fall " +
    "back", () => {
  const credit = apiError(400);
  credit.message = "Your credit balance is too low to access the API.";
  assert.equal(classifyProviderError(credit), "billing");
  for (const kind of ["billing", "auth", "model_unavailable", "quota",
    "rate_limit", "overloaded", "server", "timeout", "network"]) {
    assert.equal(canFallBackFor(kind), true, kind);
  }
  assert.equal(canFallBackFor("bad_request"), false);
});
