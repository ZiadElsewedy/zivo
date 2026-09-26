/**
 * The REASONING POLICY — which Claude model answers a turn, and how hard it
 * thinks, decided by the server per turn. The user never picks either (they
 * pick a provider; this chooses within it).
 *
 * One decision, not loose knobs. The policy picks a TIER; a tier is a fixed
 * (model, level) pair; a level means one coherent setting per model — effort
 * and thinking together — defined once in the model catalog
 * (`../routing/models.js` `reasoning`) and applied by the Claude provider. So
 * no combination can exist that nobody chose on purpose.
 *
 *   lookup    small talk / general knowledge: Sonnet at low effort
 *   standard  a normal question about one area, a change, a tapped option:
 *             Sonnet at medium effort
 *   deep      a decision or recommendation, a safety-sensitive question, or
 *             a turn ZIVO can't place in one area: Sonnet at high effort —
 *             exactly what every turn got before Phase 8
 *
 * Why these values (Phase 8 eval, 2026-09-26 — `functions/eval/ask_effort/`,
 * results in `.claude/hillclimb/ask-effort-{pilot,full-partial}/`): against
 * a same-setting control, Sonnet low and medium showed no measurable quality
 * loss and answered ~25–35% faster at ~20% lower cost; Claude Haiku 4.5 lost
 * all 18 judged turns (Egyptian-dialect slips, an English preamble on Arabic
 * replies), so no tier uses it. The eval was small (the owner stopped paid
 * testing): AMBIGUOUS and safety-sensitive turns therefore stay at high
 * effort, and the policy's aiUsage records (`reasoning`) are the ongoing
 * check. Re-evaluating with real API calls needs the owner's approval.
 *
 * Pure: no I/O. `turn.js` hands it what it already knows (the routed intent,
 * the words, a tapped option, what the ledger holds).
 */

const {Intent} = require("./intent");
const {modelSpec, reasoningFor} = require("../routing/models");

/** @enum {string} */
const Tier = {
  LOOKUP: "lookup",
  STANDARD: "standard",
  DEEP: "deep",
};

/** Each tier's model and level. Validated by `assertTiers`. */
const DEFAULT_TIERS = {
  [Tier.LOOKUP]: {model: "claude-sonnet", level: "low"},
  [Tier.STANDARD]: {model: "claude-sonnet", level: "medium"},
  [Tier.DEEP]: {model: "claude-sonnet", level: "high"},
};

// A turn that asks ZIVO to judge, advise, plan or explain why — the answer
// is a decision, not a read-out. English/Arabizi as whole words or prefixes;
// Arabic (Egyptian) as substrings.
const DECISION_EN = new RegExp("\\b(should|shall|why|recommend\\w*|advice|" +
  "advise|suggest\\w*|plan|plans|better|best|worth|ok to|okay to|" +
  "analy[sz]\\w*|progress\\w*|improv\\w*|stuck|plateau\\w*|compare|" +
  "instead|swap|replace|how am i doing|how is my|how's my|going|" +
  "a7sn|ahsan|el mafrood|el mafroud|a3mel eh|a3mel eih|leh|leih)\\b");
const DECISION_AR = new RegExp("ليه|ازاي|أزاي|المفروض|انصح|تنصح|" +
  "نصيحه|نصيحة|احسن|أحسن|ولا |اعمل ايه|أعمل ايه|نعمل ايه|اختار|" +
  "بدل|خطه|خطة|مستوى|تقدم|ينفع");

// Health and safety: pain or injury, very low intakes, fasting, targets —
// where a careless answer does harm. Always the most careful tier.
const SAFETY_EN = new RegExp("\\b(pain|hurts?|injur\\w*|sore|dizz\\w*|" +
  "faint\\w*|sick|doctor|medic\\w*|pregnan\\w*|diabet\\w*|" +
  "eating disorder|starv\\w*|fasting|crash|deficit|lose weight fast|" +
  "\\d{3,4} ?(kcal|cal|calories))\\b|\\b(set|change|new|lower|raise)\\b" +
  ".*\\btarget");
const SAFETY_AR = new RegExp("وجع|بيوجعني|ألم|اصابه|إصابة|اصابة|دكتور|" +
  "دوخه|دوخة|حامل|صيام|تجويع|رجيم قاسي");

// A request to change something — a proposal must be right, and the model
// has to resolve what the user means first.
const CHANGE_EN =
  /\b(log|add|mark|delete|remove|change|set|edit|update|record)\b/;
const CHANGE_AR = /سجل|سجّل|ضيف|أضف|اضف|امسح|احذف|غير|عدل|علم/;

/**
 * Whether the words ask for a judgement rather than a read-out.
 * @param {string} text
 * @return {boolean}
 */
function asksForDecision(text) {
  const s = String(text || "").toLowerCase();
  return DECISION_EN.test(s) || DECISION_AR.test(s);
}

/**
 * Whether the words touch health or safety.
 * @param {string} text
 * @return {boolean}
 */
function touchesSafety(text) {
  const s = String(text || "").toLowerCase();
  return SAFETY_EN.test(s) || SAFETY_AR.test(s);
}

/**
 * Whether the words ask ZIVO to change the user's data.
 * @param {string} text
 * @return {boolean}
 */
function asksForChange(text) {
  const s = String(text || "").toLowerCase();
  return CHANGE_EN.test(s) || CHANGE_AR.test(s);
}

/**
 * The tier for one turn, and why.
 * @param {!Object} args
 * @param {{intent: string, reason: string}} args.routed `classifyIntent`.
 * @param {string} args.message The user's words (a tapped option's label).
 * @param {boolean=} args.picked The turn answers a question card.
 * @return {{tier: string, reason: string}}
 */
function tierFor({routed, message, picked}) {
  const intent = routed ? routed.intent : Intent.AMBIGUOUS;
  // Safety first: a question about pain or a crash diet is never "small".
  if (touchesSafety(message)) return {tier: Tier.DEEP, reason: "safety"};
  if (intent === Intent.GENERAL) {
    return {tier: Tier.LOOKUP, reason: "general"};
  }
  if (asksForChange(message)) return {tier: Tier.STANDARD, reason: "change"};
  if (picked) return {tier: Tier.STANDARD, reason: "picked_option"};
  if (asksForDecision(message)) return {tier: Tier.DEEP, reason: "decision"};
  // Unplaced turns carry the full prompt and every tool, and the eval's
  // medium-effort losses were concentrated on them — kept at high.
  if (intent === Intent.AMBIGUOUS) {
    return {tier: Tier.DEEP, reason: "ambiguous"};
  }
  return {tier: Tier.STANDARD, reason: "contextual"};
}

/**
 * Throws unless every tier names a catalog model that offers its level —
 * so a bad config fails at deploy/test time, not as a half-applied request.
 * @param {!Object<string, {model: string, level: string}>} tiers
 */
function assertTiers(tiers) {
  for (const [tier, t] of Object.entries(tiers)) {
    if (!t || !modelSpec(t.model) || !reasoningFor(t.model, t.level)) {
      throw new Error(`Reasoning tier "${tier}" is not a model/level the ` +
        `catalog offers: ${JSON.stringify(t)}`);
    }
  }
}

/**
 * The turn's reasoning plan, or null when the policy doesn't apply (off, or
 * the user's provider has no reasoning settings — Gemini).
 *
 * `cfg.override` ({model, level}) forces one plan for every turn — the eval's
 * fixed variants; `mode: "auto"` runs `tierFor`.
 *
 * @param {!Object} args
 * @param {{mode: string, tiers: (!Object|undefined),
 *   override: ?{model: string, level: string}}} args.cfg `config.reasoning`.
 * @param {string} args.provider The provider the user's selection resolved
 *   to (`anthropic` | `gemini`).
 * @param {{intent: string, reason: string}} args.routed
 * @param {string} args.message
 * @param {boolean=} args.picked
 * @return {?{tier: ?string, model: string, level: string, reason: string}}
 */
function planTurn({cfg, provider, routed, message, picked}) {
  const c = cfg || {};
  if (c.override) {
    const {model, level} = c.override;
    const spec = modelSpec(model);
    if (!spec || spec.provider !== provider || !reasoningFor(model, level)) {
      return null;
    }
    return {tier: null, model, level, reason: "override"};
  }
  if (c.mode !== "auto") return null;
  const tiers = Object.assign({}, DEFAULT_TIERS, c.tiers || {});
  const {tier, reason} = tierFor({routed, message, picked});
  const t = tiers[tier];
  const spec = t ? modelSpec(t.model) : undefined;
  // A tier on another provider's model can't apply to this user's turn.
  if (!spec || spec.provider !== provider) return null;
  return {tier, model: t.model, level: t.level, reason};
}

assertTiers(DEFAULT_TIERS);

module.exports = {
  Tier,
  DEFAULT_TIERS,
  planTurn,
  tierFor,
  asksForDecision,
  asksForChange,
  touchesSafety,
  assertTiers,
};
