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
  // Re-verified 2026-09-24 against Anthropic's published pricing: $3 / $15
  // was stale (that rate belonged to Sonnet 4.6) — Sonnet 5's list price is
  // $2 / $10 per 1M tokens, now permanent (was introductory). Cache write
  // 1.25x, cache read 0.1x of the input price (Anthropic prompt caching).
  "claude-sonnet": {
    provider: "anthropic",
    id: "claude-sonnet-5",
    label: "Claude Sonnet 5",
    pricing: {
      inputPerMTok: 2,
      outputPerMTok: 10,
      cacheWriteMultiplier: 1.25,
      cacheReadMultiplier: 0.1,
    },
  },
  // `gemini-flash-latest` is a ROLLING ALIAS — pinned point versions get
  // retired for new projects (Google 404s them with "no longer available to
  // new users", which is what `gemini-2.5-pro` did here), so the alias tracks
  // whatever current Flash is. Checked 2026-09-24: third-party trackers
  // report the alias now resolving to `gemini-3.5-flash` ($1.50 / $9.00 per
  // 1M per Google's pricing page) rather than the Gemini 2.5 Flash rate this
  // was priced at ($0.30 / $2.50) — Google's own docs don't state what the
  // alias currently targets, so that could not be confirmed first-hand.
  // Left AS-IS pending the owner confirming the live rate in Google AI
  // Studio/Cloud console billing, rather than swap in a second unconfirmed
  // number — but treat today's Gemini cost figures as understated until
  // that's checked. Gemini caches implicitly — there is no cache-write
  // bucket, and a cached read bills at ~0.25x.
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
  "claude": "claude-sonnet",
  "gemini": "gemini-flash",
  // Offered briefly, removed 2026-09-23 (the alias never resolved for this
  // key) — its users land on the Gemini model that works.
  "gemini-pro": "gemini-flash",
  // Removed 2026-09-24 — ZIVO offers exactly one model per provider now, so a
  // user who had Haiku active lands on Sonnet, Anthropic's other option.
  "claude-haiku": "claude-sonnet",
};

/**
 * The other provider's model, for the router's automatic fallback
 * (`./router.js`). With exactly one model per provider this is a fixed
 * pairing — a third provider would need a real choice here instead.
 * @const {!Object<string, string>}
 */
const FALLBACK_MODEL = {
  "claude-sonnet": "gemini-flash",
  "gemini-flash": "claude-sonnet",
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
 * Maps the client's untrusted selection (a catalog key, or a legacy
 * `'claude'`/`'gemini'`/`'gemini-pro'`) to a catalog key, or undefined when
 * it names nothing we serve (including the retired `'auto'`) — the caller
 * then uses the capability's default model. Never trust the raw value.
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
  FALLBACK_MODEL,
  modelSpec,
  keyForModelId,
  preferredModelKey,
  pricingFor,
  costUsd,
};
