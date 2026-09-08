import 'package:flutter/material.dart';

import 'zivo_palette.dart';

/// The ZIVO app theme.
///
/// The defaults here are the app's *ground floor*: anything that doesn't paint
/// its own background or pick its own ink inherits them. They used to be the
/// warm v2 values, which quietly put a warm cast under every screen —
/// including the cool handoff ones — so a screen only looked cool where it had
/// explicitly overridden something.
abstract final class AppTheme {
  static ThemeData get dark => _of(ZivoPalette.dark);

  static ThemeData get light => _of(ZivoPalette.light);

  static ThemeData of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Both skins are the *same* theme with a different palette bound to it —
  /// there is one design system, and `MaterialApp`'s two slots are just where
  /// Flutter wants each dressing handed in (ADR-006, ADR-011).
  ///
  /// This reads [ZivoPalette] directly rather than going through
  /// `TrainColors`, because it is built to describe a skin that may not be
  /// the active one: `MaterialApp` is handed both at once.
  static ThemeData _of(ZivoPalette p) {
    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      scaffoldBackgroundColor: p.base,
      colorScheme: ColorScheme(
        brightness: p.brightness,
        primary: p.ember,
        onPrimary: p.base,
        secondary: p.green,
        onSecondary: p.base,
        error: p.ember,
        onError: p.base,
        surface: p.raised,
        onSurface: p.ink,
      ),
      splashFactory: InkRipple.splashFactory,
    );
  }
}

/// ZIVO motion tokens.
abstract final class AppMotion {
  static const Curve ease = Cubic(0.2, 0.8, 0.2, 1);
  static const Duration tap = Duration(milliseconds: 90);
  static const Duration enter = Duration(milliseconds: 550);
}
