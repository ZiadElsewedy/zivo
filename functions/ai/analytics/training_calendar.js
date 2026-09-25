/**
 * Calendar adherence, derived from sessions alone — "did the user train on
 * this calendar day?". Deliberately separate from workout PROGRESSION:
 *
 *   progression: the rotation advances only when a workout is completed
 *                (the app's `WorkoutPlan.advanceToAfterDay`). A day without
 *                training creates nothing and moves nothing — the same
 *                workout is still pending the next day.
 *   calendar:    each day either has a qualifying session (active) or not
 *                (inactive). An inactive day is just that: no session. It is
 *                never a "rest day", planned or otherwise — ZIVO has no such
 *                concept — and it never touches the rotation.
 *
 * "Trained" mirrors the app's `qualifiesForStreak`
 * (`lib/features/workout/domain/training_streak.dart`): a completed or still
 * running session with at least one completed working set, bucketed by
 * `completedAt ?? startedAt` on the user's local calendar.
 *
 * Works on day keys ("yyyy-MM-dd") only. Pure, so it runs under `node --test`.
 */

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * @param {string} key
 * @return {number}
 */
function keyToMs(key) {
  const [y, m, d] = key.split("-").map(Number);
  return Date.UTC(y, m - 1, d);
}

/**
 * @param {string} key
 * @param {number} n
 * @return {string}
 */
function addDays(key, n) {
  return new Date(keyToMs(key) + n * DAY_MS).toISOString().slice(0, 10);
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
 * Whether a session counts as a day trained (`qualifiesForStreak`).
 * @param {!Object} s
 * @return {boolean}
 */
function qualifiesAsTrainingDay(s) {
  if (s.status !== "completed" && s.status !== "active") return false;
  return (s.exercises || []).some((e) => (e.sets || []).some((set) =>
    set.outcome === "completed" && set.type !== "warmup"));
}

/**
 * The calendar over `[from, today]`, clamped to the first day the user ever
 * trained (days before their history began are not "inactive", they are
 * before ZIVO knew them).
 *
 * @param {{sessionsByDay: !Object<string, number>, from: string,
 *   today: string}} args `sessionsByDay`: day key → qualifying sessions.
 * @return {?Object} Null when there is no training history at all.
 */
function trainingCalendar({sessionsByDay, from, today}) {
  const trainedDays = Object.keys(sessionsByDay)
      .filter((d) => d <= today).sort();
  if (!trainedDays.length) return null;
  const start = trainedDays[0] > from ? trainedDays[0] : from;

  const days = [];
  for (let day = start; day <= today; day = addDays(day, 1)) {
    days.push({day, sessions: sessionsByDay[day] || 0});
  }
  const todayTrained = (sessionsByDay[today] || 0) > 0;
  // Today is still open: it is not inactive until it is over.
  const judged = todayTrained ? days : days.filter((d) => d.day !== today);
  const active = judged.filter((d) => d.sessions > 0);
  const inactive = judged.filter((d) => d.sessions === 0);
  const last = trainedDays[trainedDays.length - 1];

  const weeks = [];
  for (let end = days.length; end > 0; end -= 7) {
    const chunk = days.slice(Math.max(0, end - 7), end);
    weeks.unshift({
      start: chunk[0].day,
      activeDays: chunk.filter((d) => d.sessions > 0).length,
      sessions: chunk.reduce((n, d) => n + d.sessions, 0),
    });
  }

  return {
    from: start,
    to: today,
    daysJudged: judged.length,
    activeDays: active.length,
    inactiveDays: inactive.length,
    inactiveDates: inactive.map((d) => d.day),
    trainingSessions: days.reduce((n, d) => n + d.sessions, 0),
    trainedToday: todayTrained,
    trainingDaysPerWeek: judged.length === 0 ? 0 :
      Math.round(active.length * 7 / judged.length * 100) / 100,
    lastTrainedDay: last,
    daysSinceLastTraining: daysBetween(last, today),
    weeks,
  };
}

module.exports = {trainingCalendar, qualifiesAsTrainingDay, addDays};
