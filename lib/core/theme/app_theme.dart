import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The ZIVO app theme (dark & warm, Brand System v2).
abstract final class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.ground,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.ember,
        surface: AppColors.card,
        onSurface: AppColors.ink,
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
