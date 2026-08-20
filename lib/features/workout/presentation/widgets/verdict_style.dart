import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/progress_comparison.dart';

/// The icon/color/word for a [ProgressVerdict] — shared so the live session's
/// set-level badge and the analysis page's exercise-level badge read as the
/// same visual language.
(IconData, Color, String) verdictStyle(ProgressVerdict verdict) => switch (verdict) {
  ProgressVerdict.progressing => (Icons.trending_up_rounded, AppColors.pulse, 'Progressing'),
  ProgressVerdict.matched => (Icons.horizontal_rule_rounded, AppColors.ink3, 'Matched'),
  ProgressVerdict.down => (Icons.trending_down_rounded, AppColors.flare, 'Down'),
};
