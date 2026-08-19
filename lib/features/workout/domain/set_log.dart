import 'rep_target.dart';

/// The record of one set performed during a [WorkoutSession] — the plan's
/// [target] alongside what was actually done ([actualReps]/[actualWeightKg]).
///
/// Immutable value type: a set is logged once (as [done]) and never mutated in
/// place; edits produce a new [SetLog] via [copyWith].
class SetLog {
  const SetLog({
    required this.exerciseId,
    required this.setOrder,
    required this.target,
    this.actualReps,
    this.actualWeightKg,
    this.done = false,
  });

  /// The [PlannedExercise.id] this set belongs to — the join key back to the
  /// plan when projecting to history.
  final String exerciseId;

  /// The set's `order` within its exercise (0-based).
  final int setOrder;

  /// What the plan prescribed for this set.
  final RepTarget target;

  /// Reps actually performed; null when not recorded.
  final int? actualReps;

  /// Load actually used, in kg; null when bodyweight or not recorded.
  final double? actualWeightKg;

  /// Whether the set has been completed.
  final bool done;

  SetLog copyWith({
    String? exerciseId,
    int? setOrder,
    RepTarget? target,
    int? actualReps,
    double? actualWeightKg,
    bool? done,
  }) => SetLog(
    exerciseId: exerciseId ?? this.exerciseId,
    setOrder: setOrder ?? this.setOrder,
    target: target ?? this.target,
    actualReps: actualReps ?? this.actualReps,
    actualWeightKg: actualWeightKg ?? this.actualWeightKg,
    done: done ?? this.done,
  );

  @override
  bool operator ==(Object other) =>
      other is SetLog &&
      other.exerciseId == exerciseId &&
      other.setOrder == setOrder &&
      other.target == target &&
      other.actualReps == actualReps &&
      other.actualWeightKg == actualWeightKg &&
      other.done == done;

  @override
  int get hashCode =>
      Object.hash(exerciseId, setOrder, target, actualReps, actualWeightKg, done);
}
