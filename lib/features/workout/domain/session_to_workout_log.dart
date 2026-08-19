import 'exercise.dart';
import 'planned_exercise.dart';
import 'rep_target.dart';
import 'set_log.dart';
import 'workout.dart';
import 'workout_session.dart';

/// Projects a finished [WorkoutSession] onto the flat history [Workout] entity
/// ("what I did").
///
/// LOSSY BY DESIGN: the history model holds only sets × reps × weight per
/// exercise, so per-set actuals collapse to a single representative reps/weight.
/// A richer session-history entity that preserves every [SetLog] is a future
/// enhancement — until then, this is the bridge into the existing log.
extension WorkoutSessionLog on WorkoutSession {
  /// Builds the history [Workout]. Title is the day's label, `performedAt` is
  /// the completion time (falling back to the start), and each planned exercise
  /// with at least one completed set becomes one [Exercise]:
  /// - `sets`     = number of completed sets for that exercise;
  /// - `reps`     = the exercise's first-set target (fixed count / range min),
  ///                or the best actual reps when the target is to-failure;
  /// - `weightKg` = the last recorded actual weight for that exercise.
  Workout toWorkoutLog() {
    final exercises = <Exercise>[];
    for (final planned in day.exercises) {
      final doneLogs = logs.where((l) => l.exerciseId == planned.id && l.done).toList();
      if (doneLogs.isEmpty) continue;
      exercises.add(
        Exercise(
          name: planned.name,
          sets: doneLogs.length,
          reps: _repsFor(planned, doneLogs),
          weightKg: _lastActualWeight(doneLogs),
        ),
      );
    }
    return Workout(
      id: id,
      title: day.label,
      performedAt: completedAt ?? startedAt,
      exercises: exercises,
    );
  }
}

/// The first set's prescribed reps (fixed count or range minimum), or — when the
/// target is to-failure — the best actual reps recorded across the done sets.
int _repsFor(PlannedExercise planned, List<SetLog> doneLogs) {
  final firstTarget = planned.sets.isNotEmpty ? planned.sets.first.repTarget : null;
  if (firstTarget != null &&
      (firstTarget.kind == RepTargetKind.fixed || firstTarget.kind == RepTargetKind.range)) {
    return firstTarget.min ?? 0;
  }
  final actuals = doneLogs.map((l) => l.actualReps).whereType<int>();
  return actuals.isEmpty ? 0 : actuals.reduce((a, b) => a > b ? a : b);
}

/// The last non-null actual weight in completion order, or null if none recorded.
double? _lastActualWeight(List<SetLog> doneLogs) {
  double? weight;
  for (final log in doneLogs) {
    if (log.actualWeightKg != null) weight = log.actualWeightKg;
  }
  return weight;
}
