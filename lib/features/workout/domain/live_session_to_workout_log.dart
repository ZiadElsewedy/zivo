import 'exercise.dart';
import 'live_session.dart';
import 'logged_set.dart';
import 'workout.dart';

/// Projects a finished [LiveSession] onto the flat history [Workout] entity
/// ("what I did").
///
/// LOSSY BY DESIGN: the history model holds only sets × reps × weight per
/// exercise, so per-set actuals collapse to a single representative reps/weight
/// — the full per-set record lives in the session itself
/// (`users/{uid}/workoutSessions`), this is just the bridge into the existing
/// flat log.
extension LiveSessionLog on LiveSession {
  /// Builds the history [Workout]. Title is the day's label, `performedAt` is
  /// the completion time (falling back to the start), and each session
  /// exercise with at least one done set becomes one [Exercise]:
  /// - `sets`     = number of done sets for that exercise;
  /// - `reps`     = the best actual reps recorded, or the first set's target
  ///                when nothing was recorded;
  /// - `weightKg` = the last recorded actual weight for that exercise.
  Workout toWorkoutLog() {
    final exercises = <Exercise>[];
    for (final exercise in this.exercises) {
      final doneSets = exercise.sets.where((s) => s.done).toList();
      if (doneSets.isEmpty) continue;
      exercises.add(
        Exercise(
          name: exercise.name,
          sets: doneSets.length,
          reps: _repsFor(doneSets),
          weightKg: _lastActualWeight(doneSets),
        ),
      );
    }
    return Workout(
      id: id,
      title: dayLabel,
      performedAt: completedAt ?? startedAt,
      exercises: exercises,
    );
  }
}

/// The best actual reps recorded across the done sets, or the first set's
/// prescribed minimum when nothing was recorded.
int _repsFor(List<LoggedSet> doneSets) {
  final actuals = doneSets.map((s) => s.actualReps).whereType<int>();
  if (actuals.isNotEmpty) return actuals.reduce((a, b) => a > b ? a : b);
  return doneSets.first.target.min ?? 0;
}

/// The last non-null actual weight in list order, or null if none recorded.
double? _lastActualWeight(List<LoggedSet> doneSets) {
  double? weight;
  for (final set in doneSets) {
    if (set.actualWeightKg != null) weight = set.actualWeightKg;
  }
  return weight;
}
