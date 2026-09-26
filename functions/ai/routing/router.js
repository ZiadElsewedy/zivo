/**
 * Which model answers an AI call. The model the user marked active in the app
 * (`users/{uid}/settings/ai.provider`, a `./models.js` key) is the one that
 * answers — ONE active model, deterministically: Gemini selected → Gemini
 * only; Claude selected → Claude only.
 *
 * NO CROSS-PROVIDER FALLBACK (owner decision 2026-09-26, replacing the
 * automatic fallback of 2026-09-24). When the selected provider fails, its
 * OWN failure is what the caller gets — `AiUnavailableError` naming that
 * provider, model and why (`kind`) — and the app shows it with a "Switch
 * model" action. The other provider is never called behind the user's back:
 * a Gemini that's out of quota, or a Claude that's out of credit, must be
 * visible, not papered over. Switching is the user's choice, through the
 * existing model selection.
 *
 * When the selected provider fails:
 *   - TRANSIENT (down, overloaded, rate-limited, timed out — see
 *     `../providers/classify.js`'s `isTransientFailure`): retried on the SAME
 *     provider after a short backoff (twice for a fast failure, once for a
 *     timeout — `attemptsFor`), then it fails. This file is the ONLY retry
 *     layer: the SDK clients' own retries are off.
 *   - PROVIDER-SIDE BUT NOT TRANSIENT (quota used up, out of credit, key
 *     rejected, model retired): not retried — it won't answer 350ms later —
 *     it fails at once.
 *   - A MALFORMED REQUEST (`bad_request`) is rethrown as-is: that's our bug.
 *
 * The cross-provider path itself (`FALLBACK_MODEL`, `onFallback`,
 * `stickyProvider`, the `fallbackOccurred` stamps) is kept, switched off by
 * `CROSS_PROVIDER_FALLBACK` — so re-enabling it is one deliberate change,
 * not a rebuild, and old usage records that carry those stamps still read.
 *
 * ZIVO's own daily Ask allowance is NOT a provider failure and never reaches
 * this file: `../chat/turn.js` checks it before any model call.
 *
 * `food_search` is Gemini-only whatever the selection: Google Search
 * grounding exists only on Gemini (`../tools/food_search_product.js`).
 */

const {
  classifyProviderError,
  isTransientFailure,
  canFallBackFor,
  ProviderErrorKind,
  AiUnavailableError,
} = require("../providers/classify");
const {MODELS, modelSpec, FALLBACK_MODEL} = require("./models");

/**
 * Whether a failed call may be re-run on the OTHER provider. Off: the
 * selected model answers or its failure is returned (see the file header).
 * @const {boolean}
 */
const CROSS_PROVIDER_FALLBACK = false;

/**
 * The pause before each same-provider retry, in order.
 *
 * THIS FILE IS THE ONLY RETRY OWNER. The SDK clients are built with their own
 * retries OFF (`maxRetries: 0` — `functions/index.js`); before that, the
 * Anthropic SDK's default 2 retries ran INSIDE each attempt here, so one
 * overloaded call could become 6 provider requests (3 per attempt × 2
 * attempts) before the fallback — invisible to the usage log. Now every
 * request to a provider is an attempt this file makes, times and records
 * (`tries`).
 * @const {!Array<number>}
 */
const RETRY_BACKOFF_MS = [350, 1000];

/**
 * Same-provider attempts for a transient failure, by kind. A fast failure
 * (overloaded, rate-limited, a 5xx, a dropped connection) gets two retries —
 * what the SDK's own retries used to provide, now in one place. A TIMEOUT gets
 * one: each costs a full per-attempt deadline, and three of them would outlast
 * the callable itself.
 * @param {string} kind
 * @return {number}
 */
function attemptsFor(kind) {
  return kind === ProviderErrorKind.TIMEOUT ? 2 : 3;
}

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
 * `opts` with its streaming sinks (`onText`, `onInputJson`) routed through a
 * gate that `close()` shuts — so one attempt's stream can't outlive it.
 * @param {(!Object|undefined)} opts
 * @return {{opts: (!Object|undefined), close: function(): void}}
 */
function gatedStreamOpts(opts) {
  let open = true;
  const close = () => {
    open = false;
  };
  if (!opts) return {opts, close};
  const gated = Object.assign({}, opts);
  for (const sink of ["onText", "onInputJson"]) {
    if (typeof opts[sink] !== "function") continue;
    gated[sink] = (...args) => {
      if (open) opts[sink](...args);
    };
  }
  return {opts: gated, close};
}

/**
 * One route's outcome: either a stamped response, or a classified failure
 * kind with nothing thrown yet — `generate` decides what a failure MEANS
 * (retry, fall back, or give up) rather than unwinding the stack for it.
 * Both carry `tries` — every request actually sent, `{provider, model, ok,
 * kind?, latencyMs}`.
 * @typedef {{ok: true, response: !Object, tries: !Array<!Object>} |
 *   {ok: false, kind: string, permanent: boolean, cause: *,
 *     tries: !Array<!Object>}}
 *   RouteAttemptResult
 */

/**
 * Runs `route` through `registry`, retrying a transient failure after a
 * short backoff when `allowRetry` (`attemptsFor`: twice for a fast
 * failure, once for a timeout). Never throws for a provider failure —
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
      // Nothing was sent to the provider.
      tries: [],
    };
  }
  const provider = registry.get(target.provider);
  // Every request sent to the provider, in order — what the usage record
  // shows as `tries` (`../shared/usage_log.js`, `../chat/turn.js`).
  const tries = [];
  const backoff = (opts && opts.retryBackoffMs) || RETRY_BACKOFF_MS;
  for (let i = 0; ; i++) {
    if (i > 0) await delay(backoff[Math.min(i - 1, backoff.length - 1)]);
    const startedAt = Date.now();
    // Each attempt streams through its OWN gate, closed the moment the
    // attempt settles. An attempt abandoned at its deadline may still be
    // streaming (a provider that ignores the abort signal), and its late
    // words must never land in the retry's reply.
    const gate = gatedStreamOpts(opts);
    try {
      const response = await attempt(provider,
          Object.assign({}, normalizedRequest, {model: target.model}),
          gate.opts, attemptTimeoutMs);
      gate.close();
      tries.push({provider: target.provider, model: target.model, ok: true,
        latencyMs: Date.now() - startedAt});
      response.provider = target.provider;
      response.model = target.model;
      response.modelKey = target.key;
      return {ok: true, response, tries};
    } catch (err) {
      gate.close();
      const kind = classifyProviderError(err);
      tries.push({provider: target.provider, model: target.model, ok: false,
        kind, latencyMs: Date.now() - startedAt});
      if (opts && opts.signal && opts.signal.aborted) throw err;
      if (kind === ProviderErrorKind.BAD_REQUEST) {
        // Our own malformed request: never retried or fallen back for, but
        // it IS a failed request — tagged so the usage log records it
        // instead of losing it (`UsageMeter`).
        if (err && typeof err === "object") err.tries = tries;
        throw err;
      }
      if (!isTransientFailure(kind)) {
        return {ok: false, kind, permanent: true, cause: err, tries};
      }
      if (!allowRetry || i >= attemptsFor(kind) - 1) {
        return {ok: false, kind, permanent: false, cause: err, tries};
      }
      // Transient and another attempt remains — loop retries after the delay.
      // The caller hears it first: whatever this attempt already streamed is
      // about to be superseded by a fresh answer, and a streaming chat must
      // not show the two back to back (`../chat/live_text.js`).
      if (opts && typeof opts.onRetry === "function") {
        opts.onRetry({attempt: i + 2, reason: kind});
      }
    }
  }
}

/**
 * Calls the capability's model through `registry` — retrying a transient
 * failure on the same provider, and throwing that provider's failure
 * (`AiUnavailableError`) when it can't answer; the other provider is tried
 * only if `CROSS_PROVIDER_FALLBACK` is on, which it isn't (see the header).
 * The route that answered is stamped onto the response — `provider`,
 * `model` (provider-native id), `modelKey` — and every provider request it
 * took (`tries`), so the usage record says exactly which model did the
 * work. (With fallback on, a response that needed it would also carry
 * `requestedProvider`, `requestedModel`, `fallbackOccurred: true`,
 * `fallbackReason` (the primary's failure kind) and `failedAttempts`
 * (`[{provider, model, kind}]`).) A failure carries
 * `tries` too.
 *
 * @param {!Object} registry A `ProviderRegistry`.
 * @param {string} capability
 * @param {!Object} normalizedRequest A `NormalizedRequest`; `model` is
 *   overridden by the route.
 * @param {{onText: (function(string): void),
 *   signal: (AbortSignal|undefined),
 *   onRetry: (function({attempt: number, reason: string}): void|undefined),
 *   onFallback: (function({from: string, to: string, reason: string}): void|
 *     undefined)}=} opts Passed through to the provider. An aborted `signal`
 *   (a user cancel) is rethrown unchanged; `onRetry` is called just before a
 *   same-provider retry (the failed attempt's streamed text is superseded);
 *   `onFallback` just before the other provider is tried.
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
  if (primaryResult.ok) {
    primaryResult.response.tries = primaryResult.tries;
    return primaryResult.response;
  }

  const attempts = [
    {provider: primary.provider, model: primary.model,
      kind: primaryResult.kind},
  ];
  const canFallBack = CROSS_PROVIDER_FALLBACK &&
    canFallBackFor(primaryResult.kind) &&
    SELECTABLE_CAPABILITIES.has(capability) && FALLBACK_MODEL[primary.key];
  if (!canFallBack) {
    const err = new AiUnavailableError(
        primaryResult.kind, attempts, primaryResult.cause);
    err.tries = primaryResult.tries;
    throw err;
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
    // What was tried and why it failed — the usage record keeps it, so a
    // provider that keeps failing is visible even while the other answers.
    response.failedAttempts = attempts;
    response.tries = primaryResult.tries.concat(fallbackResult.tries);
    return response;
  }
  attempts.push(
      {provider: fallback.provider, model: fallback.model,
        kind: fallbackResult.kind});
  const err = new AiUnavailableError(
      fallbackResult.kind, attempts, fallbackResult.cause);
  err.tries = primaryResult.tries.concat(fallbackResult.tries);
  throw err;
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
  CROSS_PROVIDER_FALLBACK,
  stickyProvider,
  CAPABILITY_DEFAULTS,
  SELECTABLE_CAPABILITIES,
  resolve,
  generate,
};
