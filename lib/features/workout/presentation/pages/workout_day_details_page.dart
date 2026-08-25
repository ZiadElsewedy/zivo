import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/planned_exercise.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_plan_format.dart';

/// What "today's workout" actually is: one focused page for a single
/// [WorkoutDay] of [plan] — every exercise with its collapsed set summary,
/// plus the day's notes — so tapping the Training card answers "what am I
/// training?" before a single set is logged. Read-only by design; starting
/// the session stays on the card's own CTA.
class WorkoutDayDetailsPage extends StatelessWidget {
  const WorkoutDayDetailsPage({super.key, required this.plan, required this.day});

  final WorkoutPlan plan;
  final WorkoutDay day;

  @override
  Widget build(BuildContext context) {
    final exercises = [...day.exercises]..sort((a, b) => a.order.compareTo(b.order));
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.1),
            radius: 1.15,
            colors: [Color(0xFF182016), AppColors.ground, Color(0xFF0E0B08)],
            stops: [0.0, 0.52, 1.0],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
            children: [
              Row(
                children: [
                  PressableScale(
                    child: Tooltip(
                      message: 'Back',
                      child: InkWell(
                        onTap: () => Navigator.of(context).maybePop(),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceRaised,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.hairline2),
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            size: 18,
                            color: AppColors.ink2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      plan.name,
                      style: AppText.meta.copyWith(color: AppColors.ink3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              RiseIn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(day.label, style: AppText.greeting.copyWith(fontSize: 30)),
                    const SizedBox(height: 6),
                    Text(
                      workoutDayMeta(day),
                      style: AppText.meta.copyWith(color: AppColors.pulseText),
                    ),
                    if (day.notes != null && day.notes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        day.notes!,
                        style: AppText.body.copyWith(
                          fontSize: 14,
                          height: 1.4,
                          color: AppColors.ink2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 22),
              for (final (i, exercise) in exercises.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RiseIn(
                    delay: Duration(milliseconds: 40 * (i + 1).clamp(0, 8)),
                    child: _PlannedExerciseCard(exercise: exercise),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One planned movement — name, meta line ("3 sets · Chest"), optional
/// notes, and one collapsed line per distinct set spec ("3 × 8–10 · 60kg ·
/// rest 1:30"). Same visual language as the live session's details page.
class _PlannedExerciseCard extends StatelessWidget {
  const _PlannedExerciseCard({required this.exercise});

  final PlannedExercise exercise;

  @override
  Widget build(BuildContext context) {
    final sets = [...exercise.sets]..sort((a, b) => a.order.compareTo(b.order));
    final setLines = collapsedSetSummaries(sets);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.name,
                  style: AppText.rowTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                plannedExerciseMeta(exercise),
                style: AppText.meta.copyWith(color: AppColors.pulse),
              ),
            ],
          ),
          if (exercise.notes != null && exercise.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              exercise.notes!,
              style: AppText.body.copyWith(
                fontSize: 13,
                color: AppColors.ink2,
              ),
            ),
          ],
          const SizedBox(height: 10),
          for (final line in setLines)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  const _SetDot(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      line,
                      style: AppText.meta.copyWith(
                        color: AppColors.ink2,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SetDot extends StatelessWidget {
  const _SetDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      margin: const EdgeInsets.only(top: 2),
      decoration: const BoxDecoration(
        color: AppColors.pulse,
        shape: BoxShape.circle,
      ),
    );
  }
}
