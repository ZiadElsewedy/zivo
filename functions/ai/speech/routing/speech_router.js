/**
 * A small, explicit capability → provider/model map for speech-to-text, plus
 * a fallback-on-error policy — the STT counterpart of
 * `../../routing/router.js`, kept separate because it's `.transcribe`-shaped
 * rather than `.generate`-shaped (see `../providers/speech_provider.js`).
 * Both routers share the generic `../../providers/registry.js`
 * `ProviderRegistry`.
 *
 * Gemini is the default STT provider; OpenAI is the fallback tried on error
 * (the order of a capability's list IS the try order — see `transcribe`).
 * Both are real adapters under `speech/providers/`; adding a third provider is
 * a new `speech/providers/*.js` adapter plus one more entry below.
 */

/**
 * @typedef {Object} SpeechCapabilityRoute
 * @property {string} provider A name registered in a `ProviderRegistry`.
 * @property {string} model The provider-native model id for this route.
 */

/** @const {!Object<string, !Array<!SpeechCapabilityRoute>>} */
const SPEECH_ROUTES = {
  speech_to_text: [
    {provider: "gemini", model: "gemini-2.5-flash"},
    {provider: "openai", model: "gpt-4o-mini-transcribe"},
  ],
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
  let attempted = false;
  for (const route of routes) {
    // Skip a route whose provider isn't registered — e.g. the optional OpenAI
    // fallback when no OpenAI key is configured. A skipped route is a no-op,
    // not a failure, so a Gemini-only deployment surfaces Gemini's own error
    // rather than an "unknown provider" one.
    if (!registry.has(route.provider)) continue;
    attempted = true;
    const provider = registry.get(route.provider);
    try {
      return await provider.transcribe(
          Object.assign({}, normalizedRequest, {model: route.model}));
    } catch (err) {
      lastError = err;
    }
  }
  if (!attempted) {
    throw new Error(
        `No registered STT provider for capability: ${capability}`);
  }
  throw lastError;
}

module.exports = {SPEECH_ROUTES, resolve, transcribe};
