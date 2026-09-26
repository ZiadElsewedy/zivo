/**
 * The server-side read-only tool registry for the `aiChat` gateway
 * (`functions/ai/gateway.js`). Every tool is `uid`-scoped and reads through
 * the injected `store` seam (`functions/ai/shared/store.js` in production, a
 * plain in-memory fake in tests) — nothing here touches Firestore or any SDK
 * directly, so it runs offline under `node --test`.
 *
 * Strictly READ-ONLY: no tool writes, creates, or deletes anything.
 *
 * Two rules this registry holds to, both about trust rather than mechanics:
 *
 * 1. **Every payload states its own date.** Nothing else in a turn tells the
 *    model what day it is. A tool that resolves "today" says which day that
 *    was, in the user's timezone (`offsetMinutes`, forwarded from the client
 *    by `aiChat` — see `../shared/dates.js`).
 * 2. **Nutrition carries its provenance.** A calorie/macro figure that was
 *    AI-estimated at PDF import time (`FoodItem.estimated`) travels with that
 *    flag, per item and aggregated onto the day totals, so the coach can say
 *    "about" where the number is a guess instead of quoting it as measured.
 * 3. **The coach is handed decisions, not just data.** Alongside the state
 *    comes `findings` — what the deterministic rules engine
 *    (`functions/diet/rules.js`) concluded, each typed, ranked, and carrying
 *    the state fields it rests on. The model phrases them; it does not decide
 *    them.
 * 4. **One state, both surfaces.** The diet payload IS the `DietState` the
 *    Diet screen renders, built by the same rules (`functions/diet/state.js`,
 *    mirrored from Dart and pinned by shared golden vectors). Two surfaces
 *    deriving "how am I doing" independently is how they end up disagreeing,
 *    and a coach that contradicts the screen is worse than no coach.
 * 5. **Consumption is the LOG, not the plan.** What the user recorded eating
 *    (`foodLogs`) is what `consumed`/`remaining` are computed from. Each entry
 *    says whether a person logged it or the app materialised it from a ticked
 *    meal, and the payload says which kind the day is made of — "you ate 1,850"
 *    and "the plan values what you ticked at 1,850" are different claims.
 * 6. **"Target" is never implied.** The user's own objective
 *    (`dietTargets/current`) is reported as `targets`, and `null` when they
 *    haven't set one; a plan day's own sum is reported separately as
 *    `nutrition.target` and never passed off as a goal anyone chose. Where
 *    real targets exist, the remaining budget is computed here so the coach
 *    doesn't have to derive it.
 */

const {
  dayKeyFor,
  dayRangeMs,
  weekRangeMs,
  monthRangeMs,
  isoWeekday,
  localHourAt,
  resolveDietDay,
  startOfDay,
} = require("../shared/dates");
const {readinessFromSignals} = require("../analytics/readiness");
const {
  buildDietState, summariseHistory, BASIS_LABEL,
} = require("../../diet/state");
const {buildDietDayRecord} = require("../../diet/day_record");
const {calibrateMaintenance, energyFor, ageFrom} = require("../../diet/energy");
const {coachingFindings} = require("../../diet/rules");
const {analyzeTraining} = require("../analytics/workout_analytics");
const {
  trainingCalendar,
  qualifiesAsTrainingDay,
  addDays,
} = require("../analytics/training_calendar");
const {analyzeExercise, analyzePlanAdherence} = require("../analytics/exercise_analytics");
const {makeResolver, IDENTITY} = require("../analytics/exercise_identity");
const {
  rotationFrom,
  upNextDay,
  dayAfter,
  dayName,
} = require("./workout_rotation");
const {
  resolveComposite,
  resolveAndCompute,
  normalizeItem,
  summariseFood,
} = require("../../nutrition/resolve");
const {
  priceReplacementCandidates,
  classifyMacroRole,
} = require("../../nutrition/meal_replacement");

/**
 * ISO string for `date`, or null.
 * @param {?Date} date
 * @return {?string}
 */
function iso(date) {
  return date ? date.toISOString() : null;
}

/**
 * Recursively removes keys whose value is `null` or `undefined` from a plain
 * object/array tree, so a tool result carries only the fields it actually has.
 *
 * TOKEN DISCIPLINE (context-engineering pass): a tool result is re-sent, at
 * full (uncached) price, on every subsequent model call in the same turn. An
 * absent
 * key costs nothing; a `"weightKg": null` on every bodyweight set, or a
 * `"muscleGroup": null` on every exercise, costs the same tokens as a real
 * value — repeatedly. Stripping them is a pure size win.
 *
 * SCOPE — do NOT apply this to the diet tools. There, `null` is a SEMANTIC
 * signal the prompt reasons about ("targets is null → the user set no
 * objective", a macro null in `remaining` → untracked, not zero), and the
 * gateway/tools tests assert those nulls explicitly. This helper is only for
 * tools where a missing figure genuinely means "absent" (workouts, expenses,
 * the week digest): there, absence and null carry the same meaning, so dropping
 * the key changes nothing the model can read.
 * @template T
 * @param {T} value
 * @return {T}
 */
function dropNull(value) {
  if (Array.isArray(value)) return value.map(dropNull);
  if (value && typeof value === "object" && !(value instanceof Date)) {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      if (v === null || v === undefined) continue;
      out[k] = dropNull(v);
    }
    return out;
  }
  return value;
}

/**
 * Sums a meal-plan item's numeric field, skipping items where the value is
 * absent (the diet importer legitimately leaves calories/macros null).
 * @param {!Array<Object>} items
 * @param {string} field
 * @return {?number} The total, or null when NO item states the field.
 */
function sumItemField(items, field) {
  let total = 0;
  let stated = false;
  for (const item of items) {
    const value = item && item[field];
    if (typeof value === "number" && Number.isFinite(value)) {
      total += value;
      stated = true;
    }
  }
  return stated ? total : null;
}

/**
 * Whether any of `items` carries AI-estimated nutrition — the aggregate form
 * of `FoodItem.estimated`. A total built from even one estimated item is
 * itself an estimate, and must not be quoted as a measured value.
 * @param {!Array<Object>} items
 * @return {boolean}
 */
function anyEstimated(items) {
  return items.some((item) => item && item.estimated === true);
}

/**
 * Aggregates a set of planned meals into day-level nutrition totals — the
 * target side when fed every meal, the consumed side when fed only the eaten
 * ones. Each component is null when no contributing item states it.
 * @param {!Array<Object>} meals Planned meals (label/items shape).
 * @return {!Object} `{kcal, proteinG, carbsG, fatG, estimated}`.
 */
function dayNutrition(meals) {
  const items = meals.flatMap(
      (m) => (m && Array.isArray(m.items) ? m.items : []));
  return {
    kcal: sumItemField(items, "calories"),
    proteinG: sumItemField(items, "proteinG"),
    carbsG: sumItemField(items, "carbsG"),
    fatG: sumItemField(items, "fatG"),
    // True when at least one contributing item's figures were AI-estimated
    // rather than stated by the user's own plan document.
    estimated: anyEstimated(items),
  };
}

/**
 * The user's objective as the model should see it — or null when unset.
 * `source` travels with it for the same reason `estimated` travels with a
 * calorie: a figure the user typed and one a formula proposed are different
 * kinds of fact.
 * @param {?Object} targets A `store.getDietTargets` result.
 * @return {?Object}
 */
function targetsPayload(targets) {
  if (!targets) return null;
  return {
    goal: targets.goal,
    calories: targets.calories,
    proteinG: targets.proteinG,
    carbsG: targets.carbsG,
    fatG: targets.fatG,
    source: targets.source,
  };
}

/**
 * One plan item as the model reads it. `index` is its position within the
 * meal — a FoodItem has no id of its own, so this is what
 * search_food_alternatives / replace_meal_item address it by (both re-check
 * the name at that index before writing). `estimated` appears only when true:
 * provenance, not decoration — the figures came from an AI estimate at import.
 * @param {!Object} it A plan FoodItem.
 * @param {number} index
 * @return {!Object}
 */
function planItemForModel(it, index) {
  const out = {
    index,
    name: it.name,
    quantity: it.quantity,
    unit: it.unit,
    calories: it.calories,
    proteinG: it.proteinG,
    carbsG: it.carbsG,
    fatG: it.fatG,
  };
  if (it.estimated === true) out.estimated = true;
  return out;
}

/**
 * The day's meals and foods WITHOUT saying anything twice (Phase 6).
 *
 * Ticking a meal materialises one `plannedMeal` log entry per item, id
 * `${dayKey}__${mealId}-${index}` (`planned_meal_log.dart`), with the plan's
 * exact name and quantity — so for a ticked meal the log restated the plan's
 * items word for word (2.4K of a 7K payload on a real day, pushing `get_diet`
 * past the tool-result cap and truncating the last meal's items). Here each
 * such entry is folded back into its meal:
 *   - a ticked meal whose entries match every item: `eaten: true`, nothing
 *     more — the items ARE what was eaten;
 *   - one with only some left (a half-eaten meal): `eatenItems` lists the
 *     indices still logged;
 *   - anything the plan doesn't explain — food the user logged, or a planned
 *     entry that no longer matches the plan (edited since) — stays in
 *     `logEntries`, exactly as before.
 * `itemsFor` picks which meals carry their items: "all" (get_diet — the plan
 * is the subject) or "eaten" (get_today — what was consumed).
 * @param {!Array<!Object>} stateMeals `state.meals`.
 * @param {?Object} dietDay The resolved plan day.
 * @param {!Array<!Object>} log The day's raw entries.
 * @param {string} dayKey
 * @param {string} itemsFor "all" | "eaten"
 * @return {{meals: !Array<!Object>, logEntries: !Array<!Object>}}
 */
function mealsAndFoodsForModel(stateMeals, dietDay, log, dayKey, itemsFor) {
  const planMeals = new Map(
      ((dietDay && dietDay.meals) || []).map((m) => [m.id, m]));
  const explained = new Map(); // mealId → Set of item indices
  const unexplained = [];
  for (const e of log) {
    const meal = e.origin === "plannedMeal" && e.mealId ?
      planMeals.get(e.mealId) : null;
    const prefix = `${dayKey}__${e.mealId}-`;
    const id = String(e.id || "");
    const index = meal && id.startsWith(prefix) &&
      /^\d+$/.test(id.slice(prefix.length)) ?
      Number(id.slice(prefix.length)) : -1;
    const item = index >= 0 ? (meal.items || [])[index] : null;
    const stateMeal = meal ? stateMeals.find((s) => s.id === meal.id) : null;
    if (item && stateMeal && stateMeal.eaten &&
        e.foodName === item.name &&
        Math.abs((e.quantity || 0) - (item.quantity || 0)) < 1e-6) {
      if (!explained.has(meal.id)) explained.set(meal.id, new Set());
      explained.get(meal.id).add(index);
    } else {
      unexplained.push(e);
    }
  }
  // In the plan's own order (Breakfast … Dinner), as `planItems` was —
  // `state.meals` is id-sorted for the shared vectors, which puts m10 before
  // m2.
  const byId = new Map(stateMeals.map((s) => [s.id, s]));
  const ordered = [
    ...[...planMeals.keys()].filter((id) => byId.has(id))
        .map((id) => byId.get(id)),
    ...stateMeals.filter((s) => !planMeals.has(s.id)),
  ];
  const meals = ordered.map((s) => {
    const out = {id: s.id, label: s.label, eaten: s.eaten, kcal: s.kcal};
    if (s.estimated) out.estimated = true;
    if (s.isSupplement) out.isSupplement = true;
    const plan = planMeals.get(s.id);
    const items = (plan && plan.items) || [];
    const kept = explained.get(s.id);
    // A ticked meal with no materialised entries predates the food log (or
    // the log was never written): its planned items stand, as before.
    if (s.eaten && kept && kept.size < items.length) {
      out.eatenItems = [...kept].sort((a, b) => a - b);
    }
    if (itemsFor === "all" || s.eaten) {
      out.items = items.map(planItemForModel);
    }
    return out;
  });
  return {
    meals,
    logEntries: unexplained.map((e) => ({
      food: e.foodName,
      quantity: e.quantity,
      unit: e.unit,
      kcal: e.kcal,
      proteinG: e.proteinG,
      carbsG: e.carbsG,
      fatG: e.fatG,
      // `source` (usdaFdc/userCustom/dietPlan) stays on the stored entry for
      // provenance; the coach doesn't need it and must never make the user
      // think about where a figure came from — `estimated` says what matters.
      origin: e.origin,
      estimated: e.estimated,
    })),
  };
}

/**
 * Projects a `DietState` into the shape the model reads. Field order matters:
 * tool results are truncated from the END, so what the coach must never lose —
 * the date, the objective, where the user stands — is serialized first.
 * @param {!Object} state
 * @param {!Array<Object>} log The day's raw entries.
 * @param {?number} localHour The user's own hour of day, when known.
 * @param {?Object=} dietDay The resolved plan day, for the meals' items.
 * @param {string=} itemsFor "all" | "eaten" — see `mealsAndFoodsForModel`.
 * @return {!Object}
 */
function stateForModel(state, log, localHour, dietDay, itemsFor = "eaten") {
  const {meals, logEntries} = mealsAndFoodsForModel(
      state.meals, dietDay || null, log, state.dayKey, itemsFor);
  return {
    date: state.dayKey,
    targets: state.targets,
    consumed: state.consumed,
    remaining: state.remaining,
    // What the rules engine concluded — typed, ranked and evidenced. These are
    // decisions, already made; the model's job is to phrase them, not to
    // second-guess them or to invent others.
    findings: coachingFindings(state, localHour),
    // What the app knows it doesn't know — handed over rather than left for
    // the model to infer.
    quality: state.quality,
    // What this person burns, and how ZIVO knows — null when it doesn't.
    // Carried with its source for the same reason `consumed.basis` is: a
    // coach that can't say how it knows shouldn't be saying it.
    energy: state.energy,
    targetVersusMaintenance: state.targetVersusMaintenance,
    plan: state.planName,
    day: state.dayLabel,
    // The plan's own daily sum, reported separately from `targets` and never
    // to be described as a goal the user chose.
    plannedKcal: state.plannedKcal,
    mealsEaten: state.mealsEaten,
    mealsTotal: state.mealsTotal,
    history: state.history,
    // The foods the ticked meals don't already account for — what the user
    // logged themselves, so the coach can talk about what was eaten rather
    // than only about totals.
    logEntries,
    // Last: the block that can most afford to be truncated.
    meals,
  };
}

/**
 * Loads the active plan's resolved day for `date` plus that day's eaten-meal
 * ids — the shared read behind `get_diet` and `get_today`'s diet block.
 * @param {!Object} store
 * @param {string} uid
 * @param {!Date} date
 * @param {number=} offsetMinutes
 * @return {!Promise<?{plan: !Object, dietDay: !Object, eaten: !Set<string>}>}
 */
async function loadDietDay(store, uid, date, offsetMinutes) {
  const key = dayKeyFor(date, offsetMinutes);
  const [plan, log] = await Promise.all([
    store.getActiveDietPlan(uid),
    store.listFoodLogs(uid, key),
  ]);
  if (!plan) return {plan: null, dietDay: null, eaten: new Set(), log};
  const dietDay = resolveDietDay(plan.days, date, offsetMinutes);
  if (!dietDay) return {plan, dietDay: null, eaten: new Set(), log};
  const entries = await store.listDietEntries(uid, key);
  return {
    plan,
    dietDay,
    eaten: new Set(entries.filter((e) => e.eaten).map((e) => e.mealId)),
    log,
  };
}

const TODAY_TOOL = {
  name: "get_today",
  description:
    "A composed snapshot of 'today' in the user's own timezone: the date, " +
    "the user's diet targets and what's left of them, today's diet plan " +
    "(which meals are eaten, plan-vs-consumed nutrition totals, and whether " +
    "those figures are estimated), and today's workout(s). `targets` is null " +
    "when the user hasn't set an objective — say so rather than treating the " +
    "plan's own total as a goal.",
  inputSchema: {type: "object", properties: {}},
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @param {number=} offsetMinutes
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now, offsetMinutes) {
    const {fromMs, toMs} = dayRangeMs(now, offsetMinutes);
    const dayKey = dayKeyFor(now, offsetMinutes);
    // A week's history in one range query — `dayKey` is a sortable string, so
    // no composite index and no seven round-trips.
    const weekAgo = new Date(now.getTime() - 6 * 24 * 60 * 60 * 1000);
    // Eight weeks for the maintenance calibration — the same window the app
    // uses (`kCalibrationWindowDays`), so the coach measures over exactly the
    // period the Diet screen does.
    const calibrationStart =
      new Date(now.getTime() - CALIBRATION_WINDOW_DAYS * 24 * 60 * 60 * 1000);
    const [
      workouts, dietDay, targets, historyRows,
      bodyProfile, weighIns, dobMs, calibrationRows,
    ] = await Promise.all([
      store.listWorkouts(uid, {fromMs, toMs}),
      loadDietDay(store, uid, now, offsetMinutes),
      store.getDietTargets(uid),
      store.listFoodLogRange(
          uid, dayKeyFor(weekAgo, offsetMinutes), dayKey),
      store.getBodyProfile ? store.getBodyProfile(uid) : null,
      store.listBodyWeights ? store.listBodyWeights(uid) : [],
      store.getDateOfBirthMs ? store.getDateOfBirthMs(uid) : null,
      store.listFoodLogRange ?
        store.listFoodLogRange(
            uid, dayKeyFor(calibrationStart, offsetMinutes), dayKey) : [],
    ]);

    // What this person burns, measured from their own data where possible and
    // estimated only as a last resort. Assembled HERE and handed to the
    // builder, mirroring the app: `buildDietState` derives nothing about
    // bodies, so the coach and the screen are given the same figure rather
    // than each computing one (`functions/diet/energy.js`).
    const calibration = calibrateMaintenance({
      weighIns: weighIns || [],
      intake: dailyTotals(calibrationRows || []),
    });
    const energy = energyFor({
      profile: bodyProfile,
      weightKg: (weighIns || []).length > 0 ?
        weighIns[weighIns.length - 1].weightKg : null,
      age: dobMs === null || dobMs === undefined ?
        null : ageFrom(dobMs, now.getTime()),
      measuredMaintenanceKcal: calibration.measured ?
        calibration.measured.maintenanceKcal : null,
    });

    const {plan, dietDay: day, eaten, log} = dietDay;
    const state = buildDietState({
      dayKey,
      weekday: isoWeekday(now, offsetMinutes),
      targets: targetsPayload(targets),
      planName: plan ? plan.name : null,
      day,
      consumedMealIds: eaten,
      log,
      history: summariseHistory(historyRows, 7),
      energy,
    });

    // The diet block leads the payload deliberately. Tool results are capped
    // at `maxToolResultChars` and truncated from the END, so whatever is
    // serialized last is what disappears — the user's objective and where they
    // stand must never be silently half-delivered.
    return {
      ...stateForModel(state, log, localHourAt(now, offsetMinutes), day),
      workouts: workouts.map((w) => ({
        title: w.title,
        performedAt: iso(w.performedAt),
        durationMinutes: w.durationMinutes,
      })),
    };
  },
};

const EXPENSES_TOOL = {
  name: "get_expenses",
  description:
    "List expenses and totals by category. range: 'week' (default) or " +
    "'month'. category: optional exact-match filter. Each item includes its " +
    "stable `id` — pass that exact id to edit_expense/delete_expense; never " +
    "guess an id.",
  inputSchema: {
    type: "object",
    properties: {
      range: {type: "string", enum: ["week", "month"]},
      category: {type: "string"},
    },
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @param {number=} offsetMinutes
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now, offsetMinutes) {
    const range = input.range === "month" ?
      monthRangeMs(now, offsetMinutes) : weekRangeMs(now, offsetMinutes);
    const all = await store.listExpenses(uid, range);
    const items = input.category ?
      all.filter((e) => e.category === input.category) :
      all;

    const totalByCategory = {};
    let totalMinor = 0;
    let currency = null;
    for (const e of items) {
      totalByCategory[e.category] =
        (totalByCategory[e.category] || 0) + e.amountMinor;
      totalMinor += e.amountMinor;
      currency = currency || e.currency;
    }

    return dropNull({
      range: input.range === "month" ? "month" : "week",
      today: dayKeyFor(now, offsetMinutes),
      currency,
      totalMinor,
      totalByCategory,
      items: items.map((e) => ({
        // The stable doc id — the handle edit_expense/delete_expense need to
        // target this exact entry. Without it the model can describe an
        // expense but not point at one.
        id: e.id,
        amountMinor: e.amountMinor,
        currency: e.currency,
        category: e.category,
        // Dropped by `dropNull` when the expense has no note, rather than
        // serializing `"note": null` on every noteless row.
        note: e.note || null,
        spentAt: iso(e.spentAt),
      })),
    });
  },
};

/**
 * A session's actual duration in minutes (active time, pauses excluded), or
 * null when it is not a number the app stands behind.
 *
 * Mirrors `LiveSession.elapsed` + `hasUsableDuration` on the Dart side, and
 * must keep mirroring them: a coach that quotes a nineteen-hour workout the
 * app itself is holding out of its averages is worse than one that says
 * nothing about duration. A user correction wins; a duration marked `unknown`,
 * or longer than any plausible session, is withheld rather than reported.
 * @param {!Object} s
 * @return {?number}
 */
function sessionDurationMinutes(s) {
  if (typeof s.correctedDurationMinutes === "number") {
    return s.correctedDurationMinutes;
  }
  if (s.durationSource === "unknown") return null;
  if (!s.completedAt || !s.startedAt) return null;
  const ms = s.completedAt.getTime() - s.startedAt.getTime() -
    (s.pausedAccumMs || 0);
  if (ms <= 0) return 0;
  const minutes = Math.round(ms / 60000);
  return minutes > MAX_PLAUSIBLE_SESSION_MINUTES ? null : minutes;
}

/**
 * The upper bound past which a session duration is not reported to the model.
 * Deliberately generous — the client's own threshold is a user setting this
 * layer cannot see, so this is a backstop against the absurd, not a
 * re-implementation of that rule.
 * @const {number}
 */
const MAX_PLAUSIBLE_SESSION_MINUTES = 12 * 60;

const WORKOUTS_TOOL = {
  name: "get_workouts",
  description:
    "List the user's workout SESSIONS with their REAL per-set actuals — every " +
    "set's weight, reps, type (working/warmup/dropset/failure) and outcome. " +
    "range: 'week' (default) or 'month'. Reason only from these real sets: a " +
    "'top set' is the heaviest WORKING set, and warm-ups are marked so you " +
    "don't treat them as working volume. Never collapse an exercise to one " +
    "rep/weight, and never invent a set that isn't listed. For strength " +
    "trends, PRs and whether a lift is progressing, prefer get_training_analysis.",
  inputSchema: {
    type: "object",
    properties: {range: {type: "string", enum: ["week", "month"]}},
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @param {number=} offsetMinutes
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now, offsetMinutes) {
    const range = input.range === "month" ?
      monthRangeMs(now, offsetMinutes) : weekRangeMs(now, offsetMinutes);
    const {sessions} = await loadResolvedSessions(store, uid, range);
    sessions.sort((a, b) =>
      (b.completedAt || b.startedAt) - (a.completedAt || a.startedAt));
    // The "warm-up isn't working volume / top set is the heaviest working set"
    // guidance the payload used to repeat as a prose `note` lives in the tool
    // description and the TRAINING prompt section — both cached — so it is not
    // re-sent uncached with every result here. `dropNull` then strips the
    // absent figures a workout legitimately has (a bodyweight set's null
    // `weightKg`, a null `muscleGroup`) rather than paying to serialize them.
    return dropNull({
      range: input.range === "month" ? "month" : "week",
      today: dayKeyFor(now, offsetMinutes),
      workouts: sessions.map((s) => ({
        day: s.dayLabel,
        status: s.status,
        performedAt: iso(s.completedAt || s.startedAt),
        durationMinutes: sessionDurationMinutes(s),
        exercises: (s.exercises || []).map((e) => ({
          name: e.name,
          muscleGroup: e.muscleGroup,
          // Real per-set actuals — done sets only (a skipped/pending set was
          // not performed), numbered in order so "set 3" means set 3.
          sets: (e.sets || [])
              .filter((set) => set.outcome === "completed")
              .map((set, i) => ({
                set: i + 1,
                weightKg: set.actualWeightKg,
                reps: set.actualReps,
                type: set.type,
              })),
        })),
      })),
    });
  },
};

/**
 * The heaviest working (non-warm-up) set of a projected set list, as a short
 * label ("100kg × 8", or "8 reps" for a bodyweight movement), or null when the
 * exercise has no working set. Computed here so the coach can lead with the top
 * set without re-deriving "heaviest" from the set list itself.
 * @param {!Array<{weightKg: ?number, reps: ?number, type: string}>} sets
 * @return {?string}
 */
function topWorkingSetLabel(sets) {
  let best = null;
  for (const s of sets) {
    if (s.type === "warmup") continue;
    if (best === null) {
      best = s;
      continue;
    }
    const bw = best.weightKg == null ? -1 : best.weightKg;
    const sw = s.weightKg == null ? -1 : s.weightKg;
    if (sw > bw || (sw === bw && (s.reps || 0) > (best.reps || 0))) best = s;
  }
  if (!best) return null;
  if (best.weightKg == null) return `${best.reps} reps`;
  return `${trimKg(best.weightKg)}kg × ${best.reps}`;
}

const LAST_WORKOUT_TOOL = {
  name: "get_last_workout",
  description:
    "The single most recent COMPLETED workout session — its real per-set " +
    "actuals (each set's weight, reps and type), the top working set of each " +
    "exercise, the session duration and how many days ago it was. Use this for " +
    "'what did I do last workout', 'how was my last session', 'what was my " +
    "last leg day'. It reads ONE session, not a date range — for a whole week " +
    "or month use get_workouts, and for one lift's trend over time use " +
    "get_exercise_analysis. Returns `found:false` when no completed session " +
    "exists yet.",
  inputSchema: {type: "object", properties: {}},
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @param {number=} offsetMinutes
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now, offsetMinutes) {
    const today = dayKeyFor(now, offsetMinutes);
    const {sessions} = await loadResolvedSessions(store, uid);
    const s = (sessions || [])
        .filter((x) => x.status === "completed")
        .sort((a, b) =>
          (b.completedAt || b.startedAt) - (a.completedAt || a.startedAt))[0];
    if (!s) return {date: today, found: false};

    const at = s.completedAt || s.startedAt;
    const dayMs = 24 * 60 * 60 * 1000;
    const daysAgo = at ? Math.round(
        (startOfDay(now, offsetMinutes).getTime() -
          startOfDay(at, offsetMinutes).getTime()) / dayMs) : null;

    return dropNull({
      date: today,
      found: true,
      workout: {
        day: s.dayLabel,
        performedAt: iso(at),
        daysAgo,
        durationMinutes: sessionDurationMinutes(s),
        exercises: (s.exercises || []).map((e) => {
          const sets = (e.sets || [])
              .filter((set) => set.outcome === "completed")
              .map((set, i) => ({
                set: i + 1,
                weightKg: set.actualWeightKg,
                reps: set.actualReps,
                type: set.type,
              }));
          return {
            name: e.name,
            muscleGroup: e.muscleGroup,
            // The deterministic top set, so the coach leads with the fact
            // rather than scanning the sets to find the heaviest itself.
            topSet: topWorkingSetLabel(sets),
            workingSets: sets.filter((set) => set.type !== "warmup").length,
            sets,
          };
        }),
      },
    });
  },
};

const CALENDAR_WINDOW_DAYS = 28;

/**
 * Calendar adherence (`analytics/training_calendar.js`) over the last
 * CALENDAR_WINDOW_DAYS on the user's local calendar — which days had a
 * qualifying session. Never touches, and never describes, the rotation.
 * @param {!Array<!Object>} sessions
 * @param {Date} now
 * @param {number=} offsetMinutes
 * @return {?Object} Null with no training history.
 */
function calendarFor(sessions, now, offsetMinutes) {
  const sessionsByDay = {};
  for (const s of sessions || []) {
    const at = s.completedAt || s.startedAt;
    if (!at || !qualifiesAsTrainingDay(s)) continue;
    const key = dayKeyFor(at, offsetMinutes);
    sessionsByDay[key] = (sessionsByDay[key] || 0) + 1;
  }
  const today = dayKeyFor(now, offsetMinutes);
  return trainingCalendar({
    sessionsByDay,
    from: addDays(today, -(CALENDAR_WINDOW_DAYS - 1)),
    today,
  });
}

const TRAINING_ANALYSIS_TOOL = {
  name: "get_training_analysis",
  description:
    "ZIVO's deterministic workout analysis over the user's whole session " +
    "history — the SAME numbers the Progress screen shows. Returns: " +
    "overallStatus + a plain summary; overallStrengthChangePercent " +
    "(estimated 1RM change over ~6 weeks); per-exercise status " +
    "(progressing/maintaining/plateauing/regressing/building) with " +
    "strengthChangePercent and currentE1RM; a per-muscle weekly rollup; " +
    "weekly working volume vs last week; recentPrs (last 30 days); " +
    "improving / needsAttention lists; a nextStep; ranked `findings` " +
    "(confidence 'fact' or 'interpretation'); `planAdherence` (planned " +
    "movements 'neverTrained' or 'stale' with daysSinceLast); and " +
    "`trainingCalendar` (last 4 weeks: active vs inactive days with the " +
    "inactive dates, training days per week, days since last training). " +
    "The WHOLE-training summary — for one lift's session-by-session " +
    "detail use get_exercise_analysis.",
  inputSchema: {type: "object", properties: {}},
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @param {number=} offsetMinutes
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now, offsetMinutes) {
    const {sessions, resolver} = await loadResolvedSessions(store, uid);
    // The active plan is what makes "what's being skipped" answerable; a store
    // without the reader (or with no plan) just yields empty adherence.
    const plan = store.getActiveWorkoutPlan ?
      await store.getActiveWorkoutPlan(uid) : null;
    const analysis = analyzeTraining({sessions, now});
    const adherence = analyzePlanAdherence({plan, sessions, now, resolver});
    const calendar = calendarFor(sessions, now, offsetMinutes);
    return {
      ...analysis,
      // ISO the PR dates for the model.
      recentPrs: analysis.recentPrs.map((p) => ({
        ...p,
        achievedAt: iso(p.achievedAt),
      })),
      exercises: analysis.exercises.map((e) => ({
        ...e,
        lastPerformedAt: iso(e.lastPerformedAt),
      })),
      planAdherence: adherence,
      ...(calendar ? {trainingCalendar: calendar} : {}),
    };
  },
};

const EXERCISE_ANALYSIS_TOOL = {
  name: "get_exercise_analysis",
  description:
    "ZIVO's deterministic drill-down for ONE exercise — the SAME " +
    "session-by-session analysis its Exercise Analysis screen shows. Pass " +
    "the exercise by name (e.g. 'incline dumbbell press'); it's matched " +
    "against the user's logged movements. Use it for any question about a " +
    "SPECIFIC lift ('how is my bench going', 'what should I do on squats " +
    "next'). Returns the full history oldest→newest (each session's sets, " +
    "reps, load, total volume, average load, rep range, estimated 1RM), " +
    "the session-to-session `comparisons` (load/reps/volume/estimated-1RM " +
    "deltas + typed `tags` + a `tone` of " +
    "improved/declined/mixed/maintained), all-time PRs, frequency, " +
    "daysSinceLast, the overall `status`/`verdict`, and a deterministic " +
    "`insight` (whatHappened / whyItMatters / whatToDo). If `matched` is " +
    "false, tell the user and offer the listed candidates.",
  inputSchema: {
    type: "object",
    properties: {
      exercise: {
        type: "string",
        description: "The exercise name to analyse (as the user refers to it).",
      },
    },
    required: ["exercise"],
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now) {
    const {sessions} = await loadResolvedSessions(store, uid);
    const resolved = resolveExerciseId(sessions, input.exercise);
    if (!resolved.exerciseId) {
      return {
        matched: false,
        query: input.exercise || "",
        candidates: resolved.candidates,
        note: resolved.candidates.length === 0 ?
          "No completed sessions logged yet, so there's no exercise history to analyse." :
          "No logged exercise matched that name. Offer the user one of the candidates.",
      };
    }
    const analysis = analyzeExercise({
      exerciseId: resolved.exerciseId, sessions, now,
    });
    if (!analysis) {
      return {
        matched: false,
        query: input.exercise || "",
        candidates: resolved.candidates,
        note: "That movement is in the plan/history but has no completed working sets to analyse yet.",
      };
    }
    return {matched: true, ...serializeExerciseAnalysis(analysis)};
  },
};

/**
 * The user's sessions read through their exercise identities (ADR-017): each
 * session's `exerciseId`s folded into the canonical exercise they mean, so one
 * movement trained on two days — or in two splits — is one history, exactly
 * as the Analysis screen reads it. In memory only; nothing is written back.
 *
 * A store without the alias reader (a test fake), or a failed read, resolves
 * every id to itself: the pre-identity reading, never an error.
 * @param {!Object} store
 * @param {string} uid
 * @param {{fromMs: number, toMs: number}=} range
 * @return {!Promise<{sessions: !Array<Object>, resolver: !Object}>}
 */
async function loadResolvedSessions(store, uid, range) {
  const [sessions, aliases] = await Promise.all([
    store.listWorkoutSessions(uid, range),
    store.listExerciseAliases ?
      store.listExerciseAliases(uid).catch(() => []) :
      Promise.resolve([]),
  ]);
  const resolver = aliases.length ? makeResolver(aliases) : IDENTITY;
  return {sessions: resolver.canonicalize(sessions), resolver};
}

/**
 * Resolves a free-text exercise name to a logged exerciseId. Prefers an exact
 * (case-insensitive) name, then a whole-word/substring match, and returns the
 * available names as candidates so the model can disambiguate or fall back.
 * @param {!Array<Object>} sessions
 * @param {?string} query
 * @return {{exerciseId: ?string, candidates: !Array<string>}}
 */
function resolveExerciseId(sessions, query) {
  const byId = new Map(); // exerciseId -> freshest name
  // Every name an exercise was ever logged under. Sessions arrive already
  // canonicalized, so "Hammer Curl" on one day and "Hammer Dumbbell Curl" on
  // another are one id — and asking about either name finds it.
  const namesById = new Map();
  const ordered = [...(sessions || [])].sort((a, b) =>
    (a.completedAt || a.startedAt) - (b.completedAt || b.startedAt));
  for (const s of ordered) {
    if (s.status !== "completed") continue;
    for (const e of s.exercises || []) {
      const hasWorking = (e.sets || []).some(
          (set) => set.outcome === "completed" && set.type !== "warmup");
      if (!hasWorking) continue;
      const name = e.name || e.exerciseId;
      byId.set(e.exerciseId, name);
      if (!namesById.has(e.exerciseId)) namesById.set(e.exerciseId, new Set());
      namesById.get(e.exerciseId).add(name.toLowerCase());
    }
  }
  const candidates = [...byId.values()];
  const q = String(query || "").trim().toLowerCase();
  if (!q) return {exerciseId: null, candidates};

  let exact = null;
  let starts = null;
  let contains = null;
  for (const [id, names] of namesById) {
    for (const n of names) {
      if (n === q) exact = exact || id;
      if (starts == null && n.startsWith(q)) starts = id;
      if (contains == null && (n.includes(q) || q.includes(n))) contains = id;
    }
    if (exact) break;
  }
  return {exerciseId: exact || starts || contains, candidates};
}

/**
 * Shapes an `analyzeExercise` result for the model — ISO dates, PRs as an
 * array, the deltas passed through unchanged (they are the deterministic facts
 * the coach must not restate differently).
 * @param {!Object} a
 * @return {!Object}
 */
function serializeExerciseAnalysis(a) {
  return {
    exercise: a.name,
    muscleGroup: a.muscleGroup,
    status: a.status,
    verdict: a.verdict,
    latestTone: a.latestTone,
    strengthChangePercent: a.strengthChangePercent,
    currentE1RM: a.currentE1RM,
    bestE1RM: a.bestE1RM,
    totalSessions: a.totalSessions,
    totalWorkingSets: a.totalWorkingSets,
    totalVolumeKg: a.totalVolumeKg,
    daysSinceLast: a.daysSinceLast,
    sessionsPerWeek: a.sessionsPerWeek,
    isWeighted: a.isWeighted,
    insight: a.insight,
    personalRecords: Object.entries(a.records).map(([kind, r]) => ({
      kind,
      weightKg: r.weightKg,
      reps: r.reps,
      estimatedOneRepMax: r.estimatedOneRepMax,
      achievedAt: iso(r.achievedAt),
    })),
    // Newest first, each with its own session-to-session comparison inlined.
    sessions: [...a.sessions].reverse().map((s) => ({
      performedAt: iso(s.date),
      day: s.dayLabel,
      isPersonalBest: s.isPrSession,
      workingSets: s.workingSetCount,
      topSet: s.topWeightKg == null ?
        `${s.topReps} reps` : `${trimKg(s.topWeightKg)}kg × ${s.topReps}`,
      totalVolumeKg: round1(s.totalVolumeKg),
      avgLoadKg: s.avgLoadKg == null ? null : round1(s.avgLoadKg),
      repRange: s.repRange,
      estimatedOneRepMax: s.bestE1RM == null ? null : round1(s.bestE1RM),
      sets: s.sets.map((set) => ({
        weightKg: set.weightKg,
        reps: set.reps,
        type: set.type,
      })),
      vsPreviousSession: comparisonFor(a, s.sessionId),
    })),
  };
}

/**
 * The comparison whose current session is `sessionId`, shaped for the model, or
 * null for the oldest (baseline) session.
 * @param {!Object} a
 * @param {string} sessionId
 * @return {?Object}
 */
function comparisonFor(a, sessionId) {
  const c = a.comparisons.find((x) => x.currentSessionId === sessionId);
  if (!c) return null;
  return {
    tone: c.tone,
    changes: c.tags,
    loadChangeKg: c.loadChangeKg == null ? null : round1(c.loadChangeKg),
    topRepsChange: c.topRepsChange,
    volumeChangeKg: round1(c.volumeChangeKg),
    volumeChangePercent:
      c.volumeChangePercent == null ? null : round1(c.volumeChangePercent),
    estimatedOneRepMaxChangeKg:
      c.e1rmChangeKg == null ? null : round1(c.e1rmChangeKg),
    estimatedOneRepMaxChangePercent:
      c.e1rmChangePercent == null ? null : round1(c.e1rmChangePercent),
  };
}

const trimKg = (v) => Number.isInteger(v) ? String(v) : v.toFixed(1);
const round1 = (v) => Math.round(v * 10) / 10;

/** Mirrors the app's `kCalibrationWindowDays`. */
const CALIBRATION_WINDOW_DAYS = 56;

/**
 * Per-day kcal totals from raw log rows. Days with nothing logged are ABSENT,
 * never zero — a zero would drag the intake average down and manufacture a
 * deficit that never happened.
 * @param {!Array<{dayKey: string, kcal: number}>} rows
 * @return {!Array<{dayKey: string, kcal: number}>}
 */
function dailyTotals(rows) {
  const byDay = new Map();
  for (const row of rows) {
    if (!row || !row.dayKey) continue;
    byDay.set(row.dayKey, (byDay.get(row.dayKey) || 0) + (row.kcal || 0));
  }
  return [...byDay.entries()]
      .map(([dayKey, kcal]) => ({dayKey, kcal}))
      .sort((a, b) => a.dayKey.localeCompare(b.dayKey));
}

/**
 * A food-log row as the model reads it.
 * @param {!Object} e
 * @return {!Object}
 */
function logEntryForModel(e) {
  return {
    food: e.foodName, quantity: e.quantity, unit: e.unit, kcal: e.kcal,
    proteinG: e.proteinG, carbsG: e.carbsG, fatG: e.fatG, origin: e.origin,
    estimated: e.estimated,
  };
}

/**
 * Consumed minus target per figure, or null where no target was set.
 * @param {!Object} consumed
 * @param {?Object} targets
 * @return {?Object}
 */
function versusTarget(consumed, targets) {
  if (!targets) return null;
  const d = (t, c) => (typeof t === "number" ? round1(c - t) : null);
  return {
    kcal: d(targets.calories, consumed.kcal),
    proteinG: d(targets.proteinG, consumed.proteinG),
    carbsG: d(targets.carbsG, consumed.carbsG),
    fatG: d(targets.fatG, consumed.fatG),
  };
}

/**
 * A PAST day as the model reads it: the day's own record (`dietDays` — what
 * was planned THAT day, frozen, and what happened) plus the foods behind it.
 * Not today's live state: there is no "remaining" and no time-of-day advice
 * for a day that is over.
 * @param {!Object} record A `buildDietDayRecord` result.
 * @param {!Array<!Object>} log That day's food-log rows.
 * @return {!Object}
 */
function pastDayForModel(record, log) {
  const eatenIds = new Set(record.meals
      .filter((m) => m.status === "eaten" || m.status === "modified")
      .map((m) => m.mealId));
  const out = {
    date: record.dayKey,
    kind: "pastDay",
    targets: record.targets,
    consumed: Object.assign({}, record.consumed,
        {basisLabel: BASIS_LABEL[record.consumed.basis]}),
    versusTarget: versusTarget(record.consumed, record.targets),
    plan: record.plan ? record.plan.name : null,
    planned: record.planned,
    adherence: record.adherence,
    meals: record.meals.map((m) => {
      const row = {id: m.mealId, label: m.label, status: m.status};
      if (m.isSupplement) row.isSupplement = true;
      if (m.planned) {
        row.plannedKcal = m.planned.kcal;
        row.plannedProteinG = m.planned.proteinG;
      }
      if (m.actual) row.actual = m.actual;
      // What was eaten from it, by name — the rows are the plan's items.
      const foods = log.filter((e) => e.origin === "plannedMeal" &&
        e.mealId === m.mealId && eatenIds.has(m.mealId));
      if (foods.length) {
        row.foods = foods.map((e) => `${e.foodName} ${e.quantity}${e.unit}`);
      }
      return row;
    }),
    // Everything eaten outside the day's ticked meals, in full.
    logEntries: log
        .filter((e) => e.origin !== "plannedMeal" || !eatenIds.has(e.mealId))
        .map(logEntryForModel),
  };
  // Said only when true: the day was first recorded after it ended, so its
  // plan side is today's plan applied to it, not what was in force then.
  if (record.plannedReconstructed) out.planReconstructed = true;
  return out;
}

/**
 * The stored record for a past day, or one built now from its sources when
 * none is stored yet (a day from before the record existed) — marked
 * reconstructed by the builder. Null when nothing was recorded that day.
 * @param {!Object} store
 * @param {string} uid
 * @param {string} dayKey
 * @param {!Array<!Object>} log
 * @return {!Promise<?Object>}
 */
async function pastDayRecord(store, uid, dayKey, log) {
  const stored = store.getDietDay ? await store.getDietDay(uid, dayKey) : null;
  if (stored) return stored;
  const [plan, entries, targets] = await Promise.all([
    store.getActiveDietPlan(uid),
    store.listDietEntries(uid, dayKey),
    store.getDietTargets(uid),
  ]);
  return buildDietDayRecord({
    dayKey, isPast: true, offsetMinutes: null, plan,
    planDay: plan ?
      resolveDietDay(plan.days || [], new Date(`${dayKey}T12:00:00Z`), 0) :
      null,
    targets, entries, log, existing: null,
  });
}

const DIET_TOOL = {
  name: "get_diet",
  description:
    "The active diet plan's meals for a day (default today, in the user's " +
    "own timezone), with calories/macros, which meals are already eaten, " +
    "plan-vs-consumed nutrition totals, the user's own daily `targets` and " +
    "what's `remaining` of them. Every figure carries an `estimated` flag: " +
    "true means it was AI-estimated when the plan was imported, not stated " +
    "by the plan itself. `targets` is null when the user hasn't set an " +
    "objective. day: optional 'yyyy-MM-dd'; a past day returns that day's " +
    "own record (plan as it was then, meal statuses, consumed vs target).",
  inputSchema: {
    type: "object",
    properties: {day: {type: "string"}},
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @param {number=} offsetMinutes
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now, offsetMinutes) {
    // An explicit `day` is a bare calendar date with no timezone of its own;
    // anchor it at the user's local midnight so it resolves to that same
    // calendar day rather than sliding into a neighbouring one.
    const requested = typeof input.day === "string" ?
      /^\d{4}-\d{2}-\d{2}$/.exec(input.day.trim()) : null;
    const date = requested ?
      new Date(`${requested[0]}T12:00:00Z`) : now;
    const dateOffset = requested ? 0 : offsetMinutes;

    // A day that is over is read from its own record — what was planned
    // THEN, not the plan as it is now.
    if (requested && requested[0] < dayKeyFor(now, offsetMinutes)) {
      const log = await store.listFoodLogs(uid, requested[0]);
      const record = await pastDayRecord(store, uid, requested[0], log);
      return record ? pastDayForModel(record, log) :
        {date: requested[0], kind: "pastDay", nothingRecorded: true};
    }

    const [{plan, dietDay, eaten, log}, targets] = await Promise.all([
      loadDietDay(store, uid, date, dateOffset),
      store.getDietTargets(uid),
    ]);
    const state = buildDietState({
      dayKey: dayKeyFor(date, dateOffset),
      weekday: isoWeekday(date, dateOffset),
      targets: targetsPayload(targets),
      planName: plan ? plan.name : null,
      day: dietDay,
      consumedMealIds: eaten,
      log,
    });

    return {
      // An explicit `day` is a past/future date, so "what hour is it" doesn't
      // apply to it — time-sensitive rules correctly stay quiet.
      ...stateForModel(
          state, log, requested ? null : localHourAt(now, offsetMinutes),
          dietDay, "all"),
    };
  },
};

/** Longest window get_diet_history reads, and when rows become weeks. */
const HISTORY_MAX_DAYS = 90;
const HISTORY_DAILY_ROWS_MAX = 14;
/** A day within ±10% of its calorie target counts as on target. */
const ON_TARGET_BAND = 0.1;

/**
 * One recorded day as a compact history row.
 * @param {!Object} r A stored `dietDays` record.
 * @param {string} todayKey
 * @return {!Object}
 */
function historyRow(r, todayKey) {
  const row = {
    date: r.dayKey,
    kcal: r.consumed.kcal,
    proteinG: r.consumed.proteinG,
    carbsG: r.consumed.carbsG,
    fatG: r.consumed.fatG,
    basis: r.consumed.basis,
    meals: `${r.adherence.eaten + r.adherence.modified}/` +
      `${r.adherence.mealsPlanned}`,
  };
  const vs = versusTarget(r.consumed, r.targets);
  if (vs) row.vsTargetKcal = vs.kcal;
  if (r.adherence.skipped) row.skipped = r.adherence.skipped;
  if (r.adherence.modified) row.modified = r.adherence.modified;
  if (r.unplanned && r.unplanned.count) row.offPlanKcal = r.unplanned.kcal;
  if (r.consumed.estimated) row.estimated = true;
  if (r.dayKey === todayKey) row.inProgress = true;
  return row;
}

/**
 * The window's summary: averages over RECORDED days only (a day with nothing
 * recorded is absent, never zero), days on/over/under target, and which meals
 * went uneaten most — the pattern a coach acts on.
 * @param {!Array<!Object>} records Stored records, oldest first.
 * @param {string} todayKey
 * @return {!Object}
 */
function historySummary(records, todayKey) {
  // Today is still happening: shown, but not averaged or judged.
  const done = records.filter((r) =>
    r.dayKey !== todayKey && r.consumed.basis !== "nothingLogged");
  const avg = (f) => done.length === 0 ? null :
    round1(done.reduce((n, r) => n + (r.consumed[f] || 0), 0) / done.length);
  const target = [...records].reverse().find((r) => r.targets);
  const t = target ? target.targets : null;
  let on = 0;
  let over = 0;
  let under = 0;
  let proteinHit = 0;
  for (const r of done) {
    if (!r.targets) continue;
    const band = r.targets.calories * ON_TARGET_BAND;
    const delta = r.consumed.kcal - r.targets.calories;
    if (Math.abs(delta) <= band) on++;
    else if (delta > 0) over++;
    else under++;
    if (typeof r.targets.proteinG === "number" &&
        r.consumed.proteinG >= r.targets.proteinG * 0.9) {
      proteinHit++;
    }
  }
  const missed = new Map();
  const adherence = {mealsPlanned: 0, eaten: 0, modified: 0, skipped: 0,
    unmarked: 0};
  for (const r of records.filter((x) => x.dayKey !== todayKey)) {
    for (const k of Object.keys(adherence)) adherence[k] += r.adherence[k];
    for (const m of r.meals) {
      if (m.isSupplement || !m.planned) continue;
      if (m.status === "skipped" || m.status === "unmarked") {
        const key = `${m.label}|${m.status}`;
        missed.set(key, (missed.get(key) || 0) + 1);
      }
    }
  }
  return {
    daysCounted: done.length,
    avgKcal: avg("kcal"),
    avgProteinG: avg("proteinG"),
    avgCarbsG: avg("carbsG"),
    avgFatG: avg("fatG"),
    target: t ? {calories: t.calories, proteinG: t.proteinG} : null,
    daysOnTarget: t ? on : null,
    daysOver: t ? over : null,
    daysUnder: t ? under : null,
    daysProteinMet: t && typeof t.proteinG === "number" ? proteinHit : null,
    daysFromTickedMealsOnly: done.filter(
        (r) => r.consumed.basis === "tickedPlanMeals").length,
    meals: adherence,
    mostMissed: [...missed.entries()]
        .sort((a, b) => b[1] - a[1])
        .slice(0, 3)
        .map(([key, days]) => {
          const [label, status] = key.split("|");
          return {meal: label, status, days};
        }),
  };
}

/**
 * Seven-day buckets for a long window: the shape of a month without thirty
 * rows.
 * @param {!Array<!Object>} rows Daily rows, oldest first.
 * @return {!Array<!Object>}
 */
function weeklyBuckets(rows) {
  const out = [];
  for (let i = 0; i < rows.length; i += 7) {
    const week = rows.slice(i, i + 7).filter((r) => r.basis !== "nothingLogged");
    if (week.length === 0) continue;
    const avg = (f) =>
      round1(week.reduce((n, r) => n + (r[f] || 0), 0) / week.length);
    out.push({
      from: rows[i].date,
      to: rows[Math.min(i + 6, rows.length - 1)].date,
      daysRecorded: week.length,
      avgKcal: avg("kcal"),
      avgProteinG: avg("proteinG"),
    });
  }
  return out;
}

const DIET_HISTORY_TOOL = {
  name: "get_diet_history",
  description:
    "The user's recorded diet over a range: a row per day (consumed, meals " +
    "eaten/planned, skipped, vs target) and a summary (averages, days on/" +
    "over/under target, meals most often missed). days: back from today " +
    "(default 7, max 90), or from/to 'yyyy-MM-dd'.",
  inputSchema: {
    type: "object",
    properties: {
      days: {type: "integer", minimum: 1, maximum: HISTORY_MAX_DAYS},
      from: {type: "string"},
      to: {type: "string"},
    },
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @param {number=} offsetMinutes
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now, offsetMinutes) {
    const todayKey = dayKeyFor(now, offsetMinutes);
    const iso = (v) => typeof v === "string" &&
      /^\d{4}-\d{2}-\d{2}$/.test(v.trim()) ? v.trim() : null;
    const keyDaysBefore = (key, n) => new Date(
        Date.parse(`${key}T12:00:00Z`) - n * 86400000)
        .toISOString().slice(0, 10);
    let to = iso(input.to) || todayKey;
    if (to > todayKey) to = todayKey;
    const days = Number.isInteger(input.days) ?
      Math.min(Math.max(input.days, 1), HISTORY_MAX_DAYS) : 7;
    let from = iso(input.from) || keyDaysBefore(to, days - 1);
    if (from > to) from = to;
    if (from < keyDaysBefore(to, HISTORY_MAX_DAYS - 1)) {
      from = keyDaysBefore(to, HISTORY_MAX_DAYS - 1);
    }
    const records = await store.listDietDays(uid, from, to);
    const byKey = new Map(records.map((r) => [r.dayKey, r]));
    const rows = [];
    const notRecorded = [];
    for (let k = from; k <= to; k = keyDaysBefore(k, -1)) {
      const r = byKey.get(k);
      if (r) rows.push(historyRow(r, todayKey));
      else notRecorded.push(k);
    }
    const out = {
      from,
      to,
      today: todayKey,
      summary: historySummary(records, todayKey),
    };
    if (rows.length > HISTORY_DAILY_ROWS_MAX) {
      out.weeks = weeklyBuckets(rows);
    } else {
      out.days = rows;
    }
    // Absent, not zero: a day with no record had nothing recorded, which is
    // not the same as eating nothing.
    out.notRecorded = notRecorded.length > HISTORY_DAILY_ROWS_MAX ?
      notRecorded.length : notRecorded;
    return out;
  },
};

const RESOLVE_FOOD_TOOL = {
  name: "resolve_food",
  // SEARCH class: looks a food up in ZIVO's own catalog.
  search: true,
  description:
    "Identify a food in ZIVO's nutrition catalog (a USDA subset, plus any " +
    "foods the user defined themselves) so you can price or log it. Returns " +
    "ONE of three outcomes: 'resolved' (a single food, with its `foodId`, " +
    "per-100g nutrition and the measures it supports), 'ambiguous' (several " +
    "foods that differ materially in calories — e.g. raw vs cooked rice — " +
    "each with a `foodId`; pick one with the user before logging), or " +
    "'notFound' (nothing matched — the catalog is US-shaped, so say so and " +
    "offer to log a custom food rather than guessing a number). Pass the " +
    "`foodId` from a resolved/chosen result to calculate_meal_nutrition or " +
    "log_food. query: the food, e.g. 'chicken breast'. preparation (optional): " +
    "'raw', 'cooked' or 'dry' to disambiguate.",
  inputSchema: {
    type: "object",
    properties: {
      query: {type: "string", description: "the food to look up"},
      preparation: {type: "string", enum: ["raw", "cooked", "dry"]},
    },
    required: ["query"],
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input) {
    const query = typeof input.query === "string" ? input.query.trim() : "";
    if (!query) {
      return {outcome: "notFound", query: "", note: "No food named to look up."};
    }
    const preparation = ["raw", "cooked", "dry"].includes(input.preparation) ?
      input.preparation : null;
    const customFoods = await store.listCustomFoods(uid);
    const match = resolveComposite({query, preparation}, customFoods);

    if (match.kind === "notFound") {
      return {
        outcome: "notFound",
        query,
        note:
          "Not in the catalog. It's US-shaped, so plenty of foods genuinely " +
          "aren't. Tell the user, and offer to define it as a custom food " +
          "rather than estimating.",
      };
    }
    if (match.kind === "ambiguous") {
      return {
        outcome: "ambiguous",
        query,
        candidates: match.candidates.map(summariseFood),
        note:
          "These differ materially in calories, so choosing for the user " +
          "would be a guess. Ask which they mean, then pass that foodId.",
      };
    }
    const food = match.food;
    return {
      outcome: "resolved",
      food: {
        ...summariseFood(food),
        per100g: {
          kcal: Math.round(food.kcalPer100g),
          proteinG: food.proteinPer100g,
          carbsG: food.carbsPer100g,
          fatG: food.fatPer100g,
        },
        measures: food.portions.map((p) => p.label),
      },
      alternatives: (match.alternatives || []).map(summariseFood),
    };
  },
};

const CALCULATE_MEAL_TOOL = {
  name: "calculate_meal_nutrition",
  description:
    "Compute the calories and macros of one or more foods at given amounts — " +
    "the ONLY way to turn a food and a quantity into a number. Never do this " +
    "arithmetic yourself. Each item takes a `foodId` (from resolve_food, " +
    "preferred) OR a `query`, plus `quantity` and `unit` (g, kg, oz, lb, or a " +
    "measure the food supports like 'piece'). Returns each item's computed " +
    "nutrition and a combined total. An item that is ambiguous, not found, or " +
    "whose unit can't be converted is flagged instead of guessed, and the " +
    "total is withheld until every item resolves. Use this to answer 'how " +
    "many calories in …' and to preview before logging.",
  inputSchema: {
    type: "object",
    properties: {
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            foodId: {type: "string", description: "from resolve_food, preferred"},
            query: {type: "string", description: "the food, if no foodId"},
            preparation: {type: "string", enum: ["raw", "cooked", "dry"]},
            quantity: {type: "number"},
            unit: {type: "string", description: "g, oz, piece, …"},
          },
        },
      },
    },
    required: ["items"],
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input) {
    const raw = Array.isArray(input.items) ? input.items : [];
    if (raw.length === 0) return {items: [], total: null, allResolved: false};
    const customFoods = await store.listCustomFoods(uid);

    const items = [];
    let allResolved = true;
    let kcal = 0;
    let proteinG = 0;
    let carbsG = 0;
    let fatG = 0;
    for (const rawItem of raw) {
      let normalized;
      try {
        normalized = normalizeItem(rawItem);
      } catch (err) {
        allResolved = false;
        items.push({outcome: "invalid", reason: err.message});
        continue;
      }
      const result = resolveAndCompute(normalized, customFoods);
      items.push(result);
      if (result.outcome === "computed") {
        kcal += result.kcal;
        proteinG += result.proteinG;
        carbsG += result.carbsG;
        fatG += result.fatG;
      } else {
        allResolved = false;
      }
    }

    return {
      items,
      // Only a total everything actually resolved to — a partial sum would be
      // a number that looks whole but isn't.
      total: allResolved ? {
        kcal: Math.round(kcal),
        proteinG: Math.round(proteinG * 10) / 10,
        carbsG: Math.round(carbsG * 10) / 10,
        fatG: Math.round(fatG * 10) / 10,
      } : null,
      allResolved,
    };
  },
};

const SEARCH_FOOD_ALTERNATIVES_TOOL = {
  name: "search_food_alternatives",
  // SEARCH class: finds and prices options, changes nothing.
  search: true,
  // Its cards get ZIVO's own "Other options" chip — there are always more
  // foods to look for (`../chat/choices.js` withMoreOption).
  moreOptions: true,
  description:
    "Find realistic replacements for ONE item in the user's active plan " +
    "they don't want. Pass 3–6 candidate foods YOU choose (see MEAL " +
    "REPLACEMENT for how) as simple single foods the catalog can price. " +
    "ZIVO prices each one and sizes a portion to the original item's " +
    "calories; a candidate it can't price comes back found:false — drop " +
    "it, never estimate it. Changes nothing: show the found options with " +
    "ask_choice and wait for the user's pick. Identify the item with " +
    "mealId, itemIndex and itemName exactly as get_today/get_diet gave " +
    "them.",
  inputSchema: {
    type: "object",
    properties: {
      mealId: {type: "string", description: "exact id from get_today/get_diet"},
      itemIndex: {
        type: "integer",
        description: "the item's `index` from get_today/get_diet, within that meal",
      },
      itemName: {
        type: "string",
        description: "the item's exact name from get_today/get_diet, to catch a stale reference",
      },
      candidates: {
        type: "array",
        description: "3–6 realistic replacement foods you propose, in order of fit",
        items: {
          type: "object",
          properties: {
            name: {type: "string", description: "a simple food name in English, e.g. 'green beans'"},
            preparation: {type: "string", enum: ["raw", "cooked"]},
          },
          required: ["name"],
        },
      },
      avoid: {
        type: "array",
        items: {type: "string"},
        description: "foods the user said they don't want or are allergic to",
      },
      day: {type: "string", description: "optional 'yyyy-MM-dd', default today"},
    },
    required: ["mealId", "itemIndex", "itemName", "candidates"],
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @param {number=} offsetMinutes
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now, offsetMinutes) {
    const mealId = typeof input.mealId === "string" ? input.mealId.trim() : "";
    const itemIndex = Number.isInteger(input.itemIndex) ? input.itemIndex : -1;
    const itemName = typeof input.itemName === "string" ?
      input.itemName.trim() : "";
    const candidates = (Array.isArray(input.candidates) ? input.candidates : [])
        .map((c) => typeof c === "string" ? {name: c} : c)
        .filter((c) => c && typeof c.name === "string" && c.name.trim());
    if (!mealId || itemIndex < 0 || !itemName) {
      return {
        outcome: "invalidInput",
        note: "Need mealId, itemIndex and itemName, all from get_today/get_diet.",
      };
    }
    if (candidates.length === 0) {
      return {
        outcome: "invalidInput",
        note: "Propose 3–6 realistic replacement foods in `candidates`.",
      };
    }

    const requested = typeof input.day === "string" ?
      /^\d{4}-\d{2}-\d{2}$/.exec(input.day.trim()) : null;
    const date = requested ? new Date(`${requested[0]}T12:00:00Z`) : now;
    const dateOffset = requested ? 0 : offsetMinutes;

    const plan = await store.getActiveDietPlan(uid);
    if (!plan) {
      return {
        outcome: "notFound",
        note: "There's no active diet plan, so there's nothing to replace.",
      };
    }
    const day = resolveDietDay(plan.days || [], date, dateOffset);
    const meals = day && Array.isArray(day.meals) ? day.meals : [];
    const meal = meals.find((m) => m && m.id === mealId);
    if (!meal) {
      return {
        outcome: "notFound",
        note: `No meal with id "${mealId}" exists for that day. Call ` +
          "get_diet and use an exact id and index from it.",
      };
    }
    const items = Array.isArray(meal.items) ? meal.items : [];
    const item = items[itemIndex];
    if (!item ||
        String(item.name || "").trim().toLowerCase() !== itemName.toLowerCase()) {
      return {
        outcome: "notFound",
        note: "That item isn't there any more — the plan may have changed. " +
          "Call get_diet again and use its current index/name.",
      };
    }

    const customFoods = await store.listCustomFoods(uid);
    const priced = priceReplacementCandidates({
      originalName: item.name,
      originalCalories: Number(item.calories),
      candidates,
      customFoods,
      avoid: Array.isArray(input.avoid) ? input.avoid : [],
    });
    const found = priced.filter((c) => c.found);
    const original = {
      mealId,
      mealLabel: meal.label,
      itemIndex,
      name: item.name,
      quantity: item.quantity,
      unit: item.unit,
      calories: item.calories,
      macroRole: classifyMacroRole({
        proteinG: item.proteinG, carbsG: item.carbsG, fatG: item.fatG,
      }),
    };
    if (found.length === 0) {
      return {
        outcome: "noAlternatives",
        original,
        notFound: priced.map((c) => c.name),
        note: "None of those could be priced. Try simpler single-food names, " +
          "or ask the user what they'd like instead — never estimate one.",
      };
    }
    return {
      outcome: "found",
      original,
      // Each: foodId (pass to replace_meal_item), the portion sized to the
      // original's calories (pass its grams as quantity, unit "g"), and the
      // catalog's per-100g figures.
      alternatives: found,
      notFound: priced.filter((c) => !c.found).map((c) => c.name),
    };
  },
  /**
   * The verified options this result supports, for the choice card
   * (`../chat/choices.js`). One per found alternative, keyed by its foodId,
   * each bound to the exact `replace_meal_item` call choosing it means — the
   * item reference from `original` and the portion ZIVO priced — so a tapped
   * option is proposed as-is, never re-derived by the model. Null when fewer
   * than two were found: one option is not a choice, and none is a "no
   * alternatives" reply, not an empty card.
   * @param {!Object} result This tool's `execute` result.
   * @param {!Object} input The tool input it ran with.
   * @return {?Array<!Object>}
   */
  choiceOffer(result, input) {
    if (!result || result.outcome !== "found" ||
        !Array.isArray(result.alternatives) ||
        result.alternatives.length < 2) {
      return null;
    }
    const day = typeof input.day === "string" ?
      /^\d{4}-\d{2}-\d{2}$/.exec(input.day.trim()) : null;
    const o = result.original;
    return result.alternatives.map((alt) => {
      const p = alt.portion;
      const label = alt.name.charAt(0).toUpperCase() + alt.name.slice(1);
      const replaceInput = {
        mealId: o.mealId,
        itemIndex: o.itemIndex,
        itemName: o.name,
        foodId: alt.foodId,
        quantity: p.grams,
        unit: "g",
      };
      if (day) replaceInput.date = `${day[0]}T12:00:00Z`;
      return {
        value: alt.foodId,
        label,
        aliases: [alt.name, alt.catalogName],
        subtitle: `${p.grams} g · ${p.kcal} kcal · ${p.proteinG} g protein`,
        metadata: {
          grams: p.grams, kcal: p.kcal, proteinG: p.proteinG,
          carbsG: p.carbsG, fatG: p.fatG,
        },
        binding: {tool: "replace_meal_item", input: replaceInput},
      };
    });
  },
};

const SUMMARIZE_WEEK_TOOL = {
  name: "summarize_week",
  description:
    "A composed digest of the current week (in the user's own timezone) " +
    "across workouts, expenses, and the active diet plan.",
  inputSchema: {type: "object", properties: {}},
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @param {number=} offsetMinutes
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now, offsetMinutes) {
    const week = weekRangeMs(now, offsetMinutes);
    const [expenses, workouts, plan] = await Promise.all([
      store.listExpenses(uid, week),
      store.listWorkouts(uid, week),
      store.getActiveDietPlan(uid),
    ]);

    let totalMinor = 0;
    const totalByCategory = {};
    let currency = null;
    for (const e of expenses) {
      totalMinor += e.amountMinor;
      totalByCategory[e.category] =
        (totalByCategory[e.category] || 0) + e.amountMinor;
      currency = currency || e.currency;
    }

    return dropNull({
      today: dayKeyFor(now, offsetMinutes),
      weekStart: dayKeyFor(new Date(week.fromMs), offsetMinutes),
      workouts: workouts.map((w) => ({
        title: w.title,
        performedAt: iso(w.performedAt),
      })),
      expenses: {currency, totalMinor, totalByCategory},
      dietPlan: plan ? plan.name : null,
    });
  },
};

const READINESS_TOOL = {
  name: "get_readiness",
  description:
    "ZIVO's Daily Readiness call — the SAME train-hard / go-light / rest " +
    "recommendation the Today screen shows, fused from last night's " +
    "sleep, the training stall/deload signal, how recently the user " +
    "trained, and their body-weight trend. Use it for 'how am I today', " +
    "'should I train hard', 'what should I do today' and recovery " +
    "questions. Returns `available:false` when there is not enough data. " +
    "Otherwise `verdict` (trainHard | goLight | rest) and `factors` — " +
    "each with the number behind it: `sleep` (sleepDurationMinutes, " +
    "sleepDeltaMinutes vs target), `deload` (deloadExerciseCount stalled " +
    "lifts), `recentLoad` (restDays since last session), `bodyWeight` " +
    "(weightChangeKg over ~30 days) — and a `direction` of supports / " +
    "caution / limits. Always carries `training`: the last completed " +
    "session (`lastSessionName`, `lastSessionDaysAgo`, null = never), " +
    "`trainedToday`, and `upNext` — the next day in their split rotation " +
    "(after today's session when one is done; null = no split). That's " +
    "everything a 'should I train today' call needs in one read.",
  inputSchema: {type: "object", properties: {}},
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @param {number=} offsetMinutes
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now, offsetMinutes) {
    const dayMs = 24 * 60 * 60 * 1000;
    const todayStart = startOfDay(now, offsetMinutes).getTime();
    const daysAgo = (ms) => {
      const start = startOfDay(new Date(ms), offsetMinutes).getTime();
      return Math.round((todayStart - start) / dayMs);
    };

    // Training — the deload signal and how recently they trained.
    const [{sessions}, plan] = await Promise.all([
      loadResolvedSessions(store, uid),
      store.getActiveWorkoutPlan ?
        store.getActiveWorkoutPlan(uid) : Promise.resolve(null),
    ]);
    const analysis = analyzeTraining({sessions, now});
    let lastSessionMs = null;
    let lastSession = null;
    for (const s of sessions) {
      if (s.status !== "completed") continue;
      const at = s.completedAt || s.startedAt;
      const ms = at ? at.getTime() : null;
      if (ms !== null && (lastSessionMs === null || ms > lastSessionMs)) {
        lastSessionMs = ms;
        lastSession = s;
      }
    }
    const lastSessionDaysAgo =
      lastSessionMs === null ? null : daysAgo(lastSessionMs);
    // The facts a train-today decision rests on besides the readiness call
    // itself — what was done last, and what the split has up next — so the
    // coach decides from one read instead of guessing the half it didn't
    // fetch. Facts only: the decision is the model's, grounded in these.
    const hasSplit = plan && Array.isArray(plan.days) && plan.days.length > 0;
    const training = {
      lastSessionName: lastSession ?
        String(lastSession.dayLabel || "").trim() || null : null,
      lastSessionDaysAgo,
      trainedToday: lastSessionDaysAgo === 0,
      upNext: hasSplit ?
        dayName(rotationFrom(plan.days, plan.cycleCursor)[0]) : null,
    };

    // Sleep — only the newest night, and only if it is genuinely recent.
    const nights = store.listSleepNights ?
      await store.listSleepNights(uid) : [];
    let sleepDurationMinutes = null;
    let sleepTargetMinutes = null;
    const latestNight = nights[0]; // newest first, already has data
    if (latestNight && daysAgo(latestNight.sleepDayMs) <= 1) {
      sleepDurationMinutes = latestNight.asleepMinutes;
      sleepTargetMinutes = latestNight.targetDurationMinutes;
    }

    // Body weight — signed change over the trailing 30 days (mirrors
    // `computeWeightTrend`). `listBodyWeights` is oldest→newest.
    const weights = store.listBodyWeights ?
      await store.listBodyWeights(uid) : [];
    let weightChangeKg = null;
    const cutoff = now.getTime() - 30 * dayMs;
    const inWindow = weights.filter((w) => w.loggedAtMs >= cutoff);
    if (inWindow.length >= 2) {
      weightChangeKg =
        inWindow[inWindow.length - 1].weightKg - inWindow[0].weightKg;
    }

    const readiness = readinessFromSignals({
      sleepDurationMinutes,
      sleepTargetMinutes,
      stalledCount: analysis.needsAttention.length,
      overallStatusRegressing: analysis.overallStatus === "regressing",
      lastSessionDaysAgo,
      weightChangeKg,
    });
    if (readiness === null) {
      return {
        date: dayKeyFor(now, offsetMinutes),
        available: false,
        reason: "No readiness call: last night's sleep, training load and " +
          "weigh-ins are missing or show nothing notable.",
        training,
      };
    }
    return {date: dayKeyFor(now, offsetMinutes), available: true, ...readiness,
      training};
  },
};

const SLEEP_SUMMARY_TOOL = {
  name: "get_sleep_summary",
  description:
    "A compact sleep summary: last night's duration vs the user's " +
    "sleep-duration target, plus a rolling average over their most recent " +
    "nights. For sleep-SPECIFIC questions ('how did I sleep', 'is my " +
    "sleep improving'); readiness questions belong to get_readiness. " +
    "Durations are in minutes; a positive `deltaMinutes` means over " +
    "target, negative means short. `available:false` when no sleep is " +
    "recorded. `latestNightDaysAgo` says how fresh the newest night is — " +
    "when it's not last night, `lastNight` is null: say the freshest data " +
    "is from N days ago rather than call it last night.",
  inputSchema: {type: "object", properties: {}},
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @param {number=} offsetMinutes
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now, offsetMinutes) {
    const today = dayKeyFor(now, offsetMinutes);
    const nights = store.listSleepNights ?
      await store.listSleepNights(uid) : [];
    if (!nights || nights.length === 0) {
      return {date: today, available: false};
    }

    const dayMs = 24 * 60 * 60 * 1000;
    const todayStart = startOfDay(now, offsetMinutes).getTime();
    const daysAgo = (ms) => Math.round(
        (todayStart - startOfDay(new Date(ms), offsetMinutes).getTime()) /
        dayMs);

    const latest = nights[0]; // newest first (store sorts desc)
    const latestDaysAgo = daysAgo(latest.sleepDayMs);
    // "Last night" only holds when the newest record is genuinely recent; a
    // stale newest night is reported via `latestNightDaysAgo` instead of being
    // passed off as last night's sleep.
    const lastNight = latestDaysAgo <= 2 ? {
      date: dayKeyFor(new Date(latest.sleepDayMs), offsetMinutes),
      daysAgo: latestDaysAgo,
      asleepMinutes: latest.asleepMinutes,
      targetMinutes: latest.targetDurationMinutes,
      deltaMinutes: latest.targetDurationMinutes == null ?
        null : latest.asleepMinutes - latest.targetDurationMinutes,
    } : null;

    const recent = nights.slice(0, 7);
    const avgAsleepMinutes = Math.round(
        recent.reduce((sum, n) => sum + n.asleepMinutes, 0) / recent.length);
    const withTarget = recent.filter((n) => n.targetDurationMinutes != null);
    const avgDeltaVsTargetMinutes = withTarget.length === 0 ? null : Math.round(
        withTarget.reduce(
            (sum, n) => sum + (n.asleepMinutes - n.targetDurationMinutes), 0) /
        withTarget.length);

    return dropNull({
      date: today,
      available: true,
      latestNightDaysAgo: latestDaysAgo,
      lastNight,
      recent: {
        nights: recent.length,
        avgAsleepMinutes,
        avgDeltaVsTargetMinutes,
      },
    });
  },
};

// Read tools, in the order the model sees them. `get_tasks`, `get_schedule`,
// `get_university` and `search_notes` were removed in 2026-08 together with
// the Schedule/Tasks/University/Notes features themselves (ADR-004): they
// read collections the app no longer writes, so they could only ever return
// empty — while still costing a schema in every cached prefix and, in
// `get_today`'s case, four awaited reads per call.
const WORKOUT_SCHEDULE_TOOL = {
  name: "get_workout_schedule",
  description:
    "The user's training ROTATION (their active split) — which workout is " +
    "scheduled today, what comes after it, and every day in the cycle with " +
    "its dayId and exercises. A split is a rotating cycle (Push → Pull → " +
    "Legs → …), not a weekday calendar: `today` is the day up next in the " +
    "rotation. `trainedToday` says whether a session was already completed " +
    "today. Use it for \"what's my workout today\", and ALWAYS before " +
    "change_workout_day — its dayIds are the only valid ones.",
  inputSchema: {type: "object", properties: {}},
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @param {number=} offsetMinutes
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now, offsetMinutes) {
    const plan = store.getActiveWorkoutPlan ?
      await store.getActiveWorkoutPlan(uid) : null;
    if (!plan || !Array.isArray(plan.days) || plan.days.length === 0) {
      return {outcome: "noPlan",
        note: "The user has no workout split set up."};
    }
    const cycle = rotationFrom(plan.days, plan.cycleCursor);
    const describe = (d) => ({
      dayId: d.id,
      name: dayName(d),
      slot: d.slot || null,
      exercises: (d.exercises || []).slice()
          .sort((a, b) => (a.order || 0) - (b.order || 0))
          .map((e) => e.name).filter(Boolean),
    });
    let trainedToday = null;
    if (store.listWorkoutSessions) {
      const sessions = await store.listWorkoutSessions(
          uid, dayRangeMs(now, offsetMinutes));
      const done = sessions.find((x) => x.status === "completed");
      trainedToday = done ? {dayId: done.dayId, name: done.dayLabel} : null;
    }
    return {
      outcome: "found",
      date: dayKeyFor(now, offsetMinutes),
      split: plan.name,
      today: describe(cycle[0]),
      next: cycle.length > 1 ? describe(cycle[1]) : null,
      rotation: cycle.map(describe),
      trainedToday,
    };
  },
};

const PREVIEW_WORKOUT_CHANGE_TOOL = {
  name: "preview_workout_change",
  // SEARCH class: lays out the two ways to train another day today, changes
  // nothing. Its result is a verified OFFER (`choiceOffer`) — ask_choice after
  // it becomes the skip-or-swap question, and a tap proposes that exact change.
  search: true,
  description:
    "When the user wants to train a DIFFERENT day than the one scheduled " +
    "today but hasn't said whether to skip or swap (\"I want to do Pull " +
    "today\"): lays out both — 'swap' (they trade places: the other day " +
    "today, the scheduled one next) and 'skip' (the scheduled day drops out " +
    "of this round). Changes nothing. Then ask with ask_choice using values " +
    "'skip' and 'swap'; ZIVO attaches the exact change to each option. Don't " +
    "use it when the user already said skip or swap — call " +
    "change_workout_day. `dayId` from get_workout_schedule.",
  inputSchema: {
    type: "object",
    properties: {
      dayId: {
        type: "string",
        description: "the day they want to train today, from get_workout_schedule",
      },
    },
    required: ["dayId"],
  },
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input) {
    const plan = store.getActiveWorkoutPlan ?
      await store.getActiveWorkoutPlan(uid) : null;
    if (!plan || !Array.isArray(plan.days) || plan.days.length < 2) {
      return {outcome: "noRotation",
        note: "No split with more than one day — nothing to rearrange."};
    }
    const due = upNextDay(plan.days, plan.cycleCursor);
    const target = plan.days.find((d) => d.id === input.dayId);
    if (!target) {
      return {outcome: "invalidInput",
        note: "Unknown dayId — use one from get_workout_schedule."};
    }
    if (target.id === due.id) {
      return {outcome: "alreadyToday", today: dayName(due)};
    }
    const afterTarget = dayAfter(plan.days, target.id);
    return {
      outcome: "found",
      today: dayName(due),
      requested: dayName(target),
      // Both ways, spelled out — the two options the user chooses between.
      alternatives: [
        {mode: "skip", effect: `${dayName(target)} today; ${dayName(due)} ` +
          "is dropped from this round" +
          (afterTarget ? `; then ${dayName(afterTarget)}` : "")},
        {mode: "swap", effect: `${dayName(target)} today; ${dayName(due)} ` +
          "comes next — nothing is missed"},
      ],
    };
  },
  /**
   * The verified skip / swap options, each bound to the exact
   * change_workout_day call choosing it means.
   * @param {!Object} result
   * @param {!Object} input
   * @return {?Array<!Object>}
   */
  choiceOffer(result, input) {
    if (!result || result.outcome !== "found") return null;
    const from = result.today;
    const to = result.requested;
    return [
      {
        value: "skip",
        label: `Skip ${from}`,
        aliases: ["skip", `skip ${from}`],
        subtitle: `${to} today, ${from} waits till next round`,
        metadata: {mode: "skip", from, to},
        binding: {tool: "change_workout_day",
          input: {mode: "skip", dayId: input.dayId}},
      },
      {
        value: "swap",
        label: `Swap ${from} and ${to}`,
        aliases: ["swap", `swap ${from} with ${to}`],
        subtitle: `${to} today, ${from} next`,
        metadata: {mode: "swap", from, to},
        binding: {tool: "change_workout_day",
          input: {mode: "swap", dayId: input.dayId}},
      },
    ];
  },
};

const tools = [
  TODAY_TOOL,
  WORKOUT_SCHEDULE_TOOL,
  PREVIEW_WORKOUT_CHANGE_TOOL,
  EXPENSES_TOOL,
  WORKOUTS_TOOL,
  LAST_WORKOUT_TOOL,
  TRAINING_ANALYSIS_TOOL,
  EXERCISE_ANALYSIS_TOOL,
  READINESS_TOOL,
  SLEEP_SUMMARY_TOOL,
  DIET_TOOL,
  DIET_HISTORY_TOOL,
  RESOLVE_FOOD_TOOL,
  CALCULATE_MEAL_TOOL,
  SEARCH_FOOD_ALTERNATIVES_TOOL,
  SUMMARIZE_WEEK_TOOL,
];

const toolsByName = new Map(tools.map((t) => [t.name, t]));

module.exports = {tools, toolsByName, dayNutrition, anyEstimated};
