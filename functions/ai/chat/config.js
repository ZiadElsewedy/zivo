/**
 * Chat tuning knobs, model id, pricing, and the fixed user-facing messages.
 *
 * Everything that decides "how much work a turn may do" and "what the app says
 * when it can't answer" lives here, separated from the turn loop that enforces
 * it (`turn.js`) — so the ceilings and copy can be reviewed and changed without
 * reading the orchestration. `DEFAULT_CONFIG` is re-exported by `gateway.js`.
 */

const {MODELS, DEFAULT_MODEL_FOR_PROVIDER} = require("../routing/models");

// Provider-native default model for a chat turn. A route may override it.
// Read from the catalog rather than a second hardcoded literal, so this
// can't drift from it when the id changes.
const MODEL = MODELS["claude-sonnet"].id;

const DEFAULT_CONVERSATION_TITLE = "Ask";

const DEFAULT_CONFIG = {
  // MAX_AGENT_STEPS — the hard bound on the agent loop. One step is one model
  // call; a step that asks for tools runs them and feeds the results into the
  // next step. The LAST step is forced to answer (tools disabled via
  // `toolChoice: 'none'`), so a turn makes at most this many model calls and
  // up to `maxAgentSteps - 1` rounds of tools — never more, whatever the model
  // asks for. Provider retries (`../routing/router.js`) happen inside a step
  // and never add one. 6 = five tool rounds (enough for read diet → look up →
  // compare → calculate) plus the answer.
  maxAgentSteps: 6,
  // Immediate re-runs of a tool whose failure looks transient (a Firestore
  // hiccup — see `outcome.js` `isTransientToolError`). A retry is part of the
  // same step. If it still fails, the turn stops with `tool_error`.
  toolRetries: 1,
  // How many times the SAME tool may fail within one turn. A non-transient
  // failure (bad input) is fed back so the model can correct it once; the
  // second failure of that tool ends the turn with `tool_error` instead of
  // letting the model call it again and again.
  maxToolFailuresPerTool: 2,
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

// Pricing lives in ONE place — the model catalog (`../routing/models.js`) —
// and the per-provider table below is derived from it: a provider is priced at
// its default chat model (Anthropic → Claude Sonnet 5, Gemini → Gemini Flash).
// A turn whose calls were stamped with the exact model that answered is priced
// per model instead (see `usage.js` `TurnUsage.add`); these per-provider rates
// are the fallback for an unstamped call (the legacy seam, test fakes).

/**
 * @param {string} provider
 * @return {{inputPerToken: number, outputPerToken: number,
 *   cacheWriteMultiplier: number, cacheReadMultiplier: number}}
 */
function providerPricing(provider) {
  const p = MODELS[DEFAULT_MODEL_FOR_PROVIDER[provider]].pricing;
  return {
    inputPerToken: p.inputPerMTok / 1000000,
    outputPerToken: p.outputPerMTok / 1000000,
    cacheWriteMultiplier: p.cacheWriteMultiplier,
    cacheReadMultiplier: p.cacheReadMultiplier,
  };
}

const PRICING = {
  anthropic: providerPricing("anthropic"),
  gemini: providerPricing("gemini"),
};

// Kept as named exports for existing callers/tests: Claude Sonnet 5's rates.
const INPUT_COST_PER_TOKEN_USD = PRICING.anthropic.inputPerToken;
const OUTPUT_COST_PER_TOKEN_USD = PRICING.anthropic.outputPerToken;
const CACHE_WRITE_MULTIPLIER = PRICING.anthropic.cacheWriteMultiplier;
const CACHE_READ_MULTIPLIER = PRICING.anthropic.cacheReadMultiplier;

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

// ZIVO's OWN daily Ask allowance (`perDayMaxTurns`/`perDayTokenCeiling`,
// counted by `usage.js` `dailyCapUsageFor`) — not a provider limit. Worded
// so it can't be read as "Claude/Gemini are unavailable", which is a
// different state with its own message (`functions/index.js`
// `unavailableMessage`). Resets at the user's own midnight (`dayKeyFor`).
const DAILY_LIMIT_MESSAGE =
  "You've reached ZIVO's daily Ask limit. It resets at midnight. This is " +
  "ZIVO's own limit — Claude and Gemini are still available.";
const DAILY_LIMIT_MESSAGE_AR =
  "وصلت إلى حدّ Ask اليومي في ZIVO، ويتجدد عند منتصف الليل. هذا حدّ ZIVO " +
  "الخاص — Claude وGemini ما زالا متاحين.";
// The no-activity English form of the max-steps reply. A turn that ran any
// tools says what it actually did instead — see `outcome.js`
// `describeUnfinishedTurn`, which produces this exact text when nothing ran.
const ITERATION_LIMIT_MESSAGE =
  "I couldn't complete this request within the steps I can take for one " +
  "question. Try asking about one thing at a time.";
// The token budget running out ends the turn the same way the step budget
// does (`max_steps_reached`), so it says the same thing.
const TOKEN_CEILING_MESSAGE = ITERATION_LIMIT_MESSAGE;
// Handed to the model (as an uncached system block) on the forced final step:
// tools are disabled for that call, and this tells it why and what to say.
const FINAL_STEP_DIRECTIVE =
  "STEP LIMIT — this is your final step for this question and tools are " +
  "now disabled. Answer now using only the tool results you already have. " +
  "If they aren't enough for a complete answer, say plainly what you " +
  "checked, what you couldn't finish, and what the user can ask next. Do " +
  "not invent any figure you didn't read.";
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
  DAILY_LIMIT_MESSAGE_AR,
  ITERATION_LIMIT_MESSAGE,
  TOKEN_CEILING_MESSAGE,
  FINAL_STEP_DIRECTIVE,
  REFUSAL_MESSAGE,
  FALLBACK_MESSAGE,
  PENDING_ACTION_MESSAGE,
};
