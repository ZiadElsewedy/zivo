import 'exercise.dart';
import 'workout.dart';

/// A weight without a trailing ".0": 60 → "60", 22.5 → "22.5".
String _trimWeight(double v) =>
    v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

/// "3 × 10" or "3 × 10 · 60kg" when a load is set.
String setRepLabel(Exercise e) {
  final base = '${e.sets} × ${e.reps}';
  if (e.weightKg == null) return base;
  return '$base · ${_trimWeight(e.weightKg!)}kg';
}

/// The one-line meta beneath a workout: "5 exercises · ~50 min".
String workoutMeta(Workout w) {
  final count = '${w.exerciseCount} exercise${w.exerciseCount == 1 ? '' : 's'}';
  if (w.durationMinutes == null) return count;
  return '$count · ~${w.durationMinutes} min';
}
