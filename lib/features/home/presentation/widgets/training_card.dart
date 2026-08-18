import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../workout/domain/workout.dart';
import '../../../workout/domain/workout_format.dart';
import 'common.dart';
import 'hue.dart';

/// Today's training, reflected from what was actually logged — a Pulse card.
/// No "Start" affordance: this reports what happened, not a plan.
class TrainingCard extends StatelessWidget {
  const TrainingCard(this.workout, {super.key});

  final Workout workout;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.pulseWash, AppColors.card],
        stops: [0.0, 0.85],
      ),
      borderColor: AppColors.pulse.withValues(alpha: 0.14),
      washShadow: const [
        BoxShadow(
          color: Color(0x0F0A8F63),
          blurRadius: 4,
          offset: Offset(0, 2),
        ),
        BoxShadow(
          color: Color(0x420A8F63),
          blurRadius: 34,
          spreadRadius: -18,
          offset: Offset(0, 16),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeaderRow(hue: ZHue.pulse, label: 'Training'),
          const SizedBox(height: AppSpacing.m + 1),
          Text(workout.title, style: AppText.cardTitle),
          const SizedBox(height: 6),
          Text(workout.summary, style: AppText.body),
          const SizedBox(height: 18),
          Text(
            workoutMeta(workout),
            style: AppText.meta.copyWith(color: AppColors.pulseText),
          ),
        ],
      ),
    );
  }
}
