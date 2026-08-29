import 'package:flutter/material.dart';

import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_surfaces.dart';
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
  const WorkoutDayDetailsPage({
    super.key,
    required this.plan,
    required this.day,
  });

  final WorkoutPlan plan;
  final WorkoutDay day;

  @override
  Widget build(BuildContext context) {
    final exercises = [...day.exercises]
      ..sort((a, b) => a.order.compareTo(b.order));
    return TrainScreen(
      tint: TrainColors.hubTint,
      child: ListView(
        padding: EdgeInsets.fromLTRB(22, 12, 22, TrainBottomInset.of(context)),
        children: [
          // The day IS the title here; the plan it belongs to rides the
          // header's caption slot rather than taking the title line.
          TrainPageHeader(title: day.label),
          const SizedBox(height: 14),
          RiseIn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${plan.name.toUpperCase()} · '
                  '${workoutDayMeta(day).toUpperCase()}',
                  maxLines: 2,
                  style: TrainType.mono(
                    size: 11.5,
                    tracking: 0.06,
                    color: TrainColors.ink3,
                    height: 1.5,
                  ),
                ),
                if (day.notes != null && day.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    day.notes!,
                    style: TrainType.ui(
                      size: 13.5,
                      weight: FontWeight.w400,
                      height: 1.5,
                      color: TrainColors.ink2,
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
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 15),
      decoration: BoxDecoration(
        gradient: TrainColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.name,
                  style: TrainType.ui(
                    size: 15,
                    weight: FontWeight.w700,
                    color: TrainColors.inkPlain,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                plannedExerciseMeta(exercise).toUpperCase(),
                style: TrainType.mono(
                  size: 9.5,
                  tracking: 0.08,
                  color: TrainColors.green.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          if (exercise.notes != null && exercise.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              exercise.notes!,
              style: TrainType.ui(
                size: 12.5,
                weight: FontWeight.w400,
                height: 1.45,
                color: TrainColors.ink2,
              ),
            ),
          ],
          const SizedBox(height: 12),
          for (final line in setLines)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                children: [
                  const _SetDot(),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      line,
                      // A set prescription is a figure, so it reads mono.
                      style: TrainType.mono(
                        size: 12,
                        tracking: 0.02,
                        color: const Color(0xA6F4F4F0),
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
        color: TrainColors.green,
        shape: BoxShape.circle,
      ),
    );
  }
}
