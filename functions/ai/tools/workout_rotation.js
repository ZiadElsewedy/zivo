/**
 * The workout ROTATION, server-side — the Node mirror of the rules in
 * `lib/features/workout/domain/workout_plan.dart`, so the coach changes the
 * schedule exactly the way the app's own "Change workout" sheet does.
 *
 * A split is a rotating cycle of days (Push → Pull → Legs → Push …), not a
 * weekday calendar. `cycleCursor` holds the `order` of the day that's up next
 * — "today's workout". Two ways to train something else today, and they are
 * NOT the same thing:
 *
 *   SWAP  (`swapDayOrders`, = `WorkoutPlan.swapDays`) — the two days trade
 *         places. The cursor keeps its position, so the other day is up now
 *         and the one that was due comes straight after. Nothing is lost: the
 *         cycle still covers every day exactly once.
 *   SKIP  (`cursorOnto`) — the due day is dropped from this round and the
 *         cursor moves onto the chosen day (or, with none chosen, onto the day
 *         after the due one). When that day is trained, the rotation carries
 *         on from after it — the app's `advanceToAfterDay`.
 *
 * A day may be a scheduled REST slot (`type: "rest"`). Rest is a place in
 * the calendar, not a workout: it is never "up next", never swapped, and
 * never a day to train instead (the app's `WorkoutPlan.nextDay`/`swapDays`).
 *
 * Operates on the RAW plan doc's `days` (every exercise and set kept intact)
 * and keeps `order` contiguous and 0-based, like the app's
 * `normalizeWorkoutPlanOrder`. Pure, so it runs under `node --test`.
 */

/**
 * The days sorted by `order`.
 * @param {!Array<!Object>} days
 * @return {!Array<!Object>}
 */
function sortedDays(days) {
  return (Array.isArray(days) ? days : []).slice()
      .sort((a, b) => (a.order || 0) - (b.order || 0));
}

/**
 * Whether a raw plan day is a scheduled rest slot.
 * @param {!Object} day
 * @return {boolean}
 */
function isRestDay(day) {
  return Boolean(day) && day.type === "rest";
}

/**
 * The WORKOUT that's up next — `WorkoutPlan.nextDay`: the day whose `order`
 * is the cursor (else the first day — a stale cursor never reads as
 * "nothing"), or the first workout after it when that slot is rest.
 * @param {!Array<!Object>} days
 * @param {number} cycleCursor
 * @return {?Object}
 */
function upNextDay(days, cycleCursor) {
  const sorted = sortedDays(days);
  if (!sorted.length) return null;
  let start = sorted.findIndex((d) => d.order === cycleCursor);
  if (start < 0) start = 0;
  for (let i = 0; i < sorted.length; i++) {
    const day = sorted[(start + i) % sorted.length];
    if (!isRestDay(day)) return day;
  }
  return null;
}

/**
 * The rotation as the user will meet it, starting from the day that's up
 * next: [upNext, then, then …].
 * @param {!Array<!Object>} days
 * @param {number} cycleCursor
 * @return {!Array<!Object>}
 */
function rotationFrom(days, cycleCursor) {
  const sorted = sortedDays(days);
  const head = upNextDay(days, cycleCursor);
  if (!head) return [];
  const i = sorted.indexOf(head);
  return sorted.slice(i).concat(sorted.slice(0, i));
}

/**
 * `days` with `aId` and `bId` trading `order`, re-sorted and renumbered
 * 0..n-1. Everything else on each day is untouched.
 * @param {!Array<!Object>} days
 * @param {string} aId
 * @param {string} bId
 * @return {!Array<!Object>}
 */
function swapDayOrders(days, aId, bId) {
  const a = days.find((d) => d.id === aId);
  const b = days.find((d) => d.id === bId);
  if (!a || !b || aId === bId || isRestDay(a) || isRestDay(b)) return days;
  const swapped = days.map((d) => {
    if (d.id === aId) return Object.assign({}, d, {order: b.order});
    if (d.id === bId) return Object.assign({}, d, {order: a.order});
    return d;
  });
  return sortedDays(swapped).map((d, i) => Object.assign({}, d, {order: i}));
}

/**
 * The cursor that makes `dayId` the day up next.
 * @param {!Array<!Object>} days
 * @param {string} dayId
 * @return {?number}
 */
function cursorOnto(days, dayId) {
  const day = days.find((d) => d.id === dayId);
  return day ? day.order : null;
}

/**
 * The WORKOUT that comes after `dayId` in the rotation (wrapping; rest slots
 * are passed over).
 * @param {!Array<!Object>} days
 * @param {string} dayId
 * @return {?Object}
 */
function dayAfter(days, dayId) {
  const sorted = sortedDays(days)
      .filter((d) => !isRestDay(d) || d.id === dayId);
  const i = sorted.findIndex((d) => d.id === dayId);
  if (i < 0 || sorted.length < 2) return null;
  return sorted[(i + 1) % sorted.length];
}

/**
 * The display name of a day: its label ("Push"), else its slot ("Day A").
 * @param {!Object} day
 * @return {string}
 */
function dayName(day) {
  return String((day && (day.label || day.slot)) || "").trim() || "that day";
}

/**
 * The rotation change a validated `change_workout_day` proposal means,
 * applied to the raw days + cursor. Throws (with a message the model can act
 * on) when the plan no longer matches what was proposed.
 *
 * @param {{days: !Array<!Object>, cycleCursor: number}} plan
 * @param {{mode: string, dueDayId: string, targetDayId: string}} change
 * @return {{days: !Array<!Object>, cycleCursor: number}}
 */
function applyRotationChange(plan, change) {
  const cursor = typeof plan.cycleCursor === "number" ? plan.cycleCursor : 0;
  // Resolve what's due against the doc as stored, THEN renumber — the cursor
  // is an `order`, so it only means something against the orders it was
  // saved with.
  const dueRaw = upNextDay(plan.days, cursor);
  const days = sortedDays(plan.days).map((d, i) =>
    Object.assign({}, d, {order: i}));
  const due = dueRaw ? days.find((d) => d.id === dueRaw.id) : null;
  if (!due || due.id !== change.dueDayId) {
    throw new Error("The workout that's up next changed since this was " +
      "suggested.");
  }
  if (!days.some((d) => d.id === change.targetDayId)) {
    throw new Error("That workout day isn't in your split any more.");
  }
  if (isRestDay(days.find((d) => d.id === change.targetDayId))) {
    throw new Error("That's a rest day in your split, not a workout.");
  }
  if (change.mode === "swap") {
    // The cursor stays at the same POSITION, which now holds the target.
    return {days: swapDayOrders(days, due.id, change.targetDayId),
      cycleCursor: due.order};
  }
  return {days, cycleCursor: cursorOnto(days, change.targetDayId)};
}

module.exports = {
  isRestDay,
  sortedDays,
  upNextDay,
  rotationFrom,
  swapDayOrders,
  cursorOnto,
  dayAfter,
  dayName,
  applyRotationChange,
};
