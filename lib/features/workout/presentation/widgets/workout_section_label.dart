import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// The quiet uppercase label above each block on the Workout dashboard and its
/// Progress screen — shared so the two surfaces keep one voice.
class WorkoutSectionLabel extends StatelessWidget {
  const WorkoutSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: AppText.meta.copyWith(color: AppColors.ink3, letterSpacing: 0.8),
  );
}
