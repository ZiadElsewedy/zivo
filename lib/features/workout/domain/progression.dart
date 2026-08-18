import 'logged_set.dart';
import 'muscle_group.dart';
import 'rep_target.dart';

/// The computed progressive-overload goal for a set the user is about to
/// perform — what to aim for, given the plan's prescription and (if
/// available) what was actually done the last time this exact set (by
/// index) was trained.
class ProgressionGoal {
  const ProgressionGoal({required this.weightKg, required this.repsLabel, required this.label});

  /// The suggested load — null when there's nothing to suggest a weight
  /// from (no plan `targetWeightKg` and no previous weight, e.g. an
  /// unweighted bodyweight movement never logged with a weight).
  final double? weightKg;

  /// "8", "AMRAP" — the suggested rep count, or "AMRAP" for to-failure sets.
  final String repsLabel;

  /// A short human summary, e.g. "62.5kg × 8" or "AMRAP".
  final String label;
}

/// "60" / "22.5" — a weight without a trailing ".0".
String _trimWeight(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

/// The per-step weight jump once a rep target's top has been hit — smaller
/// for small/isolation muscle groups, which don't tolerate big load jumps.
double _incrementKg(String? muscleGroup) => isSmallMuscleGroup(muscleGroup) ? 1.25 : 2.5;

String _label(double? weightKg, String repsLabel) {
  final repsPart = repsLabel == 'AMRAP' ? 'AMRAP' : '× $repsLabel';
  return weightKg == null ? repsPart : '${_trimWeight(weightKg)}kg $repsPart';
}

/// Double progression: no history for this set → the plan's own
/// prescription. History exists → hitting the top of the rep target (its max
/// for a range, its only count for a fixed target) steps the weight up
/// ([_incrementKg]) and resets to the target's floor reps; falling short of
/// the top keeps the same weight and asks for one more rep, capped at the
/// top. A to-failure target always asks to beat the previous rep count at
/// the same weight ("AMRAP" — no fixed top to compare against).
///
/// The weight-step-and-reset only applies when there's an actual weight to
/// step ([prevWeight] non-null) — for a bodyweight movement with nothing to
/// load, resetting to the floor would ask for *fewer* reps than were just
/// done, which is a regression, not a goal. With no weight to progress,
/// hitting the top instead just keeps asking for one more rep (uncapped,
/// there being no load to trade reps against), same spirit as to-failure.
///
/// [previous] is the index-aligned set from the last time this exercise was
/// trained (see `lastPerformanceFor`/`ExerciseHistory`) — null if never
/// trained, or if that set was never actually logged with a rep count.
ProgressionGoal computeGoal({
  required RepTarget target,
  double? targetWeightKg,
  LoggedSet? previous,
  String? muscleGroup,
}) {
  final prevReps = previous?.actualReps;
  if (previous == null || prevReps == null) {
    final repsLabel = switch (target.kind) {
      RepTargetKind.fixed => '${target.min}',
      RepTargetKind.range => '${target.min}',
      RepTargetKind.toFailure => 'AMRAP',
    };
    return ProgressionGoal(
      weightKg: targetWeightKg,
      repsLabel: repsLabel,
      label: _label(targetWeightKg, repsLabel),
    );
  }

  final prevWeight = previous.actualWeightKg ?? targetWeightKg;

  if (target.kind == RepTargetKind.toFailure) {
    final reps = prevReps + 1;
    return ProgressionGoal(
      weightKg: prevWeight,
      repsLabel: '$reps',
      label: _label(prevWeight, '$reps'),
    );
  }

  final topReps = target.kind == RepTargetKind.range ? target.max! : target.min!;
  final floorReps = target.min!;
  if (prevReps >= topReps) {
    if (prevWeight == null) {
      final reps = prevReps + 1;
      return ProgressionGoal(weightKg: null, repsLabel: '$reps', label: _label(null, '$reps'));
    }
    final weight = prevWeight + _incrementKg(muscleGroup);
    return ProgressionGoal(
      weightKg: weight,
      repsLabel: '$floorReps',
      label: _label(weight, '$floorReps'),
    );
  }
  final nextReps = prevReps + 1 > topReps ? topReps : prevReps + 1;
  return ProgressionGoal(
    weightKg: prevWeight,
    repsLabel: '$nextReps',
    label: _label(prevWeight, '$nextReps'),
  );
}
