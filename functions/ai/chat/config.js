/**
 * Chat tuning knobs, model id, pricing, and the fixed user-facing messages.
 *
 * Everything that decides "how much work a turn may do" and "what the app says
 * when it can't answer" lives here, separated from the turn loop that enforces
 * it (`turn.js`) — so the ceilings and copy can be reviewed and changed without
 * reading the orchestration. `DEFAULT_CONFIG` is re-exported by `gateway.js`.
 */

// Provider-native default model for a chat turn. A route may override it.
const MODEL = "claude-sonnet-5";

const DEFAULT_CONVERSATION_TITLE = "Ask";

const DEFAULT_CONFIG = {
  // Max model↔tool round-trips per turn before aborting cleanly.
  maxIterations: 5,
  // Max input+output tokens accumulated within a single turn.
  perTurnTokenCeiling: 50000,
  // Max turns (aiUsage docs) for the same calendar day.
  perDayMaxTurns: 100,
  // Max input+output tokens across the same calendar day.
  perDayTokenCeiling: 500000,
  // How many recent persisted messages are sent as history each turn. Kept
  // deliberately small: history is re-sent on every model call in the turn, so
  // a tighter window directly bounds the quadratic input-token growth.
  historyWindow: 10,
  // Longest a single tool result may be (in characters of its JSON) before it
  // is truncated. Large tool payloads (e.g. get_today, summarize_week) are
  // re-sent on every subsequent model call in the turn, so bounding them caps
  // the accumulated cost without starving the model of data.
  maxToolResultChars: 6000,
  // Longest user message accepted, in characters.
  maxMessageChars: 2000,
  // `max_tokens` passed to the model on every call.
  maxTokens: 2048,
  // How long a proposed (pending) action can wait before it expires (ADR-003).
  pendingActionTtlMs: 60 * 60 * 1000,
};

// Claude Sonnet 5 pricing (owner-confirmed, 2026-08-15): $3 / 1M input
// tokens, $15 / 1M output tokens. Cost is computed and logged, never shown
// to the model.
const INPUT_COST_PER_TOKEN_USD = 3 / 1000000;
const OUTPUT_COST_PER_TOKEN_USD = 15 / 1000000;
// Prompt-caching multipliers on the base input price (Anthropic pricing):
// writing a cache entry costs 1.25x, reading one back costs 0.1x.
const CACHE_WRITE_MULTIPLIER = 1.25;
const CACHE_READ_MULTIPLIER = 0.1;

// Per-provider token pricing, so a turn's cost is logged at the rate of the
// provider that ACTUALLY answered (the router stamps it as `usedProvider`; an
// `Auto` turn that fell back to Gemini is priced as Gemini). Anthropic reuses
// the constants above unchanged, so existing cost behaviour and the cost test
// are preserved exactly.
const PRICING = {
  anthropic: {
    inputPerToken: INPUT_COST_PER_TOKEN_USD,
    outputPerToken: OUTPUT_COST_PER_TOKEN_USD,
    cacheWriteMultiplier: CACHE_WRITE_MULTIPLIER,
    cacheReadMultiplier: CACHE_READ_MULTIPLIER,
  },
  // `gemini-flash-latest` is a ROLLING ALIAS (see routing/router.js) → whatever
  // Google's current Flash is. These are Google's published Gemini 2.5 Flash
  // list rates, standard tier (≤200k-token context): $0.30 / 1M input,
  // $2.50 / 1M output. Two deliberate caveats:
  //   1. Owner-confirm these the way the Anthropic rate was — they are
  //      published list prices, not a billed invoice. Adjust the two numbers
  //      if the actual rate differs; nothing else needs to change.
  //   2. The model id is a rolling alias, so the rate can move under it.
  //      Revisit when the alias points at a new Flash tier.
  // Cache multipliers are INERT today: the chat path reports no cache
  // read/write tokens for Gemini (confirmed by the validation telemetry), so a
  // Gemini turn's cost depends only on the input/output rates. They are set to
  // sane values for the day a Gemini cache path exists, not because one does.
  gemini: {
    inputPerToken: 0.30 / 1000000,
    outputPerToken: 2.50 / 1000000,
    cacheWriteMultiplier: 1.0,
    cacheReadMultiplier: 0.25,
  },
};

// The provider a turn is priced at when the response carried no provider stamp
// — the legacy `callModel` seam and every buffered test fake. Anthropic is
// primary, so this keeps historical cost behaviour identical.
const DEFAULT_PRICING_PROVIDER = "anthropic";

/**
 * The pricing entry for `provider`, falling back to the default provider's
 * rates for an unknown or absent provider — so the cost math always has real
 * numbers and can never `NaN` out on a missing stamp.
 * @param {?string} provider
 * @return {{inputPerToken: number, outputPerToken: number,
 *   cacheWriteMultiplier: number, cacheReadMultiplier: number}}
 */
function pricingFor(provider) {
  return PRICING[provider] || PRICING[DEFAULT_PRICING_PROVIDER];
}

const DAILY_LIMIT_MESSAGE =
  "You've hit today's usage limit for Ask. It resets tomorrow — thanks " +
  "for your patience!";
const ITERATION_LIMIT_MESSAGE =
  "I couldn't complete that in time — could you try asking in a simpler " +
  "way, or split it into smaller questions?";
const TOKEN_CEILING_MESSAGE =
  "That question needed more digging than I'm allowed to do in one go — " +
  "could you narrow it down a bit?";
const REFUSAL_MESSAGE = "I'm not able to help with that one.";
const FALLBACK_MESSAGE = "I don't have anything to add for that.";
// Shown when the model tries to propose a change while one is already awaiting
// the user's confirmation. The existing card is the single confirm path (there
// is no free-text confirm), so we steer the user back to it rather than mint a
// second pending action — which would risk a duplicate write on double-confirm.
const PENDING_ACTION_MESSAGE =
  "You've already got a suggestion waiting above — tap Confirm or Cancel on " +
  "it first, then I can help with the next thing.";

module.exports = {
  MODEL,
  DEFAULT_CONVERSATION_TITLE,
  DEFAULT_CONFIG,
  INPUT_COST_PER_TOKEN_USD,
  OUTPUT_COST_PER_TOKEN_USD,
  CACHE_WRITE_MULTIPLIER,
  CACHE_READ_MULTIPLIER,
  PRICING,
  DEFAULT_PRICING_PROVIDER,
  pricingFor,
  DAILY_LIMIT_MESSAGE,
  ITERATION_LIMIT_MESSAGE,
  TOKEN_CEILING_MESSAGE,
  REFUSAL_MESSAGE,
  FALLBACK_MESSAGE,
  PENDING_ACTION_MESSAGE,
};
