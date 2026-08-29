const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "THU 27 AUG" — **the** page date caption, used by every surface that wears
/// one (Today's header, the Hub's).
///
/// Short and all-caps on purpose: it's a mono micro-caption, on Today sitting
/// under a 54px hero clock, where a full "Thursday · 27 August" would fight
/// the line it's tucked beneath. There used to be a second, long-form
/// `formatTodayDate` as well, so the same element changed shape between Today
/// and the Hub; one caption, one formatter.
String formatTodayShort(DateTime now) =>
    '${_weekdays[now.weekday - 1].substring(0, 3)} ${now.day} '
            '${_months[now.month - 1].substring(0, 3)}'
        .toUpperCase();

/// "Morning, Ziad" (time-of-day derived from [now]'s hour) — or a nameless
/// "Good morning" when [name] is null/blank. Uses only the first word of a
/// multi-word [name].
String greetingFor(DateTime now, String? name) {
  final timeOfDay = switch (now.hour) {
    < 12 => 'Morning',
    < 18 => 'Afternoon',
    _ => 'Evening',
  };
  final first = _firstName(name);
  if (first == null) return 'Good $timeOfDay';
  return '$timeOfDay, $first';
}

String? _firstName(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final words = trimmed.split(RegExp(r'\s+'));
  return words.length > 1 ? words.first : trimmed;
}
