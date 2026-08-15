/**
 * Pure date helpers shared by the AI gateway and tool registry. No
 * Firestore/SDK dependency, so this stays importable from offline
 * `node --test` runs.
 *
 * "Today" / "this week" / "this month" are computed from the injected `now`
 * in the server's own timezone (UTC on Cloud Functions) — there is no
 * per-user timezone stored yet, matching the rest of the read-only V1 scope.
 */

/**
 * 'yyyy-MM-dd' for `date`, mirroring the Flutter client's `dayKey()`
 * (`lib/features/diet/data/firestore_diet_repository.dart`).
 * @param {Date} date
 * @return {string}
 */
function dayKeyFor(date) {
  const y = date.getFullYear().toString().padStart(4, "0");
  const m = (date.getMonth() + 1).toString().padStart(2, "0");
  const d = date.getDate().toString().padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/**
 * Midnight at the start of `date`'s calendar day.
 * @param {Date} date
 * @return {Date}
 */
function startOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

/**
 * `date`'s weekday remapped to `DateTime.weekday` (1=Mon..7=Sun), matching
 * the Flutter client's convention (`lib/features/diet/domain/diet_day.dart`).
 * @param {Date} date
 * @return {number}
 */
function isoWeekday(date) {
  const day = date.getDay();
  return day === 0 ? 7 : day;
}

/**
 * The `[fromMs, toMs)` range covering `date`'s calendar day.
 * @param {Date} date
 * @return {{fromMs: number, toMs: number}}
 */
function dayRangeMs(date) {
  const start = startOfDay(date);
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return {fromMs: start.getTime(), toMs: end.getTime()};
}

/**
 * The `[fromMs, toMs)` range covering `date`'s Monday-to-Sunday week.
 * @param {Date} date
 * @return {{fromMs: number, toMs: number}}
 */
function weekRangeMs(date) {
  const start = startOfDay(date);
  start.setDate(start.getDate() - (isoWeekday(date) - 1));
  const end = new Date(start);
  end.setDate(end.getDate() + 7);
  return {fromMs: start.getTime(), toMs: end.getTime()};
}

/**
 * The `[fromMs, toMs)` range covering `date`'s calendar month.
 * @param {Date} date
 * @return {{fromMs: number, toMs: number}}
 */
function monthRangeMs(date) {
  const start = new Date(date.getFullYear(), date.getMonth(), 1);
  const end = new Date(date.getFullYear(), date.getMonth() + 1, 1);
  return {fromMs: start.getTime(), toMs: end.getTime()};
}

/**
 * Resolves which `DietDay`-shaped entry of `days` applies on `date`: the day
 * whose `weekday` matches `date`'s, else the every-day template
 * (`weekday == null`), else — if there's exactly one day — that day. Mirrors
 * `dayForDate()` in `lib/features/diet/presentation/today_diet.dart`.
 * @param {!Array<{weekday: ?number}>} days
 * @param {Date} date
 * @return {?Object}
 */
function resolveDietDay(days, date) {
  if (!days || days.length === 0) return null;
  const weekday = isoWeekday(date);
  for (const day of days) {
    if (day.weekday === weekday) return day;
  }
  for (const day of days) {
    if (day.weekday === null || day.weekday === undefined) return day;
  }
  if (days.length === 1) return days[0];
  return null;
}

module.exports = {
  dayKeyFor,
  startOfDay,
  isoWeekday,
  dayRangeMs,
  weekRangeMs,
  monthRangeMs,
  resolveDietDay,
};
