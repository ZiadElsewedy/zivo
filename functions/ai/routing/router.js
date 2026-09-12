/**
 * A small, explicit capability → provider/model map, plus a fallback-on-
 * provider-failure policy and a manual-override hook. Every capability lists
 * one or more `{provider, model}` routes in priority order; `generate` tries
 * each in turn, only moving to the next after the current one's `generate`
 * call rejects **with a genuine provider failure** (see `../providers/
 * classify.js`) — a request the provider rejected as malformed (a 4xx) is
 * rethrown, not masked by re-trying it against a different provider.
 *
 * Adding a provider for a capability is one more entry in that capability's
 * list plus a `providers/*.js` adapter — nothing in `../gateway.js`/
 * `../workout_import.js` changes.
 */

const {isProviderFailure} = require("../providers/classify");

/**
 * @typedef {Object} CapabilityRoute
 * @property {string} provider A name registered in a `ProviderRegistry`.
 * @property {string} model The provider-native model id for this route.
 */

/** @const {!Object<string, !Array<!CapabilityRoute>>} */
const CAPABILITY_ROUTES = {
  // Anthropic is primary; Gemini is the fallback, tried only when Anthropic's
  // call fails with a provider failure (outage, 5xx, 429/quota, timeout). A
  // manual selection can force either one directly — see `generate`'s
  // `forceProvider`. `gemini-2.5-pro` is the owner-chosen chat fallback model.
  chat: [
    {provider: "anthropic", model: "claude-sonnet-5"},
    {provider: "gemini", model: "gemini-2.5-pro"},
  ],
  // The PDF importers stream partial tool INPUT for their progress UI (a path
  // only the Anthropic adapter emits today), so they stay single-route until a
  // Gemini import path is validated — adding it is one entry here.
  workout_import: [{provider: "anthropic", model: "claude-sonnet-5"}],
  diet_import: [{provider: "anthropic", model: "claude-sonnet-5"}],
};

/**
 * The routes for `capability`, optionally narrowed to a single provider for a
 * manual override. Throws when nothing matches so a bad selection surfaces
 * loudly rather than silently doing nothing.
 * @param {string} capability
 * @param {string=} forceProvider When set, keep only routes for this provider.
 * @return {!Array<!CapabilityRoute>}
 */
function routesFor(capability, forceProvider) {
  const all = CAPABILITY_ROUTES[capability];
  if (!all || all.length === 0) {
    throw new Error(`No AI route configured for capability: ${capability}`);
  }
  if (!forceProvider) return all;
  const filtered = all.filter((r) => r.provider === forceProvider);
  if (filtered.length === 0) {
    throw new Error(
        `No "${forceProvider}" route configured for capability: ${capability}`);
  }
  return filtered;
}

/**
 * The primary (first) route for a capability — e.g. to read its default model
 * without making a call. With `forceProvider`, the first route for that
 * provider instead, so a forced turn logs the model it actually used.
 * @param {string} capability
 * @param {string=} forceProvider
 * @return {!CapabilityRoute}
 * @throws {Error} If `capability` (or the forced provider) has no route.
 */
function resolve(capability, forceProvider) {
  return routesFor(capability, forceProvider)[0];
}

/**
 * Resolves `capability` to a provider via `registry` and calls `generate`,
 * falling back to the capability's next configured route **only when the
 * current one fails with a provider failure** (outage/5xx/429/timeout — see
 * `../providers/classify.js`). A request the provider rejected as malformed
 * (a 4xx) is rethrown immediately: the next provider would reject the same
 * request the same way. The chosen route's `provider`/`model` are stamped onto
 * the response so the caller can log which model actually answered — important
 * when `Auto` fell back.
 *
 * @param {!Object} registry A `ProviderRegistry`.
 * @param {string} capability
 * @param {!Object} normalizedRequest A `NormalizedRequest`; `model` is
 *   overridden per-route from the capability table.
 * @param {{onText: (function(string): void)}=} opts Streaming sink, passed
 *   through to the provider unchanged.
 * @param {{forceProvider: string}=} routeOpts `forceProvider` pins the request
 *   to one provider and, since that leaves a single route, disables fallback —
 *   this is how the manual "Claude"/"Gemini" selection bypasses Auto's
 *   fallback logic.
 * @return {!Promise<!Object>} A `NormalizedResponse`, with `provider`/`model`
 *   set to the route that produced it.
 */
async function generate(
    registry, capability, normalizedRequest, opts, routeOpts) {
  const forceProvider = routeOpts && routeOpts.forceProvider;
  const routes = routesFor(capability, forceProvider);
  let lastError;
  let attempted = false;
  for (const route of routes) {
    // Skip a route whose provider isn't registered (e.g. Gemini when no key is
    // bound) — a skipped route is a no-op, not a failure, so a single-provider
    // deployment surfaces that provider's own error, not "unknown provider".
    if (!registry.has(route.provider)) continue;
    attempted = true;
    const provider = registry.get(route.provider);
    try {
      const response = await provider.generate(
          Object.assign({}, normalizedRequest, {model: route.model}), opts);
      response.provider = route.provider;
      response.model = route.model;
      return response;
    } catch (err) {
      lastError = err;
      // Only a real provider failure is worth failing over. A malformed-request
      // (4xx) rejection is rethrown as-is so the bug isn't masked by a retry.
      if (!isProviderFailure(err)) throw err;
    }
  }
  if (!attempted) {
    const which = forceProvider ? `"${forceProvider}" ` : "";
    throw new Error(
        `No registered ${which}AI provider for capability: ${capability}`);
  }
  throw lastError;
}

module.exports = {CAPABILITY_ROUTES, resolve, generate};
