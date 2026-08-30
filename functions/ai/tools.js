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
 * 3. **Consumption is the LOG, not the plan.** What the user recorded eating
 *    (`foodLogs`) is what `consumed`/`remaining` are computed from. Each entry
 *    says whether a person logged it or the app materialised it from a ticked
 *    meal, and the payload says which kind the day is made of — "you ate 1,850"
 *    and "the plan values what you ticked at 1,850" are different claims.
 * 4. **"Target" is never implied.** The user's own objective
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
  resolveDietDay,
} = require("./dates");

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
 * The target-vs-consumed adherence block for one resolved diet day — consumed
 * counts only the meals whose eaten-toggle is set, so a checked-off meal
 * contributes its planned macros. Null components mean the plan doesn't state
 * that nutrient anywhere; they stay null rather than reading as zero.
 * @param {!Array<Object>} meals The day's planned meals.
 * @param {!Set<string>} eatenMealIds
 * @return {!Object} `{target, consumed}` nutrition totals.
 */
function adherenceFor(meals, eatenMealIds) {
  return {
    target: dayNutrition(meals),
    consumed: dayNutrition(meals.filter((m) => m && eatenMealIds.has(m.id))),
  };
}

/**
 * One planned meal projected for the model: its id (the handle
 * `mark_meal_eaten` needs), its label, whether it's eaten, its kcal, and
 * whether that kcal figure is estimated.
 * @param {!Object} meal
 * @param {!Set<string>} eaten
 * @return {!Object}
 */
function mealSummary(meal, eaten) {
  const items = Array.isArray(meal.items) ? meal.items : [];
  return {
    id: meal.id,
    label: meal.label,
    eaten: eaten.has(meal.id),
    kcal: sumItemField(items, "calories"),
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
 * What is left of the user's targets after the meals they've ticked off —
 * computed here, deterministically, rather than left to the model's
 * arithmetic. Null when there are no targets to measure against.
 *
 * `consumedFrom` is stated explicitly because it is the honest caveat on
 * every one of these numbers: ZIVO has no food log yet, so "consumed" means
 * "the planned figures of the meals you ticked", not "what you ate".
 * @param {?Object} targets
 * @param {!Object} consumed A `consumedFrom` result.
 * @return {?Object}
 */
function remainingPayload(targets, consumed) {
  if (!targets) return null;
  const left = (target, eaten) =>
    target === null || target === undefined ? null :
      Math.round((target - (eaten || 0)) * 10) / 10;
  return {
    kcal: targets.calories - (consumed.kcal || 0),
    proteinG: left(targets.proteinG, consumed.proteinG),
    carbsG: left(targets.carbsG, consumed.carbsG),
    fatG: left(targets.fatG, consumed.fatG),
    consumedFrom: consumed.basis || "ticked meals in the plan",
    estimated: consumed.estimated === true,
  };
}

/**
 * Day totals over food-log entries, plus the honesty flags a caller needs to
 * describe them truthfully. Mirrors the Dart `totalsOf`.
 * @param {!Array<Object>} entries
 * @return {!Object}
 */
function logTotals(entries) {
  const round1 = (v) => Math.round(v * 10) / 10;
  let kcal = 0;
  let proteinG = 0;
  let carbsG = 0;
  let fatG = 0;
  let logged = 0;
  let planned = 0;
  let estimated = false;
  for (const e of entries) {
    kcal += e.kcal;
    proteinG += e.proteinG;
    carbsG += e.carbsG;
    fatG += e.fatG;
    if (e.estimated) estimated = true;
    if (e.origin === "logged") logged++;
    else planned++;
  }
  return {
    kcal,
    proteinG: round1(proteinG),
    carbsG: round1(carbsG),
    fatG: round1(fatG),
    estimated,
    entryCount: entries.length,
    loggedCount: logged,
    plannedMealCount: planned,
    // The caveat that has to travel with the numbers.
    basis: entries.length === 0 ? "nothing logged" :
      logged === 0 ? "materialised from ticked plan meals, not weighed" :
        "logged by the user",
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

/**
 * What the user consumed, preferring the FOOD LOG and falling back to the
 * planned figures of ticked meals only when the log is empty (a day recorded
 * before the log existed). The `basis` field says which it was, so the coach
 * can never pass an assumption off as a measurement.
 * @param {!Array<Object>} log
 * @param {!Object} plannedConsumed A `dayNutrition` result for eaten meals.
 * @return {!Object}
 */
function consumedFrom(log, plannedConsumed) {
  if (log.length > 0) return logTotals(log);
  return {
    kcal: plannedConsumed.kcal || 0,
    proteinG: plannedConsumed.proteinG,
    carbsG: plannedConsumed.carbsG,
    fatG: plannedConsumed.fatG,
    estimated: plannedConsumed.estimated === true,
    entryCount: 0,
    loggedCount: 0,
    plannedMealCount: 0,
    basis: "ticked plan meals (nothing logged that day)",
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
    const [workouts, dietDay, targets] = await Promise.all([
      store.listWorkouts(uid, {fromMs, toMs}),
      loadDietDay(store, uid, now, offsetMinutes),
      store.getDietTargets(uid),
    ]);

    const {plan, dietDay: day, eaten, log} = dietDay;
    const consumed = consumedFrom(
        log, plan && day ? adherenceFor(day.meals, eaten).consumed :
          dayNutrition([]));
    const remaining = remainingPayload(targets, consumed);
    let diet = null;
    if (plan && day) {
      diet = {
        planName: plan.name,
        dayLabel: day.label,
        nutrition: adherenceFor(day.meals, eaten),
        meals: day.meals.map((m) => mealSummary(m, eaten)),
      };
    }

    // `targets`/`remaining`/`diet` lead the payload deliberately. Tool results
    // are capped at `maxToolResultChars` and truncated from the END, so
    // whatever is serialized last is what disappears on a rich plan — the
    // user's objective and their nutrition are the blocks that must never be
    // silently half-delivered.
    return {
      date: dayKeyFor(now, offsetMinutes),
      targets: targetsPayload(targets),
      consumed,
      remaining,
      diet,
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

const WORKOUTS_TOOL = {
  name: "get_workouts",
  description:
    "List workout sessions with exercise summaries. range: 'week' " +
    "(default) or 'month'.",
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
    const workouts = await store.listWorkouts(uid, range);
    return {
      range: input.range === "month" ? "month" : "week",
      today: dayKeyFor(now, offsetMinutes),
      workouts: workouts.map((w) => ({
        title: w.title,
        performedAt: iso(w.performedAt),
        durationMinutes: w.durationMinutes,
        exercises: (w.exercises || []).map((e) => ({
          name: e.name,
          sets: e.sets,
          reps: e.reps,
          weightKg: e.weightKg,
        })),
      })),
    };
  },
};

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
    const dateKey = dayKeyFor(date, dateOffset);
    const targetsBlock = targetsPayload(targets);
    const planned = dietDay ?
      adherenceFor(dietDay.meals, eaten) :
      {target: dayNutrition([]), consumed: dayNutrition([])};
    const consumed = consumedFrom(log, planned.consumed);

    const head = {
      date: dateKey,
      targets: targetsBlock,
      consumed,
      remaining: remainingPayload(targets, consumed),
      // Every logged item, so the coach can talk about what was actually
      // eaten rather than only about totals.
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
    if (!plan) return {...head, plan: null};
    if (!dietDay) return {...head, plan: plan.name, day: null};

    return {
      ...head,
      plan: plan.name,
      day: dietDay.label,
      nutrition: planned,
      meals: dietDay.meals.map((m) => ({
        ...mealSummary(m, eaten),
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
  DIET_TOOL,
  SUMMARIZE_WEEK_TOOL,
];

const toolsByName = new Map(tools.map((t) => [t.name, t]));

module.exports = {tools, toolsByName, dayNutrition, anyEstimated};
