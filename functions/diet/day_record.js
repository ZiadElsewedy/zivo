/**
 * The daily diet record — `users/{uid}/dietDays/{dayKey}` — one per calendar
 * day, derived from the three sources that already exist:
 *
 *   dietPlans   → what was PLANNED (a meal-level snapshot, frozen once the day
 *                 is past, so editing the plan never rewrites yesterday)
 *   dietEntries → which meals were ticked / skipped
 *   foodLogs    → what was actually EATEN (stays the detailed source)
 *
 * It is a READ MODEL, not a new source of truth: nothing here is typed by the
 * user, and the whole record can be rebuilt from those three at any time
 * (`day_sync.js` does exactly that on every write). It exists so history —
 * "yesterday", "this week" — is one small document per day instead of every
 * log row of every day.
 *
 * Pure and deterministic: the same inputs give the same record (no clock, no
 * I/O), so a rebuild that changes nothing writes nothing.
 */

const {buildDietState, isSupplement} = require("./state");

const SCHEMA_VERSION = 1;

/** Meal status vocabulary. */
const MealStatus = {
  EATEN: "eaten",
  MODIFIED: "modified",
  SKIPPED: "skipped",
  UNMARKED: "unmarked",
};

/**
 * @param {number} v
 * @return {number}
 */
function round1(v) {
  return Math.round(v * 10) / 10;
}

/**
 * A number's sum over `rows[field]`, or null when no row states one — the
 * "absent, not zero" rule.
 * @param {!Array<!Object>} rows
 * @param {string} field
 * @return {?number}
 */
function statedSum(rows, field) {
  let total = 0;
  let stated = false;
  for (const r of rows) {
    const v = r && r[field];
    if (typeof v === "number" && Number.isFinite(v)) {
      total += v;
      stated = true;
    }
  }
  return stated ? round1(total) : null;
}

/**
 * One planned meal as the snapshot keeps it: its totals, not its items (the
 * items of what was eaten live in `foodLogs`).
 * @param {!Object} meal A plan Meal.
 * @param {number} order
 * @return {!Object}
 */
function plannedMeal(meal, order) {
  const items = meal.items || [];
  return {
    mealId: meal.id,
    label: meal.label || "",
    order,
    isSupplement: isSupplement(meal),
    planned: {
      kcal: statedSum(items, "calories"),
      proteinG: statedSum(items, "proteinG"),
      carbsG: statedSum(items, "carbsG"),
      fatG: statedSum(items, "fatG"),
      estimated: items.some((i) => i && i.estimated === true),
      itemCount: items.length,
    },
  };
}

/**
 * The plan side of the record: taken from the current plan while the day is
 * today (or ahead), kept as-is once it is past. A past day seen for the first
 * time can only be rebuilt from the plan in force NOW — it says so.
 * @param {!Object} args
 * @return {!Object}
 */
function planSide({isPast, existing, plan, planDay, targets}) {
  if (isPast && existing && Array.isArray(existing.meals)) {
    return {
      plan: existing.plan || null,
      targets: existing.targets || null,
      plannedReconstructed: existing.plannedReconstructed === true,
      snapshot: existing.meals
          .filter((m) => m.planned)
          .map((m) => ({
            mealId: m.mealId, label: m.label, order: m.order,
            isSupplement: m.isSupplement === true, planned: m.planned,
          })),
    };
  }
  return {
    plan: plan && planDay ? {
      id: plan.id || null,
      name: plan.name || "",
      dayLabel: planDay.label || null,
    } : null,
    targets: targets ? {
      goal: targets.goal || null,
      calories: targets.calories,
      proteinG: targets.proteinG === undefined ? null : targets.proteinG,
      carbsG: targets.carbsG === undefined ? null : targets.carbsG,
      fatG: targets.fatG === undefined ? null : targets.fatG,
    } : null,
    plannedReconstructed: isPast,
    snapshot: ((planDay && planDay.meals) || []).map(plannedMeal),
  };
}

/**
 * Whether a ticked meal's materialised entries still say "exactly the plan":
 * one per planned item and the same totals. Anything else — an item removed,
 * an amount changed — is a modified meal. Judged against the SNAPSHOT, never
 * the live plan, so a frozen day keeps its verdict when the plan changes.
 * @param {!Object} planned The snapshot's `planned` block.
 * @param {!Array<!Object>} entries The meal's plannedMeal log entries.
 * @return {boolean}
 */
function matchesPlan(planned, entries) {
  if (entries.length !== planned.itemCount) return false;
  const kcal = entries.reduce((n, e) => n + (e.kcal || 0), 0);
  // Stored kcal is rounded per item; macros are stored as the plan states.
  if (planned.kcal !== null &&
      Math.abs(kcal - planned.kcal) > 0.5 * entries.length + 1e-9) {
    return false;
  }
  for (const f of ["proteinG", "carbsG", "fatG"]) {
    const sum = round1(entries.reduce((n, e) => n + (e[f] || 0), 0));
    if (planned[f] !== null && Math.abs(sum - planned[f]) > 0.05) return false;
  }
  return true;
}

/**
 * @param {!Array<!Object>} entries
 * @return {!Object}
 */
function totalsOf(entries) {
  return {
    kcal: entries.reduce((n, e) => n + (e.kcal || 0), 0),
    proteinG: round1(entries.reduce((n, e) => n + (e.proteinG || 0), 0)),
    carbsG: round1(entries.reduce((n, e) => n + (e.carbsG || 0), 0)),
    fatG: round1(entries.reduce((n, e) => n + (e.fatG || 0), 0)),
  };
}

/**
 * Builds the day's record.
 * @param {!Object} args
 * @param {string} args.dayKey 'yyyy-MM-dd' — the user's local calendar day.
 * @param {boolean} args.isPast Whether `dayKey` is before the user's today.
 * @param {?number} args.offsetMinutes The user's UTC offset, when known.
 * @param {?Object} args.plan The active plan (`{id, name, days}`), or null.
 * @param {?Object} args.planDay The plan's day for `dayKey`, or null.
 * @param {?Object} args.targets The user's targets, or null.
 * @param {!Array<!Object>} args.entries The day's dietEntries.
 * @param {!Array<!Object>} args.log The day's foodLogs.
 * @param {?Object} args.existing The stored record, when there is one.
 * @return {?Object} The record, or null when the day holds nothing at all.
 */
function buildDietDayRecord({
  dayKey, isPast, offsetMinutes, plan, planDay, targets, entries, log,
  existing,
}) {
  const side = planSide({isPast, existing, plan, planDay, targets});
  const byMeal = new Map(entries.map((e) => [e.mealId, e]));
  const snapshotIds = new Set(side.snapshot.map((m) => m.mealId));

  const meals = side.snapshot.map((m) => {
    const entry = byMeal.get(m.mealId);
    const ticks = log.filter(
        (e) => e.origin === "plannedMeal" && e.mealId === m.mealId);
    let status = MealStatus.UNMARKED;
    if (entry && entry.eaten) {
      status = ticks.length === 0 || matchesPlan(m.planned, ticks) ?
        MealStatus.EATEN : MealStatus.MODIFIED;
    } else if (entry && entry.status === MealStatus.SKIPPED) {
      status = MealStatus.SKIPPED;
    }
    const consumedHere = status === MealStatus.EATEN ||
      status === MealStatus.MODIFIED;
    return Object.assign({}, m, {
      status,
      actual: consumedHere && ticks.length ? totalsOf(ticks) : null,
    });
  });
  // A meal ticked on this day that the snapshot doesn't hold (the plan was
  // replaced since) is still part of the day — kept, without a plan side.
  for (const e of entries) {
    if (snapshotIds.has(e.mealId)) continue;
    if (!e.eaten && e.status !== MealStatus.SKIPPED) continue;
    const ticks = log.filter(
        (l) => l.origin === "plannedMeal" && l.mealId === e.mealId);
    meals.push({
      mealId: e.mealId, label: "", order: meals.length, isSupplement: false,
      planned: null,
      status: e.eaten ? MealStatus.EATEN : MealStatus.SKIPPED,
      actual: ticks.length ? totalsOf(ticks) : null,
    });
  }

  // Every log row lands in exactly one place: a ticked meal's `actual`, or
  // `unplanned` (the user's own foods, and any planned row whose meal isn't
  // ticked on this day).
  const eatenIds = new Set(meals
      .filter((m) => m.status === MealStatus.EATEN ||
        m.status === MealStatus.MODIFIED)
      .map((m) => m.mealId));
  const unplannedRows = log.filter((e) =>
    e.origin !== "plannedMeal" || !eatenIds.has(e.mealId));
  if (meals.every((m) => m.status === MealStatus.UNMARKED) &&
      log.length === 0) {
    // Nothing happened on this day. No record: "absent, not zero".
    return null;
  }

  // Consumption by the ONE rule the screen and the coach share
  // (`buildDietState`): the log when it has anything, else the planned
  // figures of ticked meals — each snapshot meal stands in as one item
  // carrying its planned totals.
  const state = buildDietState({
    dayKey,
    targets: side.targets,
    day: {meals: meals.filter((m) => m.planned).map((m) => ({
      id: m.mealId,
      label: m.label,
      items: [{
        calories: m.planned.kcal === null ? undefined : m.planned.kcal,
        proteinG: m.planned.proteinG === null ? undefined : m.planned.proteinG,
        carbsG: m.planned.carbsG === null ? undefined : m.planned.carbsG,
        fatG: m.planned.fatG === null ? undefined : m.planned.fatG,
        estimated: m.planned.estimated,
      }],
    }))},
    consumedMealIds: eatenIds,
    log,
  });
  const {basisLabel, ...consumed} = state.consumed; // eslint-disable-line

  const counted = meals.filter((m) => !m.isSupplement && m.planned);
  const count = (s) => counted.filter((m) => m.status === s).length;
  return {
    dayKey,
    schemaVersion: SCHEMA_VERSION,
    offsetMinutes: typeof offsetMinutes === "number" ? offsetMinutes : null,
    plan: side.plan,
    targets: side.targets,
    plannedReconstructed: side.plannedReconstructed,
    planned: {
      kcal: statedSum(counted.map((m) => m.planned), "kcal"),
      proteinG: statedSum(counted.map((m) => m.planned), "proteinG"),
      carbsG: statedSum(counted.map((m) => m.planned), "carbsG"),
      fatG: statedSum(counted.map((m) => m.planned), "fatG"),
    },
    meals,
    unplanned: Object.assign(totalsOf(unplannedRows),
        {count: unplannedRows.length}),
    consumed,
    adherence: {
      mealsPlanned: counted.length,
      eaten: count(MealStatus.EATEN),
      modified: count(MealStatus.MODIFIED),
      skipped: count(MealStatus.SKIPPED),
      unmarked: count(MealStatus.UNMARKED),
    },
  };
}

/**
 * The user's UTC offset in minutes, read off a doc the app wrote: its `date`
 * is the device's local midnight for `dayKey`. Null when the doc can't say —
 * a server-written doc stores UTC midnight, indistinguishable from a UTC user.
 * @param {string} dayKey
 * @param {?Date} date
 * @return {?number}
 */
function offsetFromLocalMidnight(dayKey, date) {
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) return null;
  const utcMidnight = Date.parse(`${dayKey}T00:00:00Z`);
  if (Number.isNaN(utcMidnight)) return null;
  const minutes = Math.round((utcMidnight - date.getTime()) / 60000);
  if (minutes === 0 || Math.abs(minutes) > 14 * 60) return null;
  return minutes;
}

module.exports = {
  buildDietDayRecord,
  offsetFromLocalMidnight,
  MealStatus,
  SCHEMA_VERSION,
};
