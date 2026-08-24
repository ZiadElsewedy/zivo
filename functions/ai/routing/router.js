/**
 * A small, explicit capability → provider/model map, plus a fallback-on-
 * error policy. Every capability lists one or more `{provider, model}`
 * routes in priority order; `generate` tries each in turn, only moving to
 * the next after the current one's `generate` call rejects.
 *
 * Anthropic is the only real provider today, so every capability's list has
 * exactly one entry — adding a second provider for a capability is a new
 * `providers/*.js` adapter plus one more entry in the list below, nothing
 * else here or in `../gateway.js`/`../workout_import.js` changes.
 */

/**
 * @typedef {Object} CapabilityRoute
 * @property {string} provider A name registered in a `ProviderRegistry`.
 * @property {string} model The provider-native model id for this route.
 */

/** @const {!Object<string, !Array<!CapabilityRoute>>} */
const CAPABILITY_ROUTES = {
  chat: [{provider: "anthropic", model: "claude-sonnet-5"}],
  workout_import: [{provider: "anthropic", model: "claude-sonnet-5"}],
};

/**
 * The primary (first) route for a capability, e.g. to read its default model
 * without making a call.
 * @param {string} capability
 * @return {!CapabilityRoute}
 * @throws {Error} If `capability` has no configured route.
 */
function resolve(capability) {
  const routes = CAPABILITY_ROUTES[capability];
  if (!routes || routes.length === 0) {
    throw new Error(`No AI route configured for capability: ${capability}`);
  }
  return routes[0];
}

/**
 * Resolves `capability` to a provider via `registry` and calls `generate`,
 * falling back to the capability's next configured route if the current one
 * throws or rejects. Rethrows the last route's error once every route has
 * been tried.
 *
 * @param {!Object} registry A `ProviderRegistry`.
 * @param {string} capability
 * @param {!Object} normalizedRequest A `NormalizedRequest`; `model` is
 *   overridden per-route from the capability table.
 * @param {{onText: (function(string): void)}=} opts
 * @return {!Promise<!Object>} A `NormalizedResponse`.
 */
async function generate(registry, capability, normalizedRequest, opts) {
  const routes = CAPABILITY_ROUTES[capability];
  if (!routes || routes.length === 0) {
    throw new Error(`No AI route configured for capability: ${capability}`);
  }
  let lastError;
  for (const route of routes) {
    const provider = registry.get(route.provider);
    try {
      return await provider.generate(
          Object.assign({}, normalizedRequest, {model: route.model}), opts);
    } catch (err) {
      lastError = err;
    }
  }
  throw lastError;
}

module.exports = {CAPABILITY_ROUTES, resolve, generate};
