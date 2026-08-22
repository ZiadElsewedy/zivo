/**
 * A small, explicit capability → provider/model map for speech-to-text, plus
 * a fallback-on-error policy — the STT counterpart of
 * `../../routing/router.js`, kept separate because it's `.transcribe`-shaped
 * rather than `.generate`-shaped (see `../providers/speech_provider.js`).
 * Both routers share the generic `../../providers/registry.js`
 * `ProviderRegistry`.
 *
 * OpenAI is the only real STT provider today, so the one capability's list
 * has exactly one entry — adding a second provider is a new
 * `speech/providers/*.js` adapter plus one more entry below.
 */

/**
 * @typedef {Object} SpeechCapabilityRoute
 * @property {string} provider A name registered in a `ProviderRegistry`.
 * @property {string} model The provider-native model id for this route.
 */

/** @const {!Object<string, !Array<!SpeechCapabilityRoute>>} */
const SPEECH_ROUTES = {
  speech_to_text: [{provider: "openai", model: "gpt-4o-mini-transcribe"}],
};

/**
 * The primary (first) route for a capability.
 * @param {string} capability
 * @return {!SpeechCapabilityRoute}
 * @throws {Error} If `capability` has no configured route.
 */
function resolve(capability) {
  const routes = SPEECH_ROUTES[capability];
  if (!routes || routes.length === 0) {
    throw new Error(`No STT route configured for capability: ${capability}`);
  }
  return routes[0];
}

/**
 * Resolves `capability` to a provider via `registry` and calls `transcribe`,
 * falling back to the capability's next configured route if the current one
 * throws or rejects. Rethrows the last route's error once every route has
 * been tried.
 *
 * @param {!Object} registry A `ProviderRegistry`.
 * @param {string} capability
 * @param {!Object} normalizedRequest A `NormalizedSttRequest`; `model` is
 *   overridden per-route from the capability table.
 * @return {!Promise<!Object>} A `NormalizedSttResponse`.
 */
async function transcribe(registry, capability, normalizedRequest) {
  const routes = SPEECH_ROUTES[capability];
  if (!routes || routes.length === 0) {
    throw new Error(`No STT route configured for capability: ${capability}`);
  }
  let lastError;
  for (const route of routes) {
    const provider = registry.get(route.provider);
    try {
      return await provider.transcribe(
          Object.assign({}, normalizedRequest, {model: route.model}));
    } catch (err) {
      lastError = err;
    }
  }
  throw lastError;
}

module.exports = {SPEECH_ROUTES, resolve, transcribe};
