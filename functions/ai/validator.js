/**
 * The advice validator + safety intercept (Diet Coach Phase 7 — T8, T15).
 *
 * Everything upstream makes a wrong sentence *unlikely*: the numbers only move
 * downward through the stack, the rules engine decides what to say, and the
 * prompt tells the model to phrase findings rather than invent claims. This is
 * the layer that makes a wrong sentence *catchable*. After the model produces
 * its reply, `validateAdvice` compares it to the `DietState` it was handed and
 * — because every finding already carries a correct deterministic sentence — a
 * rejection is never a dead end: the user still gets the right answer, in the
 * engine's plainer voice.
 *
 * It is deliberately server-only. Coach replies are generated only in the
 * gateway, so unlike the state/rules/nutrition layers there is no Dart mirror
 * to keep in step — the app never runs this.
 *
 * Two jobs, in priority order:
 *
 * 1. **Safety intercept (T15).** A coach that *recommends* eating below the
 *    safety floor is stopped outright and replaced with a message pointing at a
 *    professional. This is the deterministic backstop behind the one prompt
 *    sentence that used to be the whole safety story.
 * 2. **Contradiction check (T8).** Every calorie figure the reply states about
 *    the user's own day must trace to the state — consumed, remaining, the
 *    target, a plan meal, or a logged food — within a rounding tolerance.
 *    A figure that matches none is either invented or contradicts what the
 *    screen shows, and the reply falls back to the findings' text. Plus two
 *    qualitative checks the prompt cares about most: claiming the user ate when
 *    nothing was logged, and calling them "over"/"under" on a macro they set no
 *    target for.
 *
 * Precision is the priority over recall: a false rejection replaces a good,
 * specific reply with terser deterministic text, which is worse than letting a
 * borderline reply through. So hypotheticals ("if you added a shake…") and
 * general-knowledge facts ("chicken is ~165 kcal per 100 g") are excluded, and
 * the numeric check only fires when a figure is clearly attached to the user's
 * own day.
 */

const {MINIMUM_SAFE_CALORIES} = require("../diet/rules");

// A stated total is "the same" as a state figure within the larger of an
// absolute and a relative tolerance — the model rounds ("about 1,200"), and
// that is not a contradiction.
const KCAL_ABS_TOLERANCE = 25;
const KCAL_REL_TOLERANCE = 0.06;

const SAFETY_MESSAGE =
  "I can't get behind eating that little — that's low enough that it's worth " +
  "talking through with a doctor or a registered dietitian before you try it. " +
  "I'm glad to help you build something sustainable instead.";

// A calorie figure with its unit: "1,180 kcal", "500 calories". Requires the
// unit so a bare number (reps, grams, a time) is never mistaken for calories.
const KCAL_RE =
  /(\d{1,3}(?:,\d{3})+|\d+)\s*(?:kilocalories|kcal|calories|calorie|cals|cal)\b/gi;

/**
 * Splits text into rough sentences. Good enough to keep a claim and its
 * context together — the validator reasons one sentence at a time.
 * @param {string} text
 * @return {!Array<string>}
 */
function sentences(text) {
  return String(text)
      .split(/(?<=[.!?])\s+|\n+/)
      .map((s) => s.trim())
      .filter(Boolean);
}

/**
 * "1,180" → 1180. Strips grouping commas and whitespace.
 * @param {string} raw
 * @return {number}
 */
function parseNum(raw) {
  return parseInt(String(raw).replace(/[,\s]/g, ""), 10);
}

/**
 * Whether `claim` is within tolerance of `actual`.
 * @param {number} claim
 * @param {number} actual
 * @return {boolean}
 */
function withinTolerance(claim, actual) {
  const diff = Math.abs(claim - actual);
  return diff <= KCAL_ABS_TOLERANCE ||
    diff <= Math.abs(actual) * KCAL_REL_TOLERANCE;
}

/**
 * Every calorie figure in the reply that could be cited as a *component* of the
 * user's day — a logged food, a plan meal, the plan's own sum, the recent
 * average. Allowed in any context, because the coach can mention any of them
 * while talking about the day.
 * @param {!Object} ctx The diet payload (a `stateForModel` result).
 * @return {!Array<number>}
 */
function componentAnchors(ctx) {
  // The safety floor is a legitimate figure the coach cites when relaying the
  // sub-floor-target warning ("…below the 1,200 kcal floor…"); it is a constant,
  // not a state field, so it is allowed everywhere rather than read as invented.
  const anchors = [MINIMUM_SAFE_CALORIES];
  if (typeof ctx.plannedKcal === "number") anchors.push(ctx.plannedKcal);
  if (ctx.history && typeof ctx.history.averageKcal === "number") {
    anchors.push(ctx.history.averageKcal);
  }
  for (const m of ctx.meals || []) {
    if (typeof m.kcal === "number") anchors.push(m.kcal);
  }
  for (const e of ctx.logEntries || []) {
    if (typeof e.kcal === "number") anchors.push(e.kcal);
  }
  return anchors;
}

// The keyword families that mark a sentence as being about the user's own
// standing — as opposed to a general fact or a hypothetical.
const CONSUMED_RE =
  /\b(eaten|ate|consumed|logged|had|taken in|so far|puts? you at|you're at|youre at|brought you to)\b/i;
const REMAINING_RE = /\b(left|remaining|to go|to spare|budget)\b/i;
const TARGET_RE = /\b(target|goal|aim(?:ing)? for|shoot for)\b/i;
// Conditional / future framing — a number here is a projection, not a claim
// about what has happened, so it is not checked against the day's totals.
const HYPOTHETICAL_RE =
  /\b(if|would|were to|once you|after you|suppose|imagine|you'?d|could (?:eat|have|add)|potential(?:ly)?)\b/i;

/**
 * Detects a reply that *recommends* eating below the safety floor. A sentence
 * that WARNS about a low number (the user's own sub-floor target, say) is not a
 * recommendation and is left alone — that is the coach doing its job.
 * @param {string} reply
 * @return {?Object} A violation, or null.
 */
// Prescriptive, RESTRICTIVE intent — the coach telling the user to cap intake,
// as opposed to observing it or telling them to eat more. Kept free of digits so
// a multi-digit calorie figure doesn't defeat the match; the number is checked
// separately.
const RESTRICTIVE_RE =
  /\b(aim(?:ing)? for|only eat|eat only|eat just|just eat|stick to|limit(?:ed)?(?: it| yourself)? to|cut (?:down|back)? ?to|drop (?:down )?to|go down to|keep (?:it )?(?:under|below|to)|stay (?:under|below)|shoot for|budget of|target of|restrict(?:ing)?(?: yourself)? to|no more than|max(?:imum)? of)\b/i;
// The opposite intent — a sub-floor number here is the coach noting intake is
// LOW and pushing it up, which must never be intercepted as a starvation diet.
const ENCOURAGE_MORE_RE =
  /\b(more|at least|bump|increase|add another|get in more|higher|up your|too little|not enough)\b/i;
// A low number the coach is flagging (a warning) rather than prescribing.
const SAFETY_WARNING_RE =
  /\b(below|too low|floor|not safe|unsafe|dangerous|doctor|dietitian|professional|risk|worth (?:checking|talking))\b/i;

/**
 * Detects a reply that *recommends* eating below the safety floor. A sentence
 * that WARNS about a low number (the user's own sub-floor target, say) or pushes
 * intake UP is not a recommendation and is left alone.
 * @param {string} reply
 * @return {?Object} A violation, or null.
 */
function detectUnsafe(reply) {
  for (const sentence of sentences(reply)) {
    if (SAFETY_WARNING_RE.test(sentence)) continue;
    if (ENCOURAGE_MORE_RE.test(sentence)) continue;
    if (!RESTRICTIVE_RE.test(sentence)) continue;
    KCAL_RE.lastIndex = 0;
    let match;
    while ((match = KCAL_RE.exec(sentence)) !== null) {
      const n = parseNum(match[1]);
      if (n > 0 && n < MINIMUM_SAFE_CALORIES) {
        return {code: "unsafe_low_calorie_advice", kind: "safety", value: n};
      }
    }
  }
  return null;
}

/**
 * The macro words for a tracked/untracked macro name.
 * @param {string} macro 'protein' | 'carbs' | 'fat'
 * @return {!RegExp}
 */
function macroWordRe(macro) {
  if (macro === "carbs") return /\bcarb(?:s|ohydrate(?:s)?)?\b/i;
  if (macro === "fat") return /\bfats?\b/i;
  return /\bprotein\b/i;
}

/**
 * The contradiction checks. Returns a de-duplicated list of violations.
 * @param {string} reply
 * @param {!Object} ctx The diet payload.
 * @return {!Array<Object>}
 */
function detectContradictions(reply, ctx) {
  const found = new Map();
  const add = (v) => {
    if (!found.has(v.code)) found.set(v.code, v);
  };

  const quality = ctx.quality || {};
  const consumed = ctx.consumed || {};
  const remaining = ctx.remaining || null;
  const targets = ctx.targets || null;
  const base = componentAnchors(ctx);

  for (const sentence of sentences(reply)) {
    if (HYPOTHETICAL_RE.test(sentence)) continue;
    const hasConsumed = CONSUMED_RE.test(sentence);
    const hasRemaining = REMAINING_RE.test(sentence);
    const hasTarget = TARGET_RE.test(sentence);

    // Qualitative: claiming the user ate, when nothing was logged. An empty log
    // means nothing was RECORDED, not that nothing was eaten — the prompt is
    // emphatic about this, so a flat "you've eaten…" is a contradiction.
    if (quality.nothingLogged && hasConsumed &&
        /\byou(?:'ve| have)?\s+(?:eaten|ate|consumed|logged|had)\b/i
            .test(sentence)) {
      add({code: "ate_but_nothing_logged", kind: "contradiction"});
    }

    // Qualitative: "over"/"under" on a macro with no target set.
    if (Array.isArray(quality.untrackedMacros) &&
        /\b(over|under|above|below|short on|low on|high on|exceed(?:ed|ing)?|surpass(?:ed)?)\b/i
            .test(sentence)) {
      for (const macro of quality.untrackedMacros) {
        if (macroWordRe(macro).test(sentence)) {
          add({code: "untracked_macro_claim", kind: "contradiction", macro});
        }
      }
    }

    // Numeric: a calorie figure attached to the user's day must trace to state.
    if (!(hasConsumed || hasRemaining || hasTarget)) continue;
    const allowed = base.slice();
    if (hasConsumed && typeof consumed.kcal === "number") {
      allowed.push(consumed.kcal);
    }
    if (hasRemaining) {
      if (remaining && typeof remaining.kcal === "number") {
        allowed.push(remaining.kcal);
      }
      if (targets && typeof targets.calories === "number") {
        allowed.push(targets.calories);
      }
    }
    if (hasTarget && targets && typeof targets.calories === "number") {
      allowed.push(targets.calories);
    }

    KCAL_RE.lastIndex = 0;
    let match;
    while ((match = KCAL_RE.exec(sentence)) !== null) {
      const n = parseNum(match[1]);
      if (!Number.isFinite(n)) continue;
      if (allowed.some((a) => withinTolerance(n, a))) continue;
      // A figure that matches nothing in the state. Name the most specific
      // reason the state can give.
      if (hasTarget && quality.targetsUnset) {
        add({code: "target_but_unset", kind: "contradiction", value: n});
      } else if (hasConsumed && quality.nothingLogged) {
        add({code: "ate_but_nothing_logged", kind: "contradiction", value: n});
      } else {
        add({code: "numeric_contradiction", kind: "contradiction", value: n});
      }
    }
  }

  return [...found.values()];
}

/**
 * The deterministic reply to fall back to when the model's is rejected. The
 * findings are already correct standalone sentences, so joining them is a
 * complete, honest answer in the engine's plainer voice. With no findings, a
 * plain readout of the state — never a number the coach can't stand behind.
 * @param {!Object} ctx The diet payload.
 * @return {string}
 */
function deterministicFallback(ctx) {
  const findings = Array.isArray(ctx.findings) ? ctx.findings : [];
  const text = findings.map((f) => f && f.text).filter(Boolean).join(" ");
  if (text) return text;

  const quality = ctx.quality || {};
  if (quality.nothingLogged) {
    return "Nothing's logged yet today, so there's no total to go on — log a " +
      "meal and I'll have real numbers to work from.";
  }
  if (ctx.targets && ctx.consumed &&
      typeof ctx.consumed.kcal === "number") {
    const basis = ctx.consumed.basisLabel || ctx.consumed.basis || "";
    return `You're at ${ctx.consumed.kcal} of ${ctx.targets.calories} kcal ` +
      `so far${basis ? ` (${basis})` : ""}.`;
  }
  return "I'd rather not give you a number I can't stand behind — let me pull " +
    "your diet back up and go from what's actually there.";
}

/**
 * Validates a coach reply against the diet state it was handed.
 *
 * @param {?string} reply The model's final text.
 * @param {?Object} context The diet payload from the turn's `get_diet` /
 *   `get_today` result (state + findings), or null when the turn read no diet
 *   data — nothing to validate against, so anything passes.
 * @return {!Object} `{ok, safe, violations, replacement}`. `replacement` is the
 *   text to use instead of the model's when `ok` is false; null otherwise.
 */
function validateAdvice(reply, context) {
  if (!context || typeof reply !== "string" || reply.trim() === "") {
    return {ok: true, safe: true, violations: [], replacement: null};
  }

  // Safety outranks everything and short-circuits.
  const unsafe = detectUnsafe(reply);
  if (unsafe) {
    return {
      ok: false, safe: false, violations: [unsafe], replacement: SAFETY_MESSAGE,
    };
  }

  const violations = detectContradictions(reply, context);
  if (violations.length === 0) {
    return {ok: true, safe: true, violations: [], replacement: null};
  }
  return {
    ok: false,
    safe: true,
    violations,
    replacement: deterministicFallback(context),
  };
}

module.exports = {
  validateAdvice,
  deterministicFallback,
  SAFETY_MESSAGE,
};
