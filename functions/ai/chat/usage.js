/**
 * Token accounting, cost, and usage limits for a chat turn.
 *
 * The turn loop calls the model several times; each call reports four kinds of
 * input/output tokens (uncached in, cache-read, cache-write, out). This module
 * accumulates them, applies the prompt-caching price multipliers, and answers
 * the two ceiling questions (per-day cap, per-turn token ceiling) — so the cost
 * math lives in one place instead of being threaded through `turn.js`.
 */

const {pricingFor} = require("./config");
const {costUsd: modelCostUsd} = require("../routing/models");

/**
 * Accumulates the four token buckets across the model calls of one turn and
 * derives totals + cost from them.
 */
class TurnUsage {
  /** Starts every bucket at zero; `add()` accumulates into them. */
  constructor() {
    this.uncachedTokensIn = 0;
    this.cacheReadTokens = 0;
    this.cacheWriteTokens = 0;
    this.tokensOut = 0;
    // Cost priced per call at the exact model that answered it — a turn can
    // span two providers when Auto falls back mid-loop, and each call must be
    // billed at its own rate. `_pricedCalls` counts the calls that carried a
    // provider stamp; with none, `totalCostUsd` falls back to `costUsd`.
    this._pricedCost = 0;
    this._pricedCalls = 0;
  }

  /**
   * Folds one model call's normalized usage into the running totals.
   * @param {?Object} usage A provider `resp.usage`
   *   (`{inputTokens, cacheReadTokens, cacheWriteTokens, outputTokens}`).
   * @param {?string=} provider The provider the router stamped on the
   *   response, when it did.
   * @param {?string=} model The provider-native model id that answered.
   */
  add(usage, provider, model) {
    const u = usage || {};
    if (provider) {
      this._pricedCost += modelCostUsd(u, provider, model);
      this._pricedCalls += 1;
    }
    this.uncachedTokensIn += u.inputTokens || 0;
    this.cacheReadTokens += u.cacheReadTokens || 0;
    this.cacheWriteTokens += u.cacheWriteTokens || 0;
    this.tokensOut += u.outputTokens || 0;
  }

  /**
   * Total input volume (uncached + cache read + cache write), so the per-turn
   * ceiling and per-day totals reflect real work done. Cost applies the caching
   * discounts to each slice separately (see `costUsd`).
   * @return {number}
   */
  get tokensIn() {
    return this.uncachedTokensIn + this.cacheReadTokens + this.cacheWriteTokens;
  }

  /**
   * Total input + output tokens accumulated so far this turn — the figure the
   * per-turn ceiling is checked against.
   * @return {number}
   */
  get total() {
    return this.tokensIn + this.tokensOut;
  }

  /**
   * The turn's dollar cost, priced at the rate of the provider that actually
   * answered, with cache reads/writes at that provider's multipliers. An
   * unknown or omitted `provider` prices at the default (Anthropic) — the
   * legacy `callModel` seam and buffered test fakes stamp no provider, so their
   * cost is unchanged from before per-provider pricing existed.
   * @param {?string=} provider The `usedProvider` the router stamped, e.g.
   *   'anthropic' | 'gemini'.
   * @return {number}
   */
  costUsd(provider) {
    const p = pricingFor(provider);
    return (
      this.uncachedTokensIn * p.inputPerToken +
      this.cacheWriteTokens * p.inputPerToken * p.cacheWriteMultiplier +
      this.cacheReadTokens * p.inputPerToken * p.cacheReadMultiplier +
      this.tokensOut * p.outputPerToken
    );
  }
}

/**
 * @param {TurnUsage} usage
 * @param {?string=} fallbackProvider Rates for a turn with no stamped calls.
 * @return {number} The turn's cost — per-call model pricing when the router
 *   stamped the calls, else the whole turn at `fallbackProvider`'s rates.
 */
function totalCostUsd(usage, fallbackProvider) {
  return usage._pricedCalls > 0 ?
    usage._pricedCost : usage.costUsd(fallbackProvider);
}

/**
 * What one `aiUsage` record costs against Ask's daily allowance — the ONE
 * definition of the rule, so the cap and anything that explains it agree.
 *
 *   - Only CHAT records count. Imports, plan generation, food search and
 *     transcription have their own quota buckets. A record with no `feature`
 *     predates the field and was always a chat turn.
 *   - A turn that FAILED (`error`) or was `cancelled` counts for nothing: it
 *     answered nothing, so a provider outage — or a fallback that still
 *     failed — never eats the allowance.
 *   - One user question is one turn, however many model calls it took:
 *     tool steps, the same-provider retry and the fallback to the other
 *     provider all live inside that one record.
 *   - Tokens are the FRESH tokens the turn spent: uncached input, cache
 *     writes, and output. Cache READS are left out. They're ZIVO's own
 *     system prompt and tool schemas re-read on every model call — ~84% of
 *     every token Ask logged on 2026-09-24, billed at 0.1x — and counting
 *     them at full weight tripped the 500K ceiling after 11 questions
 *     (~$0.34 of real spend) and showed "You've hit today's usage limit".
 *
 * @param {!Object} record An `aiUsage` document.
 * @return {{turns: number, tokens: number}}
 */
function dailyCapUsageFor(record) {
  const d = record || {};
  if (d.feature && d.feature !== "chat") return {turns: 0, tokens: 0};
  if (d.status === "error" || d.status === "cancelled") {
    return {turns: 0, tokens: 0};
  }
  const fresh = Math.max(0, (d.tokensIn || 0) - (d.cacheReadTokens || 0));
  return {turns: 1, tokens: fresh + (d.tokensOut || 0)};
}

/**
 * Whether the user has exhausted their allowance for the calendar day — by turn
 * count OR by token volume. `totals` is `store.getTodayUsageTotals()`'s result
 * (or null/undefined when nothing's been used yet).
 * @param {?{turns: number, tokens: number}} totals
 * @param {{perDayMaxTurns: number, perDayTokenCeiling: number}} cfg
 * @return {boolean}
 */
function isOverDailyCap(totals, cfg) {
  return Boolean(
      totals &&
      (totals.turns >= cfg.perDayMaxTurns ||
        totals.tokens >= cfg.perDayTokenCeiling));
}

// A crude bytes→tokens heuristic (~4 chars/token) for content WE generate and
// whose exact tokenization the provider never reports back — specifically the
// tool-result JSON. It is deliberately not the provider's tokenizer: it exists
// only to make "how much of this turn's input was tool output" observable and
// comparable across providers, not to bill against. Off by ~15%; never used for
// a ceiling or a charge.
const APPROX_CHARS_PER_TOKEN = 4;

/**
 * Approximate token count for `chars` characters of tool-result JSON. See
 * `APPROX_CHARS_PER_TOKEN` — this is an observability estimate, not a billed or
 * enforced figure.
 * @param {number} chars
 * @return {number}
 */
function approxTokensFromChars(chars) {
  return Math.round((chars || 0) / APPROX_CHARS_PER_TOKEN);
}

module.exports = {
  TurnUsage,
  totalCostUsd,
  dailyCapUsageFor,
  isOverDailyCap,
  approxTokensFromChars,
  APPROX_CHARS_PER_TOKEN,
};
