/**
 * Which model answers an AI call — and nothing more. **One active model per
 * request, no fallback** (owner decision, 2026-09-23): the model the user
 * marked active in the app (`users/{uid}/settings/ai.provider`, a
 * `./models.js` key) answers every chat turn, plan import and plan build; when
 * no valid selection exists, the capability's default below does. If that
 * model's provider can't answer (out of credit, down, rate-limited, timed
 * out), the call fails with `AiUnavailableError` naming the provider and the
 * reason — it is NOT silently re-run on another provider. Silent switching
 * made cost and usage impossible to attribute, and a request billed to two
 * providers for one answer.
 *
 * The one exception is `food_search`: Google Search grounding exists only on
 * Gemini, so that single tool call (see `../tools/food_search_product.js`)
 * always runs on Gemini Flash and is logged as its own `food_search` request.
 *
 * A request the provider rejected as malformed (a 4xx that isn't billing/auth/
 * model — see `../providers/classify.js`) is rethrown as-is: that's our bug,
 * not the provider being unavailable.
 */

const {
  classifyProviderError,
  ProviderErrorKind,
  AiUnavailableError,
} = require("../providers/classify");
const {MODELS, modelSpec} = require("./models");

/**
 * @typedef {Object} CapabilityRoute
 * @property {string} provider A name registered in a `ProviderRegistry`.
 * @property {string} model The provider-native model id.
 * @property {string} key The `./models.js` catalog key.
 */

/**
 * @param {string} key A `./models.js` key.
 * @return {!CapabilityRoute}
 */
function route(key) {
  const spec = MODELS[key];
  return {provider: spec.provider, model: spec.id, key};
}

/**
 * The model each capability uses when the user hasn't picked one.
 * @const {!Object<string, string>}
 */
const CAPABILITY_DEFAULTS = {
  chat: "claude-sonnet",
  workout_import: "claude-sonnet",
  diet_import: "claude-sonnet",
  diet_generate: "claude-sonnet",
  // Grounding is Gemini-only — never follows the user's selection.
  food_search: "gemini-flash",
};

/**
 * Capabilities that follow the user's active model.
 * @const {!Set<string>}
 */
const SELECTABLE_CAPABILITIES =
  new Set(["chat", "workout_import", "diet_import", "diet_generate"]);

/**
 * @typedef {Object} RouteOptions
 * @property {string=} preferModel The user's active model (a `./models.js`
 *   key). Ignored for a capability the user can't steer, or an unknown key.
 * @property {number=} attemptTimeoutMs Abandon the call after this long with
 *   a clean `timeout` failure — so a hung provider surfaces as "didn't
 *   respond" inside the callable's own deadline instead of the client's
 *   opaque DEADLINE_EXCEEDED.
 */

/**
 * The single route a call uses.
 * @param {string} capability
 * @param {!RouteOptions=} opts
 * @return {!CapabilityRoute}
 * @throws {Error} For an unknown capability.
 */
function resolve(capability, opts) {
  const fallbackKey = CAPABILITY_DEFAULTS[capability];
  if (!fallbackKey) {
    throw new Error(`No AI route configured for capability: ${capability}`);
  }
  const preferred = opts && opts.preferModel;
  if (preferred && SELECTABLE_CAPABILITIES.has(capability) &&
      modelSpec(preferred)) {
    return route(preferred);
  }
  return route(fallbackKey);
}

/**
 * Runs the provider call under an optional deadline. The call gets its own
 * AbortSignal that fires on the deadline OR the caller's signal (a user
 * cancel), and the race makes the deadline hold even for a provider that
 * ignores the signal.
 * @param {!Object} provider
 * @param {!Object} request
 * @param {(!Object|undefined)} opts
 * @param {(number|undefined)} timeoutMs
 * @return {!Promise<!Object>}
 */
async function attempt(provider, request, opts, timeoutMs) {
  if (!timeoutMs) return provider.generate(request, opts);
  const controller = new AbortController();
  const outer = opts && opts.signal;
  const onOuterAbort = () => controller.abort();
  if (outer) {
    if (outer.aborted) controller.abort();
    else outer.addEventListener("abort", onOuterAbort, {once: true});
  }
  let timer;
  const deadline = new Promise((_, reject) => {
    timer = setTimeout(() => {
      const err = new Error(`Provider call timed out after ${timeoutMs}ms`);
      err.name = "TimeoutError";
      controller.abort();
      reject(err);
    }, timeoutMs);
  });
  try {
    return await Promise.race([
      provider.generate(request,
          Object.assign({}, opts, {signal: controller.signal})),
      deadline,
    ]);
  } finally {
    clearTimeout(timer);
    if (outer) outer.removeEventListener("abort", onOuterAbort);
  }
}

/**
 * Calls the capability's one model through `registry`. The route is stamped
 * onto the response — `provider`, `model` (provider-native id), `modelKey` —
 * so the usage record says exactly which model did the work.
 *
 * @param {!Object} registry A `ProviderRegistry`.
 * @param {string} capability
 * @param {!Object} normalizedRequest A `NormalizedRequest`; `model` is
 *   overridden by the route.
 * @param {{onText: (function(string): void),
 *   signal: (AbortSignal|undefined)}=} opts Passed through to the provider.
 *   An aborted `signal` (a user cancel) is rethrown unchanged.
 * @param {!RouteOptions=} routeOpts
 * @return {!Promise<!Object>} A `NormalizedResponse`.
 * @throws {AiUnavailableError} When the provider couldn't answer.
 */
async function generate(
    registry, capability, normalizedRequest, opts, routeOpts) {
  const ro = routeOpts || {};
  const r = resolve(capability, ro);
  if (!registry.has(r.provider)) {
    // The provider's key isn't bound in this deployment — as unavailable as
    // an outage, from the user's side.
    throw new AiUnavailableError(ProviderErrorKind.AUTH,
        [{provider: r.provider, model: r.model, kind: ProviderErrorKind.AUTH}],
        new Error(`No registered AI provider: ${r.provider}`));
  }
  const provider = registry.get(r.provider);
  try {
    const response = await attempt(provider,
        Object.assign({}, normalizedRequest, {model: r.model}),
        opts, ro.attemptTimeoutMs);
    response.provider = r.provider;
    response.model = r.model;
    response.modelKey = r.key;
    return response;
  } catch (err) {
    if (opts && opts.signal && opts.signal.aborted) throw err;
    const kind = classifyProviderError(err);
    if (kind === ProviderErrorKind.BAD_REQUEST) throw err;
    throw new AiUnavailableError(kind,
        [{provider: r.provider, model: r.model, kind}], err);
  }
}

module.exports = {
  CAPABILITY_DEFAULTS,
  SELECTABLE_CAPABILITIES,
  resolve,
  generate,
};
