import 'planned_exercise.dart';
import 'rep_target.dart';
import 'workout_day.dart';
import 'workout_set.dart';

/// A weight without a trailing ".0": 60 → "60", 22.5 → "22.5".
String _trimWeight(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

/// "10", "8–12" (en dash), or "To failure".
String repTargetLabel(RepTarget t) {
  switch (t.kind) {
    case RepTargetKind.fixed:
      return '${t.min}';
    case RepTargetKind.range:
      return '${t.min}–${t.max}';
    case RepTargetKind.toFailure:
      return 'To failure';
  }
}

/// "2:00", "0:45", "1:30" — seconds formatted as mm:ss.
String restLabel(int seconds) {
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  return '$minutes:${remaining.toString().padLeft(2, '0')}';
}

/// "10 reps · 60kg · rest 2:00" — omits the weight when unset.
String setSummary(PlannedSet s) {
  final repsLabel = s.repTarget.kind == RepTargetKind.toFailure
      ? repTargetLabel(s.repTarget)
      : '${repTargetLabel(s.repTarget)} reps';
  final parts = [
    repsLabel,
    if (s.targetWeightKg != null) '${_trimWeight(s.targetWeightKg!)}kg',
    'rest ${restLabel(s.restSeconds)}',
  ];
  return parts.join(' · ');
}

/// "4 sets · Chest" — omits the muscle group when unset.
String plannedExerciseMeta(PlannedExercise e) {
  final count = '${e.setCount} set${e.setCount == 1 ? '' : 's'}';
  if (e.muscleGroup == null) return count;
  return '$count · ${e.muscleGroup}';
}

/// "6 exercises" — the one-line meta beneath a workout day.
String workoutDayMeta(WorkoutDay d) {
  final count = d.exerciseCount;
  return '$count exercise${count == 1 ? '' : 's'}';
}
