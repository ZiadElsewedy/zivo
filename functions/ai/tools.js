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
 * Loads the active plan's resolved day for `date` plus that day's eaten-meal
 * ids — the shared read behind `get_diet` and `get_today`'s diet block.
 * @param {!Object} store
 * @param {string} uid
 * @param {!Date} date
 * @param {number=} offsetMinutes
 * @return {!Promise<?{plan: !Object, dietDay: !Object, eaten: !Set<string>}>}
 */
async function loadDietDay(store, uid, date, offsetMinutes) {
  const plan = await store.getActiveDietPlan(uid);
  if (!plan) return {plan: null, dietDay: null, eaten: new Set()};
  const dietDay = resolveDietDay(plan.days, date, offsetMinutes);
  if (!dietDay) return {plan, dietDay: null, eaten: new Set()};
  const entries = await store.listDietEntries(
      uid, dayKeyFor(date, offsetMinutes));
  return {
    plan,
    dietDay,
    eaten: new Set(entries.filter((e) => e.eaten).map((e) => e.mealId)),
  };
}

const TODAY_TOOL = {
  name: "get_today",
  description:
    "A composed snapshot of 'today' in the user's own timezone: the date, " +
    "today's diet plan (which meals are eaten, target-vs-consumed nutrition " +
    "totals, and whether those figures are estimated), and today's " +
    "workout(s).",
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
    const [workouts, dietDay] = await Promise.all([
      store.listWorkouts(uid, {fromMs, toMs}),
      loadDietDay(store, uid, now, offsetMinutes),
    ]);

    const {plan, dietDay: day, eaten} = dietDay;
    let diet = null;
    if (plan && day) {
      diet = {
        planName: plan.name,
        dayLabel: day.label,
        nutrition: adherenceFor(day.meals, eaten),
        meals: day.meals.map((m) => mealSummary(m, eaten)),
      };
    }

    // `diet` leads the payload deliberately. Tool results are capped at
    // `maxToolResultChars` and truncated from the END, so whatever is
    // serialized last is what disappears on a rich plan — nutrition is the
    // one block that must never be silently half-delivered.
    return {
      date: dayKeyFor(now, offsetMinutes),
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
    "and target-vs-consumed nutrition totals. Every figure carries an " +
    "`estimated` flag: true means it was AI-estimated when the plan was " +
    "imported, not stated by the plan itself. day: optional 'yyyy-MM-dd'.",
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

    const {plan, dietDay, eaten} =
      await loadDietDay(store, uid, date, dateOffset);
    const dateKey = dayKeyFor(date, dateOffset);
    if (!plan) return {date: dateKey, plan: null};
    if (!dietDay) return {date: dateKey, plan: plan.name, day: null};

    return {
      date: dateKey,
      plan: plan.name,
      day: dietDay.label,
      nutrition: adherenceFor(dietDay.meals, eaten),
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
