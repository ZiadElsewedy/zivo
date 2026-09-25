/**
 * Planned vs actual training days — the Node mirror of
 * `lib/features/workout/domain/training_days.dart`
 * (`classifyTrainingDayRecords` + `summarizeTrainingDays`), pinned to it by
 * the shared golden vectors in `test/fixtures/training_days_vectors.json`
 * (both suites run them).
 *
 * A split is a ROTATION, not a weekday calendar, so what was planned on a day
 * is derived: a rest slot sits after the workout it follows ("Lower → Rest →
 * Push"), so the day(s) right after training such a workout are PLANNED REST;
 * every other day has a workout due, and the rotation waits for it.
 *
 * Actual: a qualifying session that day (trained), the user's explicit rest
 * choice (a `trainingDayMarks` doc with reason `rest`), or nothing.
 *
 * "Missed" needs a plan that spells out its rest days. On a pure rotation an
 * unlogged day is `unscheduled` — the rest it assumes — never a failure.
 *
 * Works on day keys ("yyyy-MM-dd", the user's local calendar) and day ids
 * only. Pure, so it runs under `node --test`.
 */

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * @param {string} key "yyyy-MM-dd"
 * @return {number} UTC ms of that calendar day.
 */
function keyToMs(key) {
  const [y, m, d] = key.split("-").map(Number);
  return Date.UTC(y, m - 1, d);
}

/**
 * @param {number} ms
 * @return {string}
 */
function msToKey(ms) {
  return new Date(ms).toISOString().slice(0, 10);
}

/**
 * @param {string} key
 * @param {number} n
 * @return {string}
 */
function addDays(key, n) {
  return msToKey(keyToMs(key) + n * DAY_MS);
}

/**
 * @param {string} a
 * @param {string} b
 * @return {number} Calendar days from a to b.
 */
function daysBetween(a, b) {
  return Math.round((keyToMs(b) - keyToMs(a)) / DAY_MS);
}

/**
 * @param {!Array<!Object>} days
 * @return {!Array<!Object>} Sorted by `order`.
 */
function sortedDays(days) {
  return (Array.isArray(days) ? days : []).slice()
      .sort((a, b) => (a.order || 0) - (b.order || 0));
}

/**
 * @param {!Object} day
 * @return {boolean}
 */
function isRest(day) {
  return day && day.type === "rest";
}

/**
 * `WorkoutPlan.nextDay`: the cursor's day, or the first workout after it
 * when that slot is rest. Never a rest day.
 * @param {!Array<!Object>} days
 * @param {number} cycleCursor
 * @return {?Object}
 */
function nextWorkoutDay(days, cycleCursor) {
  const sorted = sortedDays(days);
  if (!sorted.length) return null;
  let start = sorted.findIndex((d) => d.order === cycleCursor);
  if (start < 0) start = 0;
  for (let i = 0; i < sorted.length; i++) {
    const day = sorted[(start + i) % sorted.length];
    if (!isRest(day)) return day;
  }
  return null;
}

/**
 * `WorkoutPlan.restDaysAfter`.
 * @param {!Array<!Object>} days
 * @param {string} dayId
 * @return {number}
 */
function restDaysAfter(days, dayId) {
  const sorted = sortedDays(days);
  const index = sorted.findIndex((d) => d.id === dayId);
  if (index < 0) return 0;
  let count = 0;
  for (let i = 1; i < sorted.length; i++) {
    if (!isRest(sorted[(index + i) % sorted.length])) break;
    count++;
  }
  return count;
}

/**
 * `WorkoutPlan.workoutAfter`.
 * @param {!Array<!Object>} days
 * @param {string} dayId
 * @return {?Object}
 */
function workoutAfter(days, dayId) {
  const sorted = sortedDays(days);
  const index = sorted.findIndex((d) => d.id === dayId);
  if (index < 0) return null;
  for (let i = 1; i <= sorted.length; i++) {
    const day = sorted[(index + i) % sorted.length];
    if (!isRest(day)) return day;
  }
  return null;
}

/**
 * Classifies every day from `from` (clamped to the plan's creation day)
 * through `today`, oldest first.
 *
 * @param {{
 *   plan: {createdDay: string, cycleCursor: number, days: !Array<!Object>},
 *   trainedDayIds: !Object<string, !Array<string>>,
 *   userRestDays: !Array<string>,
 *   from: string,
 *   today: string,
 * }} args
 * @return {!Array<{day: string, planned: string, outcome: string,
 *   dueDayId: ?string, trainedDayIds: !Array<string>}>}
 */
function classifyTrainingDayRecords({plan, trainedDayIds = {},
  userRestDays = [], from, today}) {
  const days = sortedDays(plan && plan.days);
  const workouts = days.filter((d) => !isRest(d));
  if (!workouts.length) return [];
  let start = from;
  if (plan.createdDay && start < plan.createdDay) start = plan.createdDay;
  if (start > today) return [];

  const workoutIds = new Set(workouts.map((d) => d.id));
  const anchors = new Map();
  for (const [day, ids] of Object.entries(trainedDayIds)) {
    const own = (ids || []).filter((id) => workoutIds.has(id));
    if (own.length) anchors.set(day, own[own.length - 1]);
  }
  const anchorDays = [...anchors.keys()].sort();
  const latestAnchor = anchorDays.length ? anchorDays[anchorDays.length - 1] :
    null;
  const schedulesRest = days.some(isRest);
  const chosen = new Set(userRestDays);
  const next = nextWorkoutDay(days, plan.cycleCursor);

  const records = [];
  let a = -1;
  for (let day = start; day <= today; day = addDays(day, 1)) {
    while (a + 1 < anchorDays.length && anchorDays[a + 1] < day) a++;
    const previous = a < 0 ? null : anchorDays[a];

    let planned = "workout";
    let due = null;
    if (previous !== null) {
      const lastId = anchors.get(previous);
      const gap = daysBetween(previous, day);
      if (gap >= 1 && gap <= restDaysAfter(days, lastId)) {
        planned = "rest";
      } else {
        const d = previous === latestAnchor ? next :
          workoutAfter(days, lastId);
        due = d ? d.id : null;
      }
    } else {
      const d = latestAnchor === null ? next : workouts[0];
      due = d ? d.id : null;
    }

    const trainedIds = trainedDayIds[day] || [];
    const trained = trainedIds.length > 0;
    let outcome;
    if (planned === "rest") {
      outcome = trained ? "extraWorkout" : "plannedRest";
    } else if (trained) {
      outcome = "completed";
    } else if (chosen.has(day)) {
      outcome = "userRest";
    } else if (day === today) {
      outcome = "pending";
    } else {
      outcome = schedulesRest ? "missed" : "unscheduled";
    }
    records.push({
      day,
      planned,
      outcome,
      dueDayId: planned === "workout" ? due : null,
      trainedDayIds: trainedIds.slice(),
    });
  }
  return records;
}

/**
 * @param {number} v
 * @return {number}
 */
function round2(v) {
  return Math.round(v * 100) / 100;
}

/**
 * `summarizeTrainingDays`: planned vs actual over the records.
 * @param {{days: !Array<!Object>}} plan
 * @param {!Array<!Object>} records Oldest first.
 * @return {!Object}
 */
function summarizeTrainingDays(plan, records) {
  const count = (o) => records.filter((r) => r.outcome === o).length;
  const completed = count("completed");
  const missed = count("missed");
  const userRest = count("userRest");
  const extra = count("extraWorkout");
  const judged = records.filter((r) => r.outcome !== "pending").length;
  const days = sortedDays(plan && plan.days);
  const schedulesRest = days.some(isRest);
  const workoutCount = days.filter((d) => !isRest(d)).length;

  const skipped = {};
  for (const r of records) {
    if (r.outcome !== "userRest" && r.outcome !== "missed") continue;
    if (r.dueDayId) skipped[r.dueDayId] = (skipped[r.dueDayId] || 0) + 1;
  }

  const weeks = [];
  const isTrained = (r) =>
    r.outcome === "completed" || r.outcome === "extraWorkout";
  for (let end = records.length; end > 0; end -= 7) {
    const chunk = records.slice(Math.max(0, end - 7), end);
    const n = (test) => chunk.filter(test).length;
    weeks.unshift({
      start: chunk[0].day,
      trainedDays: n(isTrained),
      userRestDays: n((r) => r.outcome === "userRest"),
      missedDays: n((r) => r.outcome === "missed"),
      plannedRestDays: n((r) => r.outcome === "plannedRest"),
    });
  }

  return {
    days: judged,
    schedulesRest,
    plannedWorkouts: schedulesRest ? completed + missed + userRest : null,
    completed,
    missed: schedulesRest ? missed : null,
    userRest,
    plannedRest: count("plannedRest"),
    extraWorkouts: extra,
    unscheduled: count("unscheduled"),
    trainingDaysPerWeek: judged === 0 ? 0 :
      round2((completed + extra) * 7 / judged),
    plannedTrainingDaysPerWeek: schedulesRest && days.length > 0 ?
      round2(workoutCount * 7 / days.length) : null,
    skippedByDayId: skipped,
    weeks,
  };
}

module.exports = {
  classifyTrainingDayRecords,
  summarizeTrainingDays,
  nextWorkoutDay,
  restDaysAfter,
  workoutAfter,
  addDays,
  daysBetween,
};
