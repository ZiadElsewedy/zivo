/**
 * The model catalog — every model ZIVO can route an AI call to, in ONE place:
 * which provider serves it, its provider-native id, and what it costs.
 *
 * Everything that names a model reads it from here: the router's capability
 * table (`./router.js`), the user's model selection (a catalog KEY such as
 * `"claude-sonnet"`, persisted at `users/{uid}/settings/ai.provider`), and the
 * cost figure every usage record carries (`pricingFor`). Adding a model is one
 * entry below — the client lists what it offers in
 * `lib/features/ai/domain/ai_model_selection.dart`, keyed by the same KEYS.
 *
 * Keys are ZIVO's own, stable ids; `id` is what the provider's API wants and
 * may change (a new snapshot, a retired alias) without touching a stored
 * selection or a usage record's `modelKey`.
 */

/**
 * @typedef {Object} ModelPricing Per-million-token list prices in USD.
 * @property {number} inputPerMTok
 * @property {number} outputPerMTok
 * @property {number} cacheWriteMultiplier Applied to the input price.
 * @property {number} cacheReadMultiplier Applied to the input price.
 */

/**
 * @typedef {Object} ModelSpec
 * @property {string} provider A `ProviderRegistry` name.
 * @property {string} id The provider-native model id.
 * @property {string} label Human name, for logs.
 * @property {!ModelPricing} pricing
 */

/** @const {!Object<string, !ModelSpec>} */
const MODELS = {
  // Owner-confirmed 2026-08-15: $3 / $15 per 1M tokens. Cache write 1.25x,
  // cache read 0.1x of the input price (Anthropic prompt caching).
  "claude-sonnet": {
    provider: "anthropic",
    id: "claude-sonnet-5",
    label: "Claude Sonnet 5",
    pricing: {
      inputPerMTok: 3,
      outputPerMTok: 15,
      cacheWriteMultiplier: 1.25,
      cacheReadMultiplier: 0.1,
    },
  },
  // Anthropic list price: $1 / $5 per 1M tokens. Faster and cheaper than
  // Sonnet, a good fit for the structured-extraction calls.
  "claude-haiku": {
    provider: "anthropic",
    id: "claude-haiku-4-5-20251001",
    label: "Claude Haiku 4.5",
    pricing: {
      inputPerMTok: 1,
      outputPerMTok: 5,
      cacheWriteMultiplier: 1.25,
      cacheReadMultiplier: 0.1,
    },
  },
  // `gemini-flash-latest` is a ROLLING ALIAS — pinned point versions get
  // retired for new projects (Google 404s them with "no longer available to
  // new users", which is what `gemini-2.5-pro` did here), so the alias tracks
  // whatever current Flash is. Priced at Google's published Gemini 2.5 Flash
  // standard-tier list rates ($0.30 / $2.50 per 1M); the rate can move under
  // the alias, so treat Gemini costs as estimates. Gemini caches implicitly —
  // there is no cache-write bucket, and a cached read bills at ~0.25x.
  "gemini-flash": {
    provider: "gemini",
    id: "gemini-flash-latest",
    label: "Gemini Flash",
    pricing: {
      inputPerMTok: 0.30,
      outputPerMTok: 2.50,
      cacheWriteMultiplier: 1.0,
      cacheReadMultiplier: 0.25,
    },
  },
  // The Pro-tier rolling alias. Priced at Gemini 2.5 Pro's standard-tier list
  // rates ($1.25 / $10 per 1M, ≤200k context) — an estimate for the same
  // reason as Flash. If Google ever retires the alias for this key, the
  // router classifies the 404 as `model_unavailable` and falls through to the
  // next route instead of failing the user's request.
  "gemini-pro": {
    provider: "gemini",
    id: "gemini-pro-latest",
    label: "Gemini Pro",
    pricing: {
      inputPerMTok: 1.25,
      outputPerMTok: 10,
      cacheWriteMultiplier: 1.0,
      cacheReadMultiplier: 0.25,
    },
  },
};

/**
 * The model a provider is priced at when a record names the provider but not
 * a model this catalog knows (a legacy record, a test fake).
 * @const {!Object<string, string>}
 */
const DEFAULT_MODEL_FOR_PROVIDER = {
  anthropic: "claude-sonnet",
  gemini: "gemini-flash",
};

/**
 * The client's stored selection values from before per-model selection
 * existed, mapped onto catalog keys — a user who picked "Claude" keeps Claude.
 * @const {!Object<string, string>}
 */
const LEGACY_SELECTIONS = {
  claude: "claude-sonnet",
  gemini: "gemini-flash",
};

/**
 * @param {string} key
 * @return {(!ModelSpec|undefined)}
 */
function modelSpec(key) {
  return Object.prototype.hasOwnProperty.call(MODELS, key) ?
    MODELS[key] : undefined;
}

/**
 * The catalog key for a provider-native model id, or undefined.
 * @param {?string} id
 * @return {(string|undefined)}
 */
function keyForModelId(id) {
  if (!id) return undefined;
  return Object.keys(MODELS).find((k) => MODELS[k].id === id);
}

/**
 * Maps the client's untrusted selection (`'auto'`, a catalog key, or a legacy
 * `'claude'`/`'gemini'`) to a catalog key, or undefined for Auto. Anything
 * unrecognized is Auto — never trust the raw value.
 * @param {*} selection
 * @return {(string|undefined)}
 */
function preferredModelKey(selection) {
  if (typeof selection !== "string") return undefined;
  const key = LEGACY_SELECTIONS[selection] || selection;
  return modelSpec(key) ? key : undefined;
}

/**
 * The per-token pricing for a call, resolved by the model id that answered,
 * then by provider, then Anthropic Sonnet — so the cost math always has real
 * numbers and can never `NaN` out on a missing stamp.
 * @param {?string} provider
 * @param {?string=} modelId Provider-native id, e.g. `"claude-sonnet-5"`.
 * @return {{inputPerToken: number, outputPerToken: number,
 *   cacheWriteMultiplier: number, cacheReadMultiplier: number}}
 */
function pricingFor(provider, modelId) {
  const key = keyForModelId(modelId) ||
    DEFAULT_MODEL_FOR_PROVIDER[provider] ||
    DEFAULT_MODEL_FOR_PROVIDER.anthropic;
  const p = MODELS[key].pricing;
  return {
    inputPerToken: p.inputPerMTok / 1000000,
    outputPerToken: p.outputPerMTok / 1000000,
    cacheWriteMultiplier: p.cacheWriteMultiplier,
    cacheReadMultiplier: p.cacheReadMultiplier,
  };
}

/**
 * Dollar cost of a `NormalizedUsage`-shaped token count at a model's rates.
 * @param {?{inputTokens: number, outputTokens: number,
 *   cacheReadTokens: number, cacheWriteTokens: number}} usage
 * @param {?string} provider
 * @param {?string=} modelId
 * @return {number}
 */
function costUsd(usage, provider, modelId) {
  const u = usage || {};
  const p = pricingFor(provider, modelId);
  return (
    (u.inputTokens || 0) * p.inputPerToken +
    (u.cacheWriteTokens || 0) * p.inputPerToken * p.cacheWriteMultiplier +
    (u.cacheReadTokens || 0) * p.inputPerToken * p.cacheReadMultiplier +
    (u.outputTokens || 0) * p.outputPerToken
  );
}

module.exports = {
  MODELS,
  DEFAULT_MODEL_FOR_PROVIDER,
  modelSpec,
  keyForModelId,
  preferredModelKey,
  pricingFor,
  costUsd,
};
