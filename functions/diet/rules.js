/**
 * The server's mirror of `lib/features/diet/domain/coaching/rules.dart`.
 *
 * **The coach's decisions are made here, not by the model.** This turns a
 * `DietState` into typed findings — observation / analysis / recommendation /
 * warning / encouragement / clarification — each carrying a deterministic
 * sentence that is correct on its own and an `evidence` list naming the state
 * fields it rests on. The model's job downstream is to phrase them; the
 * validator's job (Phase 7) is to reject anything the model says that these
 * don't support, and to fall back to this text when it does.
 *
 * A deliberate transliteration of the Dart engine, pinned by
 * `test/fixtures/coaching_vectors.json`, which BOTH suites run. Change one side
 * and the other fails until they agree again.
 */

/**
 * How many findings a turn may carry. A coach who lists six has said nothing.
 */
const MAX_FINDINGS = 3;

/** Below this, a protein gap is inside the noise of any real day's eating. */
const MIN_PROTEIN_SHORTFALL_G = 15;

/** The calorie budget is "running out" below this share of the target. */
const BUDGET_TIGHT_FRACTION = 0.35;

/** After this hour, an empty log stops being "the day is young". */
const EVENING_HOUR = 18;

/** Mirrors the Dart `kMinimumSafeCalories`. */
const MINIMUM_SAFE_CALORIES = 1200;

const SEVERITY_RANK = {info: 0, notable: 1, important: 2, urgent: 3};

const GOAL_LABEL = {
  fatLoss: "Fat loss",
  maintain: "Maintain",
  muscleGain: "Muscle gain",
  recomp: "Recomposition",
};

const BASIS_LABEL = {
  logged: "logged by you",
  tickedPlanMeals: "from the meals you ticked, not weighed",
  nothingLogged: "nothing logged yet",
};

/**
 * Findings for a target below the safety floor. These outrank everything and
 * are never capped out.
 * @param {!Object} state
 * @return {!Array<Object>}
 */
function safety(state) {
  const targets = state.targets;
  if (!targets || targets.calories >= MINIMUM_SAFE_CALORIES) return [];
  return [{
    code: "target_below_safety_floor",
    kind: "warning",
    severity: "urgent",
    text:
      `The daily target is set to ${targets.calories} kcal, below the ` +
      `${MINIMUM_SAFE_CALORIES} kcal floor ZIVO will coach to. Eating this ` +
      "low is worth talking through with a doctor or a registered " +
      "dietitian first.",
    evidence: ["targets.calories"],
  }];
}

/**
 * The state is too thin to coach from — saying so IS the coaching.
 * @param {!Object} state
 * @param {?number} localHour
 * @return {!Array<Object>}
 */
function blockers(state, localHour) {
  const out = [];

  if (state.quality.targetsUnset) {
    out.push({
      code: "targets_unset",
      kind: "clarification",
      severity: "important",
      text:
        "No daily target is set, so there's nothing to measure today " +
        "against. Setting a goal and a calorie target is what turns this " +
        "from a food diary into coaching.",
      evidence: ["quality.targetsUnset"],
    });
  }

  if (state.quality.nothingLogged) {
    // An empty log means nothing was RECORDED. Never reported as "you haven't
    // eaten".
    const late = typeof localHour === "number" && localHour >= EVENING_HOUR;
    out.push({
      code: "nothing_logged",
      kind: "clarification",
      severity: late ? "notable" : "info",
      text: late ?
        "Nothing's been logged today. Anything recorded now still counts " +
          "— and without it there are no numbers to work from." :
        "Nothing's logged yet today, so there's nothing to read into the " +
          "zero.",
      evidence: ["quality.nothingLogged", "consumed.basis"],
    });
  }

  return out;
}

/**
 * The recommendation the brief used as its worked example: protein short while
 * the calorie budget is running out. Fires only when both halves are true — a
 * protein gap at breakfast is not a problem.
 * @param {!Object} state
 * @return {?Object}
 */
function proteinShortfall(state) {
  const {targets, remaining} = state;
  const target = targets.proteinG;
  const short = remaining.proteinG;
  if (target === null || target === undefined ||
      short === null || short === undefined ||
      short <= MIN_PROTEIN_SHORTFALL_G) {
    return null;
  }
  const budgetLeft = remaining.kcal;
  if (budgetLeft > targets.calories * BUDGET_TIGHT_FRACTION) return null;

  const overBudget = budgetLeft <= 0;
  return {
    code: "protein_shortfall",
    kind: "recommendation",
    severity: "important",
    text: overBudget ?
      `${Math.round(short)}g short of the ${Math.round(target)}g protein ` +
        "target with the calorie budget already spent — worth prioritising " +
        "protein earlier tomorrow." :
      `${Math.round(short)}g short of the ${Math.round(target)}g protein ` +
        `target, with ${budgetLeft} kcal left. A lean protein source closes ` +
        "most of that gap without using much of what's left.",
    evidence: [
      "remaining.proteinG", "targets.proteinG",
      "remaining.kcal", "targets.calories",
    ],
  };
}

/**
 * Where the user stands against their objective, and what to do about it.
 * @param {!Object} state
 * @return {!Array<Object>}
 */
function progress(state) {
  const {targets, remaining} = state;
  if (!targets || !remaining || state.quality.nothingLogged) return [];

  const out = [{
    code: "calories_consumed",
    kind: "observation",
    severity: "info",
    text:
      `${state.consumed.kcal} of ${targets.calories} kcal so far ` +
      `(${BASIS_LABEL[state.consumed.basis]}).`,
    evidence: ["consumed.kcal", "targets.calories", "consumed.basis"],
  }];

  if (remaining.kcal < 0) {
    out.push({
      code: "calories_over_target",
      kind: "analysis",
      severity: "important",
      text:
        `That's ${-remaining.kcal} kcal past the ` +
        `${GOAL_LABEL[targets.goal].toLowerCase()} target of ` +
        `${targets.calories}.`,
      evidence: ["remaining.kcal", "targets.calories", "targets.goal"],
    });
  } else {
    out.push({
      code: "calories_remaining",
      kind: "analysis",
      severity: "info",
      text:
        `${remaining.kcal} kcal left against the ` +
        `${GOAL_LABEL[targets.goal].toLowerCase()} target.`,
      evidence: ["remaining.kcal", "targets.goal"],
    });
  }

  const protein = proteinShortfall(state);
  if (protein) out.push(protein);

  return out;
}

/**
 * Real wins, stated because they happened — never filler.
 * @param {!Object} state
 * @return {!Array<Object>}
 */
function wins(state) {
  const {targets, remaining} = state;
  if (!targets || !remaining || state.quality.nothingLogged) return [];

  const target = targets.proteinG;
  const left = remaining.proteinG;
  if (target === null || target === undefined ||
      left === null || left === undefined || left > 0) {
    return [];
  }
  return [{
    code: "protein_met",
    kind: "encouragement",
    severity: "notable",
    text:
      `Protein is already at ${Math.round(state.consumed.proteinG)}g against ` +
      `a ${Math.round(target)}g target — that part of the day is done.`,
    evidence: ["consumed.proteinG", "targets.proteinG"],
  }];
}

/**
 * What the numbers rest on — quiet, but never omitted, so the coach can't
 * present an assumption as a measurement.
 * @param {!Object} state
 * @return {!Array<Object>}
 */
function provenance(state) {
  const out = [];

  if (state.quality.consumedIsAssumed) {
    out.push({
      code: "consumption_assumed",
      kind: "clarification",
      // Notable, not info: a qualifier that says the numbers are assumptions
      // must never be dropped by the cap in favour of a readout of those same
      // numbers. Being wrong about what a figure MEANS is worse than omitting
      // the figure.
      severity: "notable",
      text:
        "Today's totals come from the meals ticked off the plan, not from " +
        "food that was weighed — so they say what the plan expected, not " +
        "what was actually eaten.",
      evidence: ["consumed.basis", "quality.consumedIsAssumed"],
    });
  }

  if (state.quality.hasEstimatedValues) {
    out.push({
      code: "estimated_values",
      kind: "clarification",
      // Notable for the same reason as `consumption_assumed`.
      severity: "notable",
      text:
        "Some of today's figures were estimated when the plan was " +
        "imported rather than measured, so treat them as approximate.",
      evidence: ["quality.hasEstimatedValues", "consumed.estimated"],
    });
  }

  const untracked = state.quality.untrackedMacros || [];
  if (untracked.length > 0 && !state.quality.targetsUnset) {
    out.push({
      code: "untracked_macros",
      kind: "clarification",
      severity: "info",
      text:
        `No target set for ${untracked.join(", ")} — there is nothing to ` +
        "be over or under on there.",
      evidence: ["quality.untrackedMacros"],
    });
  }

  return out;
}

/**
 * Builds the coaching findings for `state`, best-first, capped at
 * `MAX_FINDINGS`.
 * @param {!Object} state A `buildDietState` result.
 * @param {?number=} localHour The user's own hour of day (0–23), when known.
 * @return {!Array<Object>}
 */
function coachingFindings(state, localHour) {
  const all = [
    ...safety(state),
    ...blockers(state, localHour),
    ...progress(state),
    ...wins(state),
    ...provenance(state),
  ];
  // A stable sort by severity: same state in, same three out, in the same
  // order. Node's sort is stable, matching Dart's.
  return all
      .sort((a, b) => SEVERITY_RANK[b.severity] - SEVERITY_RANK[a.severity])
      .slice(0, MAX_FINDINGS);
}

module.exports = {
  coachingFindings,
  MAX_FINDINGS,
  MINIMUM_SAFE_CALORIES,
  EVENING_HOUR,
};
