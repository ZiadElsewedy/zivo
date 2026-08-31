import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's language, as the user chose it — Arabic, English, or *follow the
/// phone* (null).
///
/// Device-local on purpose, like [DriveConnectionStore]: which language you
/// read the app in is a property of the phone in your hand, not of the account,
/// and syncing it would mean a sign-in on a borrowed device silently changing
/// the language.
///
/// Held as a [ValueNotifier] so `ZivoApp` can rebuild its `MaterialApp` on a
/// change without pulling in a state-management package (see AGENTS.md's
/// "no new foundational framework" rule).
class LocaleController {
  LocaleController({Locale? initial}) : locale = ValueNotifier<Locale?>(initial);

  static const _key = 'zivo.locale';

  /// The chosen locale, or **null** meaning "match the phone" — which is the
  /// default, and is why this is nullable rather than defaulting to English.
  final ValueNotifier<Locale?> locale;

  /// Reads the stored choice. Call once at startup; a failure to reach
  /// preferences leaves the app on the device locale rather than throwing.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_key);
      locale.value = code == null ? null : Locale(code);
    } catch (_) {
      locale.value = null;
    }
  }

  /// Sets the language. Pass null for "match my phone".
  Future<void> set(Locale? value) async {
    locale.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, value.languageCode);
      }
    } catch (_) {
      // The in-memory choice still applies for this session.
    }
  }

  void dispose() => locale.dispose();
}
