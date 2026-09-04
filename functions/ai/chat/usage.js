/**
 * Token accounting, cost, and usage limits for a chat turn.
 *
 * The turn loop calls the model several times; each call reports four kinds of
 * input/output tokens (uncached in, cache-read, cache-write, out). This module
 * accumulates them, applies the prompt-caching price multipliers, and answers
 * the two ceiling questions (per-day cap, per-turn token ceiling) — so the cost
 * math lives in one place instead of being threaded through `turn.js`.
 */

const {
  INPUT_COST_PER_TOKEN_USD,
  OUTPUT_COST_PER_TOKEN_USD,
  CACHE_WRITE_MULTIPLIER,
  CACHE_READ_MULTIPLIER,
} = require("./config");

/**
 * Accumulates the four token buckets across the model calls of one turn and
 * derives totals + cost from them.
 */
class TurnUsage {
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
   * The turn's dollar cost, with cache reads/writes priced at their multipliers.
   * @return {number}
   */
  costUsd() {
    const inUsd = INPUT_COST_PER_TOKEN_USD;
    return (
      this.uncachedTokensIn * inUsd +
      this.cacheWriteTokens * inUsd * CACHE_WRITE_MULTIPLIER +
      this.cacheReadTokens * inUsd * CACHE_READ_MULTIPLIER +
      this.tokensOut * OUTPUT_COST_PER_TOKEN_USD
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

module.exports = {TurnUsage, isOverDailyCap};
