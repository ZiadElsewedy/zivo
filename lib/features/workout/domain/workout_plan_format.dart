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

/// Collapses consecutive [sets] (already in `order`) that share the same
/// target/weight/rest into one summary line each — "3 × 8–10 · rest 1:30"
/// instead of the same "8–10 reps · rest 1:30" line repeated per set. Only
/// starts a new line where a set actually differs from the one before it,
/// so a plan that legitimately varies across its sets (e.g. a drop set, or a
/// deliberately different last set) still enumerates those differences.
List<String> collapsedSetSummaries(List<PlannedSet> sets) {
  if (sets.isEmpty) return const [];
  final groups = <List<PlannedSet>>[];
  for (final s in sets) {
    final current = groups.isEmpty ? null : groups.last;
    if (current != null && _sameSpec(current.first, s)) {
      current.add(s);
    } else {
      groups.add([s]);
    }
  }
  return [for (final group in groups) _groupSummary(group)];
}

bool _sameSpec(PlannedSet a, PlannedSet b) =>
    a.repTarget == b.repTarget &&
    a.targetWeightKg == b.targetWeightKg &&
    a.restSeconds == b.restSeconds &&
    a.rpe == b.rpe &&
    a.type == b.type;

String _groupSummary(List<PlannedSet> group) {
  final s = group.first;
  final parts = [
    if (s.targetWeightKg != null) '${_trimWeight(s.targetWeightKg!)}kg',
    'rest ${restLabel(s.restSeconds)}',
  ];
  return '${group.length} × ${repTargetLabel(s.repTarget)} · ${parts.join(' · ')}';
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
