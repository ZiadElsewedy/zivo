/**
 * One usage record per AI request, for EVERY AI feature — not just chat.
 *
 * Chat turns have logged to `users/{uid}/aiUsage` since ADR-001
 * (`../chat/turn.js`). The other paid calls — plan import, plan generation,
 * food search, transcription — logged nothing, so "what did Claude cost me
 * this week, and on what?" had no answer. They now write the same collection
 * with a `feature` field, through the helpers here:
 *
 *   - `UsageMeter` wraps a provider (`meter.wrap(provider)`) and records every
 *     model call that passes through it — the model that answered, its token
 *     buckets, its cost at THAT model's rate, and the provider it failed on.
 *   - `buildUsageRecord` turns a meter's calls into the record, including a
 *     failed request (status + a classified error kind, never the provider's
 *     raw text), so failures are visible in the log too.
 *
 * The chat turn keeps its own richer record (tools, iterations, validation)
 * and adds `feature: "chat"` and `status`. The daily chat cap
 * counts chat records only (`FirestoreStore.getTodayUsageTotals`).
 */

const {costUsd} = require("../routing/models");
const {
  classifyProviderError,
  AiUnavailableError,
} = require("../providers/classify");

/**
 * The `feature` values a usage record can carry. The client maps each to a
 * label (`lib/features/ai/presentation/ai_labels.dart`), and an unknown value
 * renders as a generic "AI request", so adding one here is safe.
 * @enum {string}
 */
const AiFeature = {
  CHAT: "chat",
  WORKOUT_IMPORT: "workout_import",
  DIET_IMPORT: "diet_import",
  DIET_GENERATE: "diet_generate",
  FOOD_SEARCH: "food_search",
  TRANSCRIBE: "transcribe",
};

/**
 * v5 added `requestedProvider`/`requestedModel`/`fallbackOccurred`/
 * `fallbackReason`, present only when the router actually fell back to the
 * other provider (`../routing/router.js`). v6 adds `fallbackCount` (calls
 * that needed the other provider) and `failedAttempts`
 * (`[{provider, model, kind}]`) — additive, so a v5 reader is unaffected.
 */
const USAGE_SCHEMA_VERSION = 6;

/**
 * Records every model call made through a wrapped provider.
 */
class UsageMeter {
  /** Starts with no calls recorded. */
  constructor() {
    /** @type {!Array<!Object>} */
    this.calls = [];
    /**
     * The provider/model a failed call was sent to, with why it failed.
     * @type {!Array<{provider: string, model: string, kind: string}>}
     */
    this.failedAttempts = [];
  }

  /**
   * A provider whose every `generate` is recorded here. Failures are recorded
   * too (which provider, and why), then rethrown unchanged.
   * @param {!Object} provider An `AiProvider`-shaped object.
   * @return {!Object}
   */
  wrap(provider) {
    return {
      generate: async (request, opts) => {
        try {
          const response = await provider.generate(request, opts);
          this.record(response);
          return response;
        } catch (err) {
          if (err instanceof AiUnavailableError) {
            this.failedAttempts.push(...err.attempts);
          }
          throw err;
        }
      },
    };
  }

  /**
   * Folds one model response into the meter.
   * @param {!Object} response A router-stamped `NormalizedResponse`.
   */
  record(response) {
    const u = (response && response.usage) || {};
    const provider = response && response.provider;
    const model = response && response.model;
    const call = {
      provider,
      model,
      modelKey: response && response.modelKey,
      inputTokens: u.inputTokens || 0,
      outputTokens: u.outputTokens || 0,
      cacheReadTokens: u.cacheReadTokens || 0,
      cacheWriteTokens: u.cacheWriteTokens || 0,
      costUsd: costUsd(u, provider, model),
    };
    // Set only when the router actually fell back — see `../routing/
    // router.js` — so an ordinary (non-fallback) call's record shape is
    // unchanged.
    if (response && response.fallbackOccurred) {
      call.fallbackOccurred = true;
      call.fallbackReason = response.fallbackReason;
      call.requestedProvider = response.requestedProvider;
      call.requestedModel = response.requestedModel;
      call.failedAttempts = response.failedAttempts || [];
    }
    this.calls.push(call);
  }

  /** @return {boolean} Whether any model call went through the meter. */
  get used() {
    return this.calls.length > 0 || this.failedAttempts.length > 0;
  }
}

/**
 * A short, stable reason for a failed request — safe to store and show,
 * unlike a provider's raw error text.
 * @param {*} err
 * @return {string}
 */
function errorKindFor(err) {
  if (!err) return "unknown";
  if (err instanceof AiUnavailableError) return err.kind;
  if (err.code === "cancelled") return "cancelled";
  if (typeof err.code === "string" && err.name === "GatewayError") {
    return err.code;
  }
  return classifyProviderError(err);
}

/**
 * The usage record for one request.
 * @param {{feature: string, meter: !UsageMeter, dayKey: string,
 *   startedAt: !Date, finishedAt: !Date, error: *,
 *   extra: (!Object|undefined)}} args `error` set means the request failed;
 *   `extra` is merged in (e.g. an import's input kind).
 * @return {!Object}
 */
function buildUsageRecord(
    {feature, meter, dayKey, startedAt, finishedAt, error, extra}) {
  const calls = meter.calls;
  const sum = (field) => calls.reduce((n, c) => n + c[field], 0);
  const uncached = sum("inputTokens");
  const cacheRead = sum("cacheReadTokens");
  const cacheWrite = sum("cacheWriteTokens");
  // The model that did the work (one per request — see ../routing/router.js).
  const last = calls[calls.length - 1];
  const failed = meter.failedAttempts;
  const record = {
    feature,
    dayKey,
    status: error ?
      (errorKindFor(error) === "cancelled" ? "cancelled" : "error") : "ok",
    tokensIn: uncached + cacheRead + cacheWrite,
    uncachedTokensIn: uncached,
    cacheReadTokens: cacheRead,
    cacheWriteTokens: cacheWrite,
    tokensOut: sum("outputTokens"),
    costUsd: calls.reduce((n, c) => n + c.costUsd, 0),
    calls: calls.length,
    latencyMs: finishedAt.getTime() - startedAt.getTime(),
    createdAt: finishedAt,
    schemaVersion: USAGE_SCHEMA_VERSION,
  };
  // Who answered; on a failure, who was asked.
  const who = last || failed[failed.length - 1];
  if (who) {
    record.provider = who.provider;
    record.model = who.model;
    if (who.modelKey) record.modelKey = who.modelKey;
    if (who.fallbackOccurred) {
      record.fallbackOccurred = true;
      record.fallbackReason = who.fallbackReason;
      record.requestedProvider = who.requestedProvider;
      record.requestedModel = who.requestedModel;
    }
  }
  // Every provider attempt that failed on the way — the ones a fallback
  // recovered from as well as, for a failed request, the ones that sank it —
  // and how many calls needed the other provider.
  const fellBack = calls.filter((c) => c.fallbackOccurred);
  const failedAttempts = [
    ...fellBack.flatMap((c) => c.failedAttempts || []),
    ...failed,
  ];
  if (fellBack.length) record.fallbackCount = fellBack.length;
  if (failedAttempts.length) record.failedAttempts = failedAttempts;
  if (error) record.errorKind = errorKindFor(error);
  return Object.assign(record, extra || {});
}

/**
 * Writes the record, swallowing (and logging) a write failure: usage logging
 * must never turn a successful AI request into a user-facing error.
 * @param {!Object} store A store exposing `logUsage(uid, doc)`.
 * @param {string} uid
 * @param {!Object} record
 * @param {function(string, !Object): void=} warn
 * @return {!Promise<void>}
 */
async function saveUsageRecord(store, uid, record, warn) {
  try {
    await store.logUsage(uid, record);
  } catch (err) {
    if (warn) {
      warn("aiUsage write failed", {
        feature: record.feature,
        errorMessage: err && err.message,
      });
    }
  }
}

module.exports = {
  AiFeature,
  USAGE_SCHEMA_VERSION,
  UsageMeter,
  buildUsageRecord,
  saveUsageRecord,
  errorKindFor,
};
