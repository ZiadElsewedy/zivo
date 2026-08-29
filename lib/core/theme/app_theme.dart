import 'package:flutter/material.dart';

import 'train_tokens.dart';

/// The ZIVO app theme.
///
/// The defaults here are the app's *ground floor*: anything that doesn't paint
/// its own background or pick its own ink inherits them. They used to be the
/// warm v2 values, which quietly put a warm cast under every screen —
/// including the cool handoff ones — so a screen only looked cool where it had
/// explicitly overridden something.
abstract final class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: TrainColors.base,
      colorScheme: const ColorScheme.dark(
        primary: TrainColors.ember,
        surface: TrainColors.raised,
        onSurface: TrainColors.ink,
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
