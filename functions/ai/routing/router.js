/**
 * Which model answers an AI call, with automatic fallback (owner decision,
 * 2026-09-24, replacing the one-model-no-fallback rule from 2026-09-23): the
 * model the user marked active in the app (`users/{uid}/settings/ai.provider`,
 * a `./models.js` key) is still the one that answers — but when its provider
 * hits a TRANSIENT failure (down, overloaded, rate-limited, timed out — see
 * `../providers/classify.js`'s `isTransientFailure`), the request is retried
 * once on the same provider after a short backoff, and if that still fails,
 * automatically re-run on the OTHER provider (`./models.js`'s
 * `FALLBACK_MODEL`) rather than surfacing an error the user has no way to act
 * on. The response is stamped with what actually answered AND what was
 * originally asked for (`requestedProvider`/`requestedModel`/
 * `fallbackOccurred`/`fallbackReason`), so usage stays truthful about it
 * (`../shared/usage_log.js`) instead of the switch being silent.
 *
 * A PERMANENT failure — bad API key, billing/auth, an unsupported model, or a
 * malformed request (`bad_request`) — is never retried or fallen back for:
 * another attempt or another provider can't fix a configuration problem, and
 * trying anyway would burn a second request while hiding the real problem
 * behind an apparently-working app. Those fail immediately with
 * `AiUnavailableError` (or, for `bad_request`, are rethrown as-is — that's our
 * bug, not the provider being unavailable).
 *
 * The one capability excluded from fallback is `food_search`: Google Search
 * grounding exists only on Gemini, so that single tool call (see
 * `../tools/food_search_product.js`) always runs on Gemini Flash — Claude
 * can't do the same job, so falling back to it would "succeed" at the wrong
 * task. See `SELECTABLE_CAPABILITIES`, which fallback also gates on.
 */

const {
  classifyProviderError,
  isTransientFailure,
  ProviderErrorKind,
  AiUnavailableError,
} = require("../providers/classify");
const {MODELS, modelSpec, FALLBACK_MODEL} = require("./models");

/** A short pause before the one same-provider retry. @const {number} */
const RETRY_BACKOFF_MS = 350;

/**
 * @param {number} ms
 * @return {!Promise<void>}
 */
function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

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
 * One route's outcome: either a stamped response, or a classified failure
 * kind with nothing thrown yet — `generate` decides what a failure MEANS
 * (retry, fall back, or give up) rather than unwinding the stack for it.
 * @typedef {{ok: true, response: !Object} |
 *   {ok: false, kind: string, permanent: boolean, cause: *}}
 *   RouteAttemptResult
 */

/**
 * Runs `route` through `registry`, retrying once after a short backoff on a
 * transient failure when `allowRetry`. Never throws for a provider failure —
 * callers read `.ok`/`.kind`/`.permanent`. A user cancel (`opts.signal`
 * aborted) and a malformed request (`bad_request`) are the two exceptions:
 * both are rethrown immediately, since neither retrying nor falling back
 * changes either outcome.
 * @param {!Object} registry
 * @param {!CapabilityRoute} target
 * @param {!Object} normalizedRequest
 * @param {(!Object|undefined)} opts
 * @param {(number|undefined)} attemptTimeoutMs
 * @param {boolean} allowRetry
 * @return {!Promise<!RouteAttemptResult>}
 */
async function runRoute(
    registry, target, normalizedRequest, opts, attemptTimeoutMs, allowRetry) {
  if (!registry.has(target.provider)) {
    // The provider's key isn't bound in this deployment — a configuration
    // gap, not a transient blip, so this doesn't retry. (A DIFFERENT
    // provider can still be tried by the caller, same as any other failure.)
    return {
      ok: false,
      kind: ProviderErrorKind.AUTH,
      permanent: true,
      cause: new Error(`No registered AI provider: ${target.provider}`),
    };
  }
  const provider = registry.get(target.provider);
  const attempts = allowRetry ? 2 : 1;
  for (let i = 0; i < attempts; i++) {
    if (i > 0) await delay(RETRY_BACKOFF_MS);
    try {
      const response = await attempt(provider,
          Object.assign({}, normalizedRequest, {model: target.model}),
          opts, attemptTimeoutMs);
      response.provider = target.provider;
      response.model = target.model;
      response.modelKey = target.key;
      return {ok: true, response};
    } catch (err) {
      if (opts && opts.signal && opts.signal.aborted) throw err;
      const kind = classifyProviderError(err);
      if (kind === ProviderErrorKind.BAD_REQUEST) throw err;
      if (!isTransientFailure(kind)) {
        return {ok: false, kind, permanent: true, cause: err};
      }
      if (i === attempts - 1) {
        return {ok: false, kind, permanent: false, cause: err};
      }
      // Transient and another attempt remains — loop retries after the delay.
    }
  }
  // Unreachable (the loop always returns), but keeps the function's return
  // type honest for anything analyzing it statically.
  throw new Error("unreachable");
}

/**
 * Calls the capability's model through `registry` — retrying and falling back
 * for a transient failure (see the file header), giving up immediately for a
 * permanent one. The route that actually answered is stamped onto the
 * response — `provider`, `model` (provider-native id), `modelKey` — so the
 * usage record says exactly which model did the work; a response that
 * required a fallback also carries `requestedProvider`, `requestedModel`,
 * `fallbackOccurred: true` and `fallbackReason` (the primary's failure kind).
 *
 * @param {!Object} registry A `ProviderRegistry`.
 * @param {string} capability
 * @param {!Object} normalizedRequest A `NormalizedRequest`; `model` is
 *   overridden by the route.
 * @param {{onText: (function(string): void),
 *   signal: (AbortSignal|undefined),
 *   onFallback: (function({from: string, to: string, reason: string}): void|
 *     undefined)}=} opts Passed through to the provider. An aborted `signal`
 *   (a user cancel) is rethrown unchanged; `onFallback` is called just before
 *   the other provider is tried.
 * @param {!RouteOptions=} routeOpts
 * @return {!Promise<!Object>} A `NormalizedResponse`.
 * @throws {AiUnavailableError} When no provider could answer.
 */
async function generate(
    registry, capability, normalizedRequest, opts, routeOpts) {
  const ro = routeOpts || {};
  const primary = resolve(capability, ro);
  const primaryResult = await runRoute(
      registry, primary, normalizedRequest, opts, ro.attemptTimeoutMs, true);
  if (primaryResult.ok) return primaryResult.response;

  const attempts = [
    {provider: primary.provider, model: primary.model,
      kind: primaryResult.kind},
  ];
  const canFallBack = !primaryResult.permanent &&
    SELECTABLE_CAPABILITIES.has(capability) && FALLBACK_MODEL[primary.key];
  if (!canFallBack) {
    throw new AiUnavailableError(
        primaryResult.kind, attempts, primaryResult.cause);
  }

  const fallback = route(FALLBACK_MODEL[primary.key]);
  // Tell the caller BEFORE the fallback runs, so a streaming chat can drop
  // whatever the failed attempt already streamed and show the switch as it
  // happens rather than after the answer. Model keys only.
  if (opts && typeof opts.onFallback === "function") {
    opts.onFallback({from: primary.key, to: fallback.key,
      reason: primaryResult.kind});
  }
  const fallbackResult = await runRoute(
      registry, fallback, normalizedRequest, opts, ro.attemptTimeoutMs, false);
  if (fallbackResult.ok) {
    const response = fallbackResult.response;
    response.requestedProvider = primary.provider;
    response.requestedModel = primary.model;
    response.fallbackOccurred = true;
    response.fallbackReason = primaryResult.kind;
    return response;
  }
  attempts.push(
      {provider: fallback.provider, model: fallback.model,
        kind: fallbackResult.kind});
  throw new AiUnavailableError(
      fallbackResult.kind, attempts, fallbackResult.cause);
}

/**
 * A provider seam for ONE request (one chat turn, one import) that remembers a
 * fallback: once the active model failed and the other one answered, the rest
 * of this request's calls go straight to the model that works instead of
 * re-trying the failing one (and its backoff) on every agent step. Each call
 * still retries/falls back on its own terms, so this adds no unbounded path.
 * Usage stays truthful: the turn records the FIRST call's fallback
 * (`requestedModel`/`fallbackReason`), and each call is metered at the model
 * that actually answered.
 *
 * @param {!Object} registry A `ProviderRegistry`.
 * @param {string} capability
 * @param {!RouteOptions=} routeOpts
 * @return {{generate: function(!Object, !Object=): !Promise<!Object>}}
 */
function stickyProvider(registry, capability, routeOpts) {
  let pinned = null;
  return {
    generate: async (normalizedRequest, opts) => {
      const ro = pinned ?
        Object.assign({}, routeOpts || {}, {preferModel: pinned}) : routeOpts;
      const response = await generate(
          registry, capability, normalizedRequest, opts, ro);
      if (response.fallbackOccurred && response.modelKey) {
        pinned = response.modelKey;
      }
      return response;
    },
  };
}

module.exports = {
  stickyProvider,
  CAPABILITY_DEFAULTS,
  SELECTABLE_CAPABILITIES,
  resolve,
  generate,
};
