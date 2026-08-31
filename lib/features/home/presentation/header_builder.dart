import 'package:intl/intl.dart';

import '../../../l10n/l10n.dart';

/// "THU 27 AUG" — **the** page date caption, used by every surface that wears
/// one (Today's header, the Hub's).
///
/// Short and all-caps on purpose: it's a mono micro-caption, on Today sitting
/// under a 54px hero clock, where a full "Thursday · 27 August" would fight
/// the line it's tucked beneath. There used to be a second, long-form
/// `formatTodayDate` as well, so the same element changed shape between Today
/// and the Hub; one caption, one formatter.
///
/// Day and month names come from **`intl`, not from ZIVO's ARB files**. They
/// are calendar data, not copy: `intl` already ships them for every locale it
/// supports, translating them by hand would be work with a wrong answer at the
/// end of it, and the abbreviation rules differ per language. [localeName] is
/// the app's current locale — pass `Localizations.localeOf(context)
/// .toLanguageTag()`, which the Material delegate has already loaded date
/// symbols for. `toUpperCase` is a no-op in Arabic, which has no letter case.
/// Falls back to the default locale when [localeName]'s date symbols aren't
/// loaded. That is not defensive padding: `intl` only ships `en_US` eagerly,
/// and everything else is loaded by `GlobalMaterialLocalizations` when the app
/// resolves a locale. A widget test that pumps a page under a bare
/// `MaterialApp` has no such delegate — and a date caption is not worth
/// throwing a screen away over.
String formatTodayShort(DateTime now, [String? localeName]) {
  try {
    return DateFormat('EEE d MMM', localeName).format(now).toUpperCase();
  } on Exception {
    return DateFormat('EEE d MMM').format(now).toUpperCase();
  }
}

/// "Morning, Ziad" (time-of-day derived from [now]'s hour) — or a nameless
/// "Good morning" when [name] is null/blank. Uses only the first word of a
/// multi-word [name].
///
/// The whole phrase is one ARB key per case rather than "{greeting}, {name}":
/// Arabic attaches a name with **يا** and has no separate afternoon greeting,
/// so a template assembled from parts produces a sentence no Arabic speaker
/// would write.
String greetingFor(DateTime now, String? name, AppLocalizations strings) {
  final first = _firstName(name);
  if (first == null) {
    return switch (now.hour) {
      < 12 => strings.greetingMorning,
      < 18 => strings.greetingAfternoon,
      _ => strings.greetingEvening,
    };
  }
  return switch (now.hour) {
    < 12 => strings.greetingMorningNamed(first),
    < 18 => strings.greetingAfternoonNamed(first),
    _ => strings.greetingEveningNamed(first),
  };
}

String? _firstName(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final words = trimmed.split(RegExp(r'\s+'));
  return words.length > 1 ? words.first : trimmed;
}
