/**
 * A small, explicit capability → model map, plus the fallback policy every AI
 * call goes through. Every capability lists one or more routes in priority
 * order; `generate` tries each in turn, moving to the next only when the
 * current one fails **with a provider failure** (see `../providers/
 * classify.js` — outage, overload, rate limit, exhausted credit, rejected key,
 * retired model, timeout). A request the provider rejected as malformed is
 * rethrown, not masked by re-trying it elsewhere.
 *
 * Three things shape the order a call actually tries:
 *   1. **The user's model selection** (`preferModel`, a `./models.js` key):
 *      that model goes first, the capability's defaults follow as fallback —
 *      so picking "Claude Haiku" still lands on Gemini when Anthropic is out
 *      of credit, instead of failing the user.
 *   2. **Cool-down.** A provider that just failed with a sustained outage
 *      (billing/auth) is tried LAST for `COOLDOWN_MS` — every call during a
 *      Claude credit outage shouldn't pay a failed round-trip first. It is
 *      still tried if everything else fails, so recovery is automatic.
 *   3. **`forceProvider`** — a strict pin with no fallback. Kept for tests and
 *      diagnostics; the app's selection uses `preferModel`.
 *
 * When every route fails with a provider failure the router throws
 * `AiUnavailableError`, which the callables turn into a friendly message —
 * the provider's own error text is logged, never shown.
 *
 * Adding a model is one entry in `./models.js`; adding it to a capability is
 * one entry below. Nothing in `../chat/` or `../services/` changes.
 */

const {
  classifyProviderError,
  isSustainedOutage,
  ProviderErrorKind,
  AiUnavailableError,
} = require("../providers/classify");
const {MODELS, modelSpec} = require("./models");

/**
 * @typedef {Object} CapabilityRoute
 * @property {string} provider A name registered in a `ProviderRegistry`.
 * @property {string} model The provider-native model id for this route.
 * @property {string=} key The `./models.js` catalog key.
 */

/**
 * @param {string} key A `./models.js` key.
 * @return {!CapabilityRoute}
 */
function route(key) {
  const spec = MODELS[key];
  return {provider: spec.provider, model: spec.id, key};
}

/** @const {!Object<string, !Array<!CapabilityRoute>>} */
const CAPABILITY_ROUTES = {
  // Claude Sonnet is primary; Gemini Flash answers whenever Claude can't.
  chat: [route("claude-sonnet"), route("gemini-flash")],
  // The importers and the generator were Anthropic-only (they stream partial
  // tool input for progress UI, a path only the Anthropic adapter emits). The
  // client stopped consuming that progress when imports went buffered, so
  // Gemini — which reads PDFs and images natively and supports a forced tool
  // call — is a real fallback here now, not a degraded one.
  workout_import: [route("claude-sonnet"), route("gemini-flash")],
  diet_import: [route("claude-sonnet"), route("gemini-flash")],
  diet_generate: [route("claude-sonnet"), route("gemini-flash")],
  // Google Search grounding (`search_food_product`'s "ground" call, see
  // `../tools/food_search_product.js`) is Gemini-only — Anthropic has no
  // equivalent, so there is deliberately no fallback and no user preference.
  food_search: [route("gemini-flash")],
};

/**
 * Capabilities whose model the user's selection may change. `food_search`
 * isn't one: grounding only exists on Gemini.
 * @const {!Set<string>}
 */
const SELECTABLE_CAPABILITIES =
  new Set(["chat", "workout_import", "diet_import", "diet_generate"]);

/**
 * How long a provider that hit a billing/auth failure is sent to the back of
 * the queue. Per instance (module state), which is the point: it only saves
 * this instance's next calls a doomed round-trip.
 * @const {number}
 */
const COOLDOWN_MS = 10 * 60 * 1000;

/** @type {!Map<string, number>} provider → cool-down end (epoch ms). */
const cooldowns = new Map();

/** Clears the cool-down state — for tests. */
function resetCooldowns() {
  cooldowns.clear();
}

/**
 * @typedef {Object} RouteOptions
 * @property {string=} forceProvider Keep only this provider's routes — a
 *   strict pin that disables fallback.
 * @property {string=} preferModel A `./models.js` key to try first; the
 *   capability's defaults follow as fallback. Ignored for a capability the
 *   user can't steer, or a key the catalog doesn't know.
 * @property {number=} attemptTimeoutMs Abandon one provider attempt after
 *   this long and try the next — so a hung provider can't eat the whole
 *   callable deadline and leave no time for the fallback.
 * @property {function(): number=} now Clock, for tests.
 */

/**
 * The routes for `capability`, in the order a call should try them.
 * @param {string} capability
 * @param {(string|!RouteOptions)=} opts A bare string is `forceProvider`
 *   (the original signature).
 * @return {!Array<!CapabilityRoute>}
 */
function routesFor(capability, opts) {
  const o = typeof opts === "string" ? {forceProvider: opts} : (opts || {});
  const all = CAPABILITY_ROUTES[capability];
  if (!all || all.length === 0) {
    throw new Error(`No AI route configured for capability: ${capability}`);
  }
  if (o.forceProvider) {
    const filtered = all.filter((r) => r.provider === o.forceProvider);
    if (filtered.length === 0) {
      throw new Error(`No "${o.forceProvider}" route configured for ` +
        `capability: ${capability}`);
    }
    return filtered;
  }
  let ordered = all;
  if (o.preferModel && SELECTABLE_CAPABILITIES.has(capability) &&
      modelSpec(o.preferModel)) {
    const preferred = route(o.preferModel);
    ordered = [preferred,
      ...all.filter((r) => r.model !== preferred.model)];
  }
  const nowMs = (o.now || Date.now)();
  const cooling = (r) => (cooldowns.get(r.provider) || 0) > nowMs;
  return [
    ...ordered.filter((r) => !cooling(r)),
    ...ordered.filter(cooling),
  ];
}

/**
 * The first route a call would try — e.g. to read its model without making a
 * call.
 * @param {string} capability
 * @param {(string|!RouteOptions)=} opts
 * @return {!CapabilityRoute}
 * @throws {Error} If `capability` (or the forced provider) has no route.
 */
function resolve(capability, opts) {
  return routesFor(capability, opts)[0];
}

/**
 * Runs one provider attempt under an optional deadline. The attempt gets its
 * own AbortSignal that fires on the deadline OR the caller's signal (a user
 * cancel), and the race makes the deadline hold even for a provider that
 * ignores the signal.
 * @param {!Object} provider
 * @param {!Object} request
 * @param {!Object} opts
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
      const err = new Error(`Provider attempt timed out after ${timeoutMs}ms`);
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
 * Resolves `capability` to a provider via `registry` and calls `generate`,
 * falling back through the capability's routes on provider failures (see the
 * file header). The route that answered is stamped onto the response —
 * `provider`, `model` (provider-native id), `modelKey` — along with the
 * `attempts` that failed before it and `fellBack`, so a usage record can say
 * exactly which model did the work and whether Auto had to fall back.
 *
 * @param {!Object} registry A `ProviderRegistry`.
 * @param {string} capability
 * @param {!Object} normalizedRequest A `NormalizedRequest`; `model` is
 *   overridden per-route.
 * @param {{onText: (function(string): void),
 *   signal: (AbortSignal|undefined)}=} opts Passed through to the provider.
 *   An aborted `signal` (a user cancel) is rethrown, never failed over.
 * @param {!RouteOptions=} routeOpts
 * @return {!Promise<!Object>} A `NormalizedResponse`.
 * @throws {AiUnavailableError} When every route failed with a provider
 *   failure.
 */
async function generate(
    registry, capability, normalizedRequest, opts, routeOpts) {
  const ro = routeOpts || {};
  const routes = routesFor(capability, ro);
  const nowMs = ro.now || Date.now;
  const attempts = [];
  let lastError;
  let lastKind;
  for (const r of routes) {
    // Skip a route whose provider isn't registered (e.g. Gemini when no key is
    // bound) — a skipped route is a no-op, not a failure.
    if (!registry.has(r.provider)) continue;
    const provider = registry.get(r.provider);
    try {
      const response = await attempt(provider,
          Object.assign({}, normalizedRequest, {model: r.model}),
          opts, ro.attemptTimeoutMs);
      response.provider = r.provider;
      response.model = r.model;
      if (r.key) response.modelKey = r.key;
      response.attempts = attempts;
      response.fellBack = attempts.length > 0;
      return response;
    } catch (err) {
      // A user cancel is not a provider failure — stop, don't fall over.
      if (opts && opts.signal && opts.signal.aborted) throw err;
      const kind = classifyProviderError(err);
      // A malformed request is rethrown as-is so the bug isn't masked.
      if (kind === ProviderErrorKind.BAD_REQUEST) throw err;
      if (isSustainedOutage(kind)) {
        cooldowns.set(r.provider, nowMs() + COOLDOWN_MS);
      }
      attempts.push({provider: r.provider, model: r.model, kind});
      lastError = err;
      lastKind = kind;
    }
  }
  if (attempts.length === 0) {
    const which = ro.forceProvider ? `"${ro.forceProvider}" ` : "";
    throw new Error(
        `No registered ${which}AI provider for capability: ${capability}`);
  }
  throw new AiUnavailableError(lastKind, attempts, lastError);
}

module.exports = {
  CAPABILITY_ROUTES,
  SELECTABLE_CAPABILITIES,
  COOLDOWN_MS,
  routesFor,
  resolve,
  generate,
  resetCooldowns,
};
