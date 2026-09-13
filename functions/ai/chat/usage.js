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
  }

  /**
   * Folds one model call's normalized usage into the running totals.
   * @param {?Object} usage A provider `resp.usage`
   *   (`{inputTokens, cacheReadTokens, cacheWriteTokens, outputTokens}`).
   */
  add(usage) {
    const u = usage || {};
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
  isOverDailyCap,
  approxTokensFromChars,
  APPROX_CHARS_PER_TOKEN,
};
