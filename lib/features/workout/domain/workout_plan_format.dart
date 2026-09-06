import 'rep_target.dart';
import 'workout_set.dart';

/// "10" or "8–12" (en dash) — the bare rep figure.
///
/// Deliberately has no answer for [RepTargetKind.toFailure]: that case is a
/// *word*, and a word is `presentation/workout_labels.dart`'s job. Callers
/// showing a rep target to a reader should use `repTargetText` there, which
/// handles all three and pins the range against bidi reordering.
String repTargetFigure(RepTarget t) => switch (t.kind) {
  RepTargetKind.fixed => '${t.min}',
  RepTargetKind.range => '${t.min}–${t.max}',
  RepTargetKind.toFailure => '${t.min}',
};

/// "2:00", "0:45", "1:30" — seconds formatted as mm:ss.
String restLabel(int seconds) {
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  return '$minutes:${remaining.toString().padLeft(2, '0')}';
}

/// Groups consecutive [sets] (already in `order`) that share the same
/// target/weight/rest, so a 3-set exercise reads as one "3 × 8–10 · rest 1:30"
/// line instead of the same line repeated per set. Only starts a new group
/// where a set actually differs from the one before it, so a plan that
/// legitimately varies across its sets (e.g. a drop set, or a deliberately
/// different last set) still enumerates those differences.
///
/// Returns the *groups*, not their prose: which sets belong together is a
/// property of the plan and belongs here, while what the resulting line says
/// is language, and lives in `presentation/workout_labels.dart`. Splitting
/// them is what let the spec line be translated and direction-pinned without
/// this rule being duplicated at each call site.
List<List<PlannedSet>> collapsedSetGroups(List<PlannedSet> sets) {
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
  return groups;
}

bool _sameSpec(PlannedSet a, PlannedSet b) =>
    a.repTarget == b.repTarget &&
    a.targetWeightKg == b.targetWeightKg &&
    a.restSeconds == b.restSeconds &&
    a.rpe == b.rpe &&
    a.type == b.type;

// The English composers that used to live here — `_groupSummary`,
// `plannedExerciseMeta`, `workoutDayMeta` and `setSummary` — are now
// `presentation/workout_labels.dart`. They were the reason a plan read as
// `rest 1:30 · 10–8 × 3` in Arabic: hardcoded English words, and a numeric
// skeleton with no direction of its own for the paragraph to respect.
