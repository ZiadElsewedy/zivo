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

/// "Saturday · 15 August" for [now]'s calendar date.
String formatTodayDate(DateTime now) =>
    '${_weekdays[now.weekday - 1]} · ${now.day} ${_months[now.month - 1]}';

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
