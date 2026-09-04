import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// How ZIVO writes a date or a clock time — in the reader's own language.
///
/// ## Why this exists
///
/// Thirteen files had grown their own private copy of this. Eight declared a
/// `const _monthNames = ['Jan', 'Feb', …]` list, five a
/// `['Mon', 'Tue', …]`, and four their own `isPm ? 'PM' : 'AM'` — each
/// indexing into the table by hand. Beyond being the same table written many
/// times, every one of them was **hardcoded English**: an Arabic user reading
/// an Arabic app got "MAR 1" on their session history and "6:30 AM" on their
/// moments, because a `.arb` key can't fix a month name that was never a
/// string the translator could see.
///
/// [intl]'s [DateFormat] already knows every month, weekday and day-period
/// name in both languages. These wrappers just point it at the locale the app
/// is currently rendering in, so the same call site reads correctly in both.
///
/// ## Locale resolution
///
/// The locale comes from the [Localizations] widget above [context], matching
/// `l(context)`. It falls back to English when there is none — the same
/// fallback and the same reason: ~120 widget tests pump a page under a bare
/// `MaterialApp`, and a screen shouldn't need a localization harness to be
/// testable. In the running app `ZivoApp` always installs the delegates.
///
/// Every formatter here is **presentation only**. Do not use them to build a
/// key, an id, or anything compared against a stored value — a translated
/// month name is not a stable string. (The same trap `kAmrapLabel` exists to
/// avoid; see `workout/domain/progression.dart`.)
String _localeOf(BuildContext context) =>
    Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'en';

/// Runs [format] for the context's locale, falling back to English if `intl`
/// has no symbol data for it.
///
/// [DateFormat] throws `LocaleDataException` rather than degrading when it is
/// handed a locale it has not been initialised for. In the running app that
/// cannot happen — `GlobalMaterialLocalizations` loads the symbols for every
/// locale it serves — but a widget pumped under a hand-rolled localization
/// setup could otherwise crash a screen over a month name. Formatting a date
/// is never worth a crash.
String _format(BuildContext context, String Function(String locale) format) {
  try {
    return format(_localeOf(context));
  } on Exception {
    return format('en');
  }
}

/// CLDR separates the time from its day period with U+202F (narrow no-break
/// space) in English. The thirteen hand-rolled formatters this replaces all
/// emitted a plain space, and a good deal of the app's own copy and its widget
/// tests are written around that, so normalise it — the invisible difference
/// is not worth an invisible breakage. Arabic is unaffected (no day-period
/// separator of this kind).
String _plainSpaces(String s) => s.replaceAll('\u202f', ' ').replaceAll('\u00a0', ' ');

/// "Mar 1" — an abbreviated month with the day of the month.
String formatMonthDay(BuildContext context, DateTime date) =>
    _format(context, (l) => DateFormat.MMMd(l).format(date));

/// "MAR 1" — [formatMonthDay] for a micro-label that is set in caps.
///
/// Uppercasing is locale-aware because it has to be: Arabic has no case, so
/// this is a no-op there rather than mangling the string.
String formatMonthDayCaps(BuildContext context, DateTime date) =>
    formatMonthDay(context, date).toUpperCase();

/// "Mon" — the abbreviated weekday.
String formatWeekdayShort(BuildContext context, DateTime date) =>
    _format(context, (l) => DateFormat.E(l).format(date));

/// "Monday" — the full weekday.
String formatWeekdayFull(BuildContext context, DateTime date) =>
    _format(context, (l) => DateFormat.EEEE(l).format(date));

/// "6:30 AM" — a wall-clock time with the locale's own day period.
String formatClockTime(BuildContext context, DateTime time) =>
    _plainSpaces(_format(context, (l) => DateFormat.jm(l).format(time)));

/// "6:30:45 AM" — [formatClockTime] with seconds, for a capture timestamp.
String formatClockTimeWithSeconds(BuildContext context, DateTime time) =>
    _plainSpaces(_format(context, (l) => DateFormat.jms(l).format(time)));

/// "Mon 1 Mar · 6:30 AM" — the long form a session row leads with.
String formatWeekdayDateTime(BuildContext context, DateTime at) =>
    '${formatWeekdayDate(context, at)} · ${formatClockTime(context, at)}';

/// "6:30 AM" from minutes since midnight — the shape the workout stats pages
/// hold a usual-start-time in, where there is no [DateTime] to format.
String formatMinutesSinceMidnight(BuildContext context, int minutes) {
  final clamped = minutes % (24 * 60);
  return formatClockTime(
    context,
    DateTime(2000, 1, 1, clamped ~/ 60, clamped % 60),
  );
}

/// "Sun, Mar 1" — the weekday with an abbreviated month and day, the form a
/// session header leads with.
String formatWeekdayDate(BuildContext context, DateTime date) =>
    _format(context, (l) => DateFormat.MMMEd(l).format(date));

/// "AM" / "PM" (and "ص" / "م" in Arabic) on its own, for a clock whose numerals
/// and day period are set as separate typographic elements — Today's hero
/// clock renders the digits at 54px mono with the period beside them, so it
/// cannot use [formatClockTime]'s single string.
String formatDayPeriod(BuildContext context, DateTime time) =>
    _format(context, (l) => DateFormat('a', l).format(time));

/// "Mon" from a [DateTime.weekday] number (1 = Monday … 7 = Sunday), for the
/// pickers that hold a weekday as an int and have no date to format.
String formatWeekdayShortForIndex(BuildContext context, int weekday) {
  // 2024-01-01 was a Monday, so this maps 1…7 onto Mon…Sun.
  final anchor = DateTime(2024, 1, ((weekday - 1) % 7) + 1);
  return formatWeekdayShort(context, anchor);
}

/// "Thu, 20 August 2026" — the long, day-first stamp the photo detail panel
/// uses.
///
/// This is the one formatter here built from an explicit pattern rather than a
/// [DateFormat] skeleton. The panel reads like an EXIF record, where day-first
/// is the convention, and that ordering is a deliberate part of its design; the
/// pattern keeps the order fixed while still resolving every weekday and month
/// NAME through the locale. Everywhere else, prefer a skeleton and let the
/// locale choose the order too.
String formatFullDateLong(BuildContext context, DateTime date) =>
    _format(context, (l) => DateFormat('EEE, d MMMM y', l).format(date));

/// "Aug 20, 2026" — an abbreviated date with the year, for a date of birth or
/// any stamp that needs to be unambiguous across years.
String formatDayMonthYear(BuildContext context, DateTime date) =>
    _format(context, (l) => DateFormat.yMMMd(l).format(date));

/// The twelve full month names, in order (index 0 = January), for a picker
/// that lists months rather than formatting a date.
///
/// The fourteenth hand-rolled month table lived in the date-of-birth wheel,
/// where the names are *options* rather than part of a formatted date — so it
/// could not use any of the formatters above and had spelled the list out
/// again, in English.
List<String> monthNames(BuildContext context) => [
  for (var m = 1; m <= 12; m++)
    _format(context, (l) => DateFormat.MMMM(l).format(DateTime(2024, m))),
];
