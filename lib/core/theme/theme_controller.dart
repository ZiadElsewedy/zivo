import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's skin, as the user chose it — dark, light, or *follow the phone*.
///
/// Device-local on purpose, exactly like [LocaleController]: whether you read
/// ZIVO in the dark is a property of the phone in your hand and the room you
/// are in, not of the account. Syncing it would mean a sign-in on a borrowed
/// device silently re-skinning it, and a phone that is in a gym at 6am and a
/// bed at 11pm has a better answer for this than a server does.
///
/// Held as a [ValueNotifier] so `ZivoApp` can rebuild its `MaterialApp` on a
/// change without pulling in a state-management package (see AGENTS.md's
/// "no new foundational framework" rule).
class ThemeController {
  ThemeController({ThemeMode initial = defaultMode})
    : mode = ValueNotifier<ThemeMode>(initial);

  static const _key = 'zivo.themeMode';

  /// **Dark, not `system`.**
  ///
  /// ZIVO was a dark-only app for its whole life, and its near-black ground is
  /// part of the identity rather than a preference (ADR-006). Defaulting to
  /// `system` would have re-skinned every existing install on the update that
  /// shipped this, without anyone asking for it — a new setting should be an
  /// offer, not a change. Someone who wants the phone to decide can say so,
  /// once, and this remembers it.
  static const defaultMode = ThemeMode.dark;

  /// The chosen mode. [ThemeMode.system] means "match the phone".
  final ValueNotifier<ThemeMode> mode;

  /// Reads the stored choice. Call once at startup; a failure to reach
  /// preferences leaves the app on [defaultMode] rather than throwing.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      mode.value = _parse(prefs.getString(_key));
    } catch (_) {
      mode.value = defaultMode;
    }
  }

  /// Sets the skin. Pass [ThemeMode.system] for "match my phone".
  Future<void> set(ThemeMode value) async {
    mode.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.name);
    } catch (_) {
      // The in-memory choice still applies for this session.
    }
  }

  /// Stored by `name`, so the string on disk is an id and never carries copy
  /// (the same rule the domain enums follow). An unknown or absent value —
  /// a downgrade, a corrupted preference — falls back rather than throwing.
  static ThemeMode _parse(String? stored) => switch (stored) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => defaultMode,
  };

  void dispose() => mode.dispose();
}
