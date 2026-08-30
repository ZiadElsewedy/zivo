/**
 * Pure date helpers shared by the AI gateway and tool registry. No
 * Firestore/SDK dependency, so this stays importable from offline
 * `node --test` runs.
 *
 * **Whose "today"?** Cloud Functions run in UTC, but the app writes
 * `dietEntries.dayKey` from the *device's local* calendar date
 * (`lib/features/diet/data/firestore_diet_repository.dart`). Computing the
 * server's own "today" therefore disagreed with the client's for every user
 * east or west of UTC — a UTC+3 user asking the coach anything between local
 * 00:00 and 03:00 got yesterday's diet entries and yesterday's weekday plan
 * slot while the screen showed today.
 *
 * So every function here takes an optional `offsetMinutes` — the client's
 * `DateTime.now().timeZoneOffset` in minutes, forwarded by `aiChat` — and
 * resolves the calendar date in the USER's timezone when given. Omitting it
 * keeps the old server-local behaviour, which is what the tests and any
 * caller without a client clock still use.
 */

const MINUTE_MS = 60 * 1000;

/**
 * Whether `offsetMinutes` is a usable client UTC offset. Never trust client
 * input: anything outside the real-world range (UTC-12:00 .. UTC+14:00, and
 * always a whole number of minutes) is discarded in favour of server-local.
 * @param {*} offsetMinutes
 * @return {boolean}
 */
function isUsableOffset(offsetMinutes) {
  return Number.isInteger(offsetMinutes) &&
    offsetMinutes >= -12 * 60 && offsetMinutes <= 14 * 60;
}

/**
 * `date` shifted so that reading it with `getUTC*` yields the user's local
 * wall-clock fields. Null when no usable offset was supplied.
 * @param {!Date} date
 * @param {*} offsetMinutes
 * @return {?Date}
 */
function asLocalWallClock(date, offsetMinutes) {
  if (!isUsableOffset(offsetMinutes)) return null;
  return new Date(date.getTime() + offsetMinutes * MINUTE_MS);
}

/**
 * The instant at which the user's local wall-clock midnight of
 * `y-m-d` occurs, in epoch ms.
 * @param {number} y
 * @param {number} m 1-12
 * @param {number} d
 * @param {number} offsetMinutes
 * @return {number}
 */
function instantOfLocalMidnight(y, m, d, offsetMinutes) {
  return Date.UTC(y, m - 1, d) - offsetMinutes * MINUTE_MS;
}

/**
 * 'yyyy-MM-dd' for `date` in the user's timezone (or the server's, when no
 * offset is given), mirroring the Flutter client's `dayKey()`
 * (`lib/features/diet/data/firestore_diet_repository.dart`).
 * @param {Date} date
 * @param {number=} offsetMinutes Client UTC offset in minutes.
 * @return {string}
 */
function dayKeyFor(date, offsetMinutes) {
  const local = asLocalWallClock(date, offsetMinutes);
  const y = local ? local.getUTCFullYear() : date.getFullYear();
  const m = local ? local.getUTCMonth() + 1 : date.getMonth() + 1;
  const d = local ? local.getUTCDate() : date.getDate();
  return `${y.toString().padStart(4, "0")}-` +
    `${m.toString().padStart(2, "0")}-${d.toString().padStart(2, "0")}`;
}

/**
 * Midnight at the start of `date`'s calendar day, as a Date. With an offset
 * this is the *instant* of the user's local midnight; without one it stays
 * the server's local midnight (legacy behaviour).
 * @param {Date} date
 * @param {number=} offsetMinutes
 * @return {Date}
 */
function startOfDay(date, offsetMinutes) {
  const local = asLocalWallClock(date, offsetMinutes);
  if (!local) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
  }
  return new Date(instantOfLocalMidnight(
      local.getUTCFullYear(), local.getUTCMonth() + 1, local.getUTCDate(),
      offsetMinutes));
}

/**
 * `date`'s weekday remapped to `DateTime.weekday` (1=Mon..7=Sun), matching
 * the Flutter client's convention (`lib/features/diet/domain/diet_day.dart`),
 * resolved in the user's timezone when an offset is given.
 * @param {Date} date
 * @param {number=} offsetMinutes
 * @return {number}
 */
function isoWeekday(date, offsetMinutes) {
  const local = asLocalWallClock(date, offsetMinutes);
  const day = local ? local.getUTCDay() : date.getDay();
  return day === 0 ? 7 : day;
}

/**
 * The `[fromMs, toMs)` range covering `date`'s calendar day.
 * @param {Date} date
 * @param {number=} offsetMinutes
 * @return {{fromMs: number, toMs: number}}
 */
function dayRangeMs(date, offsetMinutes) {
  const start = startOfDay(date, offsetMinutes);
  if (!isUsableOffset(offsetMinutes)) {
    const end = new Date(start);
    end.setDate(end.getDate() + 1);
    return {fromMs: start.getTime(), toMs: end.getTime()};
  }
  const local = asLocalWallClock(date, offsetMinutes);
  const toMs = instantOfLocalMidnight(
      local.getUTCFullYear(), local.getUTCMonth() + 1, local.getUTCDate() + 1,
      offsetMinutes);
  return {fromMs: start.getTime(), toMs};
}

/**
 * The `[fromMs, toMs)` range covering `date`'s Monday-to-Sunday week.
 * @param {Date} date
 * @param {number=} offsetMinutes
 * @return {{fromMs: number, toMs: number}}
 */
function weekRangeMs(date, offsetMinutes) {
  const weekdayIndex = isoWeekday(date, offsetMinutes) - 1;
  if (!isUsableOffset(offsetMinutes)) {
    const start = startOfDay(date);
    start.setDate(start.getDate() - weekdayIndex);
    const end = new Date(start);
    end.setDate(end.getDate() + 7);
    return {fromMs: start.getTime(), toMs: end.getTime()};
  }
  const local = asLocalWallClock(date, offsetMinutes);
  const y = local.getUTCFullYear();
  const m = local.getUTCMonth() + 1;
  const d = local.getUTCDate() - weekdayIndex;
  return {
    fromMs: instantOfLocalMidnight(y, m, d, offsetMinutes),
    toMs: instantOfLocalMidnight(y, m, d + 7, offsetMinutes),
  };
}

/**
 * The `[fromMs, toMs)` range covering `date`'s calendar month.
 * @param {Date} date
 * @param {number=} offsetMinutes
 * @return {{fromMs: number, toMs: number}}
 */
function monthRangeMs(date, offsetMinutes) {
  if (!isUsableOffset(offsetMinutes)) {
    const start = new Date(date.getFullYear(), date.getMonth(), 1);
    const end = new Date(date.getFullYear(), date.getMonth() + 1, 1);
    return {fromMs: start.getTime(), toMs: end.getTime()};
  }
  const local = asLocalWallClock(date, offsetMinutes);
  const y = local.getUTCFullYear();
  const m = local.getUTCMonth() + 1;
  return {
    fromMs: instantOfLocalMidnight(y, m, 1, offsetMinutes),
    toMs: instantOfLocalMidnight(y, m + 1, 1, offsetMinutes),
  };
}

const WEEKDAY_NAMES = [
  "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
];
const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June", "July", "August",
  "September", "October", "November", "December",
];

/**
 * The user's local "now" as the plain facts a coach needs to be told: the
 * date, the weekday, the time of day, and how the offset was expressed. The
 * gateway injects this into every turn — without it the model has no way at
 * all to know what day it is (nothing else in the prompt or the tool results
 * carries a date).
 * @param {!Date} date
 * @param {number=} offsetMinutes
 * @param {string=} zoneLabel A short zone name from the client ("EEST").
 * @return {{dayKey: string, weekday: string, longDate: string, time: string,
 *   zone: string, usedClientClock: boolean}}
 */
function localNowFacts(date, offsetMinutes, zoneLabel) {
  const usable = isUsableOffset(offsetMinutes);
  const local = asLocalWallClock(date, offsetMinutes);
  const y = local ? local.getUTCFullYear() : date.getFullYear();
  const mIndex = local ? local.getUTCMonth() : date.getMonth();
  const d = local ? local.getUTCDate() : date.getDate();
  const hours = local ? local.getUTCHours() : date.getHours();
  const minutes = local ? local.getUTCMinutes() : date.getMinutes();

  const sign = (usable ? offsetMinutes : 0) < 0 ? "-" : "+";
  const abs = Math.abs(usable ? offsetMinutes : 0);
  const utc = `UTC${sign}${Math.floor(abs / 60).toString().padStart(2, "0")}:` +
    `${(abs % 60).toString().padStart(2, "0")}`;
  const label = typeof zoneLabel === "string" && zoneLabel.trim() ?
    `${zoneLabel.trim()} (${utc})` : utc;

  return {
    dayKey: dayKeyFor(date, offsetMinutes),
    weekday: WEEKDAY_NAMES[isoWeekday(date, offsetMinutes) - 1],
    longDate: `${d} ${MONTH_NAMES[mIndex]} ${y}`,
    time: `${hours.toString().padStart(2, "0")}:` +
      `${minutes.toString().padStart(2, "0")}`,
    zone: label,
    usedClientClock: usable,
  };
}

/**
 * The user's own hour of day (0–23) at `date`, or null when no usable offset
 * was supplied. Null is meaningful: a coach that doesn't know whether it's
 * breakfast or bedtime should say less, not guess.
 * @param {!Date} date
 * @param {number=} offsetMinutes
 * @return {?number}
 */
function localHourAt(date, offsetMinutes) {
  const local = asLocalWallClock(date, offsetMinutes);
  return local ? local.getUTCHours() : null;
}

/**
 * Resolves which `DietDay`-shaped entry of `days` applies on `date`: the day
 * whose `weekday` matches `date`'s, else the every-day template
 * (`weekday == null`), else — if there's exactly one day — that day. Mirrors
 * `dayForDate()` in `lib/features/diet/presentation/today_diet.dart`.
 * @param {!Array<{weekday: ?number}>} days
 * @param {Date} date
 * @param {number=} offsetMinutes
 * @return {?Object}
 */
function resolveDietDay(days, date, offsetMinutes) {
  if (!days || days.length === 0) return null;
  const weekday = isoWeekday(date, offsetMinutes);
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
  localNowFacts,
  localHourAt,
  isUsableOffset,
};
