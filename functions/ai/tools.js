/**
 * The server-side read-only tool registry for the `aiChat` gateway
 * (`functions/ai/gateway.js`). Every tool is `uid`-scoped and reads through
 * the injected `store` seam (`functions/ai/store.js` in production, a plain
 * in-memory fake in tests) — nothing here touches Firestore or any SDK
 * directly, so it runs offline under `node --test`.
 *
 * Strictly READ-ONLY: no tool writes, creates, or deletes anything.
 *
 * Two rules this registry holds to, both about trust rather than mechanics:
 *
 * 1. **Every payload states its own date.** Nothing else in a turn tells the
 *    model what day it is. A tool that resolves "today" says which day that
 *    was, in the user's timezone (`offsetMinutes`, forwarded from the client
 *    by `aiChat` — see `./dates.js`).
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
} = require("./dates");
const {buildDietState, summariseHistory} = require("../diet/state");
const {calibrateMaintenance, energyFor, ageFrom} = require("../diet/energy");
const {coachingFindings} = require("../diet/rules");
const {analyzeTraining} = require("./workout_analytics");
const {
  resolveComposite,
  resolveAndCompute,
  normalizeItem,
  summariseFood,
} = require("../nutrition/resolve");

/**
 * ISO string for `date`, or null.
 * @param {?Date} date
 * @return {?string}
 */
function iso(date) {
  return date ? date.toISOString() : null;
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
 * Projects a `DietState` into the shape the model reads. Field order matters:
 * tool results are truncated from the END, so what the coach must never lose —
 * the date, the objective, where the user stands — is serialized first.
 * @param {!Object} state
 * @param {!Array<Object>} log The day's raw entries.
 * @param {?number} localHour The user's own hour of day, when known.
 * @return {!Object}
 */
function stateForModel(state, log, localHour) {
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
    meals: state.meals,
    history: state.history,
    // The individual foods, so the coach can talk about what was eaten rather
    // than only about totals.
    logEntries: log.map((e) => ({
      food: e.foodName,
      quantity: e.quantity,
      unit: e.unit,
      kcal: e.kcal,
      proteinG: e.proteinG,
      carbsG: e.carbsG,
      fatG: e.fatG,
      source: e.source,
      origin: e.origin,
      estimated: e.estimated,
    })),
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
      ...stateForModel(state, log, localHourAt(now, offsetMinutes)),
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

    return {
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
        note: e.note || null,
        spentAt: iso(e.spentAt),
      })),
    };
  },
};

/**
 * A session's actual duration in minutes (active time, pauses excluded).
 * @param {!Object} s
 * @return {?number}
 */
function sessionDurationMinutes(s) {
  if (!s.completedAt || !s.startedAt) return null;
  const ms = s.completedAt.getTime() - s.startedAt.getTime() -
    (s.pausedAccumMs || 0);
  return ms > 0 ? Math.round(ms / 60000) : 0;
}

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
    const sessions = await store.listWorkoutSessions(uid, range);
    sessions.sort((a, b) =>
      (b.completedAt || b.startedAt) - (a.completedAt || a.startedAt));
    return {
      range: input.range === "month" ? "month" : "week",
      today: dayKeyFor(now, offsetMinutes),
      note:
        "Each set below is what the user actually performed. A warm-up set " +
        "(type='warmup') is not working volume; the top set is the heaviest " +
        "set with type!='warmup'.",
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
    };
  },
};

const TRAINING_ANALYSIS_TOOL = {
  name: "get_training_analysis",
  description:
    "ZIVO's deterministic workout analysis over the user's whole session " +
    "history — the SAME numbers the Progress screen shows, so you never have " +
    "to compute strength, PRs or trends yourself (and must not contradict " +
    "them). Returns: overallStatus + a plain summary; overallStrengthChangePercent " +
    "(estimated 1RM change over ~6 weeks); per-exercise status " +
    "(progressing/maintaining/plateauing/regressing/building) with " +
    "strengthChangePercent and currentE1RM; a simple per-muscle weekly rollup; " +
    "weekly working volume vs last week; recentPrs (last 30 days); improving / " +
    "needsAttention lists; a nextStep; and `findings` — typed, ranked coaching " +
    "conclusions each marked confidence 'fact' (measured) or 'interpretation'. " +
    "**Lead with findings**, keep facts and interpretations distinct, and if " +
    "there is no data say so. Estimated strength is e1RM — call it 'estimated " +
    "strength', never expose the formula.",
  inputSchema: {type: "object", properties: {}},
  /**
   * @param {!Object} store
   * @param {string} uid
   * @param {!Object} input
   * @param {Date} now
   * @return {!Promise<!Object>}
   */
  async execute(store, uid, input, now) {
    const sessions = await store.listWorkoutSessions(uid);
    const analysis = analyzeTraining({sessions, now});
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
    };
  },
};

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

const DIET_TOOL = {
  name: "get_diet",
  description:
    "The active diet plan's meals for a day (default today, in the user's " +
    "own timezone), with calories/macros, which meals are already eaten, " +
    "plan-vs-consumed nutrition totals, the user's own daily `targets` and " +
    "what's `remaining` of them. Every figure carries an `estimated` flag: " +
    "true means it was AI-estimated when the plan was imported, not stated " +
    "by the plan itself. `targets` is null when the user hasn't set an " +
    "objective. day: optional 'yyyy-MM-dd'.",
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
          state, log, requested ? null : localHourAt(now, offsetMinutes)),
      // The plan's items, so the coach can discuss what the plan prescribes
      // rather than only its totals. Last in the payload: it is the block
      // that can most afford to be truncated.
      planItems: !dietDay ? [] : dietDay.meals.map((m) => ({
        id: m.id,
        label: m.label,
        items: m.items.map((it) => ({
          name: it.name,
          quantity: it.quantity,
          unit: it.unit,
          calories: it.calories,
          proteinG: it.proteinG,
          carbsG: it.carbsG,
          fatG: it.fatG,
          // Provenance, not decoration: true means this item's figures came
          // from an AI estimate at import time, never from a measurement or
          // the plan document itself.
          estimated: it.estimated === true,
        })),
      })),
    };
  },
};

const RESOLVE_FOOD_TOOL = {
  name: "resolve_food",
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

    return {
      today: dayKeyFor(now, offsetMinutes),
      weekStart: dayKeyFor(new Date(week.fromMs), offsetMinutes),
      workouts: workouts.map((w) => ({
        title: w.title,
        performedAt: iso(w.performedAt),
      })),
      expenses: {currency, totalMinor, totalByCategory},
      dietPlan: plan ? plan.name : null,
    };
  },
};

// Read tools, in the order the model sees them. `get_tasks`, `get_schedule`,
// `get_university` and `search_notes` were removed in 2026-08 together with
// the Schedule/Tasks/University/Notes features themselves (ADR-004): they
// read collections the app no longer writes, so they could only ever return
// empty — while still costing a schema in every cached prefix and, in
// `get_today`'s case, four awaited reads per call.
const tools = [
  TODAY_TOOL,
  EXPENSES_TOOL,
  WORKOUTS_TOOL,
  TRAINING_ANALYSIS_TOOL,
  DIET_TOOL,
  RESOLVE_FOOD_TOOL,
  CALCULATE_MEAL_TOOL,
  SUMMARIZE_WEEK_TOOL,
];

const toolsByName = new Map(tools.map((t) => [t.name, t]));

module.exports = {tools, toolsByName, dayNutrition, anyEstimated};
