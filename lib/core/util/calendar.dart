/// Calendar-day arithmetic that survives a daylight-saving transition.
///
/// **The rule: never do calendar maths with `Duration`.** A `Duration` is an
/// exact span of absolute time; a calendar day is not. On the day a zone
/// shifts, the two disagree by an hour, and every "walk back one day" loop
/// written as `day.subtract(const Duration(days: 1))` silently steps to
/// 23:00 or 01:00 of some other day — which then matches nothing in a set
/// keyed by local midnights.
///
/// That is not hypothetical. In `Africa/Cairo` (the owner's zone), the day
/// streak used to zero itself twice a year:
///
/// ```text
/// 2026-04-25 00:00  −Duration(days: 1)→  2026-04-23 23:00   // 24 Apr skipped
/// 2026-10-30 00:00  −Duration(days: 1)→  2026-10-29 01:00   // ≠ midnight
/// ```
///
/// Everything here goes through the `DateTime(y, m, d + n)` constructor
/// (which normalises by *calendar* rules) or through a UTC ordinal (which has
/// no DST at all), so the same date always produces the same key no matter
/// what the zone did that night.
///
/// A second hazard this closes: on a spring-forward day local midnight may
/// not exist, and `DateTime(2026, 4, 24)` in Cairo resolves to `01:00`. That
/// is fine — and safe — precisely *because* every producer and every consumer
/// of a day key funnels through [startOfDay], so both sides land on the same
/// instant. Construct a day key any other way and that guarantee is gone.
library;

/// Local midnight of [d]'s calendar day — the canonical key for "the day this
/// happened on". On a spring-forward day where midnight does not exist, this
/// is the first instant that does; see the library note.
DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// [d]'s calendar day shifted by [days], as a day key.
///
/// Built on the `DateTime` constructor's own calendar normalisation, so it
/// crosses month, year and DST boundaries by counting *dates*, never hours.
/// Negative [days] walks backwards.
DateTime addCalendarDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// Whole calendar days from [from] to [to] — positive when [to] is later.
///
/// Counts dates, not elapsed time: a 23-hour spring-forward day and a 25-hour
/// autumn one are both exactly 1. Computed through a UTC ordinal because UTC
/// never shifts, so the subtraction is exact by construction rather than by
/// rounding.
int calendarDaysBetween(DateTime from, DateTime to) =>
    _dayOrdinal(to) - _dayOrdinal(from);

/// Days since the Unix epoch for [d]'s calendar date. UTC-based on purpose —
/// the point is to strip the zone, not to represent an instant.
int _dayOrdinal(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// Whether [a] and [b] fall on the same calendar day.
bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Local midnight of the Monday starting [d]'s week.
DateTime startOfWeek(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

/// [d]'s week shifted by [weeks], as a week key. Same contract as
/// [addCalendarDays] — dates, not hours.
DateTime addCalendarWeeks(DateTime d, int weeks) =>
    addCalendarDays(startOfWeek(d), weeks * DateTime.daysPerWeek);

/// `yyyy-MM-dd` for [d]'s calendar date — the document id for anything stored
/// one-per-day (training day marks, sleep nights). Stable across zones because
/// it carries no time at all.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Parses a [dayKey] back to a local day key, or null if it isn't one.
/// Tolerant of a stored id that was written by something other than
/// [dayKey] — a malformed id reads as "no such day", never as a crash.
DateTime? dayFromKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final parsed = DateTime(year, month, day);
  // Rejects 2026-02-31, which the constructor would happily roll into March.
  if (parsed.month != month || parsed.day != day) return null;
  return parsed;
}
