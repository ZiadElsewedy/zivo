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
String formatWeekdayDateTime(BuildContext context, DateTime at) => _plainSpaces(
      _format(
        context,
        (l) => '${DateFormat.MMMEd(l).format(at)} · ${DateFormat.jm(l).format(at)}',
      ),
    );

/// "6:30 AM" from minutes since midnight — the shape the workout stats pages
/// hold a usual-start-time in, where there is no [DateTime] to format.
String formatMinutesSinceMidnight(BuildContext context, int minutes) {
  final clamped = minutes % (24 * 60);
  return formatClockTime(
    context,
    DateTime(2000, 1, 1, clamped ~/ 60, clamped % 60),
  );
}
