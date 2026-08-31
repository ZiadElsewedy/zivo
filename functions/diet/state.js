/**
 * The server's mirror of `lib/features/diet/domain/diet_state_builder.dart`.
 *
 * **Why a mirror rather than a second design.** The Diet screen renders a
 * `DietState` and the coach is handed one; if those are built by two different
 * pieces of reasoning they will eventually disagree, and a coach that
 * contradicts the screen is worse than no coach. So this is a deliberate
 * transliteration — same rules, same order, same edge cases — pinned by
 * `test/fixtures/diet_state_vectors.json`, which BOTH suites run. Change one
 * side and the other's test fails until they agree again.
 *
 * Pure: every input is passed in. The store-backed assembly lives in
 * `functions/ai/tools.js`.
 */

/** Consumed-basis vocabulary. Mirrors the Dart `ConsumedBasis`. */
const BASIS = {
  LOGGED: "logged",
  TICKED_PLAN_MEALS: "tickedPlanMeals",
  NOTHING_LOGGED: "nothingLogged",
};

/** How each basis should be described. Mirrors `consumedBasisLabel`. */
const BASIS_LABEL = {
  [BASIS.LOGGED]: "logged by you",
  [BASIS.TICKED_PLAN_MEALS]: "from the meals you ticked, not weighed",
  [BASIS.NOTHING_LOGGED]: "nothing logged yet",
};

/**
 * @param {number} v
 * @return {number} `v` to one decimal place.
 */
function round1(v) {
  return Math.round(v * 10) / 10;
}

/**
 * Whether a meal is the SUPPLEMENTS block rather than a real meal. Mirrors the
 * Dart `isSupplementMeal`: supplements are tracked but never counted toward
 * meal counts or the energy budget.
 * @param {!Object} meal
 * @return {boolean}
 */
function isSupplement(meal) {
  return String(meal.label || "").trim().toLowerCase().includes("supplement");
}

/**
 * Sums a meal's stated calories, or null when no item states any — the
 * "absent, not zero" rule the whole feature follows.
 * @param {!Object} meal
 * @return {?number}
 */
function mealCalories(meal) {
  let total = 0;
  let stated = false;
  for (const item of meal.items || []) {
    if (typeof item.calories === "number" && Number.isFinite(item.calories)) {
      total += item.calories;
      stated = true;
    }
  }
  return stated ? total : null;
}

/**
 * Whether any of a meal's items carries AI-estimated figures.
 * @param {!Object} meal
 * @return {boolean}
 */
function mealEstimated(meal) {
  return (meal.items || []).some((i) => i && i.estimated === true);
}

/**
 * The log when it has anything; the planned figures of ticked meals when it
 * doesn't. The basis says which.
 * @param {!Array<Object>} log
 * @param {!Array<Object>} allMeals
 * @param {!Set<string>} consumedMealIds
 * @return {!Object}
 */
function consumedFrom(log, allMeals, consumedMealIds) {
  if (log.length > 0) {
    let kcal = 0;
    let proteinG = 0;
    let carbsG = 0;
    let fatG = 0;
    let logged = 0;
    let estimated = false;
    for (const e of log) {
      kcal += e.kcal || 0;
      proteinG += e.proteinG || 0;
      carbsG += e.carbsG || 0;
      fatG += e.fatG || 0;
      if (e.estimated) estimated = true;
      if (e.origin === "logged") logged++;
    }
    return {
      kcal,
      proteinG: round1(proteinG),
      carbsG: round1(carbsG),
      fatG: round1(fatG),
      basis: logged === 0 ? BASIS.TICKED_PLAN_MEALS : BASIS.LOGGED,
      estimated,
      entryCount: log.length,
      loggedCount: logged,
    };
  }

  const eaten = allMeals.filter(
      (m) => !isSupplement(m) && consumedMealIds.has(m.id));
  if (eaten.length === 0) {
    return {
      kcal: 0, proteinG: 0, carbsG: 0, fatG: 0,
      basis: BASIS.NOTHING_LOGGED, estimated: false,
      entryCount: 0, loggedCount: 0,
    };
  }

  const items = eaten.flatMap((m) => m.items || []);
  const sum = (field) => {
    let total = 0;
    let stated = false;
    for (const item of items) {
      const v = item && item[field];
      if (typeof v === "number" && Number.isFinite(v)) {
        total += v;
        stated = true;
      }
    }
    return stated ? total : 0;
  };
  return {
    kcal: eaten.map(mealCalories).filter((k) => k !== null)
        .reduce((a, b) => a + b, 0),
    proteinG: round1(sum("proteinG")),
    carbsG: round1(sum("carbsG")),
    fatG: round1(sum("fatG")),
    basis: BASIS.TICKED_PLAN_MEALS,
    estimated: items.some((i) => i && i.estimated === true),
    entryCount: 0,
    loggedCount: 0,
  };
}

/**
 * Target minus consumed, or null when no target was set for that macro.
 * @param {?number} target
 * @param {number} consumed
 * @return {?number}
 */
function left(target, consumed) {
  return target === null || target === undefined ?
    null : round1(target - consumed);
}

/**
 * Builds the structured picture of the user's diet for one day.
 * @param {!Object} args
 * @return {!Object} A `DietState`-shaped object.
 */
function buildDietState({
  dayKey,
  weekday,
  targets,
  planName,
  day,
  consumedMealIds,
  log,
  history,
  energy,
}) {
  const allMeals = (day && Array.isArray(day.meals)) ? day.meals : [];
  const ticked = consumedMealIds instanceof Set ?
    consumedMealIds : new Set(consumedMealIds || []);
  const entries = log || [];

  const meals = allMeals
      .map((meal) => ({
        id: meal.id,
        label: meal.label,
        eaten: ticked.has(meal.id),
        kcal: mealCalories(meal),
        estimated: mealEstimated(meal),
        isSupplement: isSupplement(meal),
      }))
      .sort((a, b) => String(a.id).localeCompare(String(b.id)));

  const consumed = consumedFrom(entries, allMeals, ticked);
  const remaining = !targets ? null : {
    kcal: targets.calories - consumed.kcal,
    proteinG: left(targets.proteinG, consumed.proteinG),
    carbsG: left(targets.carbsG, consumed.carbsG),
    fatG: left(targets.fatG, consumed.fatG),
  };

  const plannedStated = meals
      .filter((m) => !m.isSupplement && m.kcal !== null)
      .map((m) => m.kcal);

  return {
    dayKey,
    weekday,
    targets: targets || null,
    planName: planName || null,
    dayLabel: (day && day.label) || null,
    // Reported separately from `targets` and never conflated with it: a plan's
    // own sum is not a goal anyone chose.
    plannedKcal: plannedStated.length === 0 ?
      null : plannedStated.reduce((a, b) => a + b, 0),
    meals,
    mealsEaten: meals.filter((m) => !m.isSupplement && m.eaten).length,
    mealsTotal: meals.filter((m) => !m.isSupplement).length,
    consumed: {...consumed, basisLabel: BASIS_LABEL[consumed.basis]},
    remaining,
    history: history || {days: 0, daysWithLog: 0, averageKcal: null},
    // What this person burns, and how ZIVO knows. An INPUT, not something
    // derived here — assembling body data belongs to the caller on both
    // sides, so the client and the gateway are handed the same figure rather
    // than each deriving one. Null is a real state: no body data, no
    // maintenance, and every rule that needs it stays quiet.
    energy: energy || null,
    // The target measured against maintenance; null when either is unknown,
    // because "no target" and "no body data" are different absences.
    targetVersusMaintenance: (targets && energy) ?
      targets.calories - energy.maintenanceKcal : null,
    quality: {
      targetsUnset: !targets,
      noPlanForDay: !day,
      nothingLogged: consumed.basis === BASIS.NOTHING_LOGGED,
      consumedIsAssumed: consumed.basis === BASIS.TICKED_PLAN_MEALS,
      hasEstimatedValues: consumed.estimated,
      untrackedMacros: [
        ...(targets && targets.proteinG !== null &&
          targets.proteinG !== undefined ? [] : ["protein"]),
        ...(targets && targets.carbsG !== null &&
          targets.carbsG !== undefined ? [] : ["carbs"]),
        ...(targets && targets.fatG !== null &&
          targets.fatG !== undefined ? [] : ["fat"]),
      ],
    },
  };
}

/**
 * A compact read on the recent past, so the coach can say "third day under"
 * without being handed every entry of every day.
 *
 * The average covers only days that had something recorded: averaging zeros
 * for days nobody logged would invent a trend out of missing data.
 * @param {!Array<{dayKey: string, kcal: number}>} entries
 * @param {number} days How many days the window covers.
 * @return {!Object}
 */
function summariseHistory(entries, days) {
  const byDay = new Map();
  for (const e of entries) {
    byDay.set(e.dayKey, (byDay.get(e.dayKey) || 0) + (e.kcal || 0));
  }
  const totals = [...byDay.values()];
  return {
    days,
    daysWithLog: totals.length,
    averageKcal: totals.length === 0 ?
      null : Math.round(totals.reduce((a, b) => a + b, 0) / totals.length),
  };
}

module.exports = {
  buildDietState,
  summariseHistory,
  consumedFrom,
  isSupplement,
  mealCalories,
  BASIS,
  BASIS_LABEL,
};
