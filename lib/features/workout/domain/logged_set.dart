import 'rep_target.dart';
import 'set_type.dart';

const Object _unset = Object();

/// One set inside a live/completed session — the plan's prescription
/// ([target] reps + [targetWeightKg]) alongside what was actually performed
/// ([actualReps]/[actualWeightKg]/[rpe]) and whether it's [done]. Immutable;
/// edits go through [copyWith], which can *clear* a nullable field back to null
/// by passing an explicit `null`.
///
/// [id] is a stable identity so sets survive reordering, insertion, and deletion
/// while the UI keys off them.
class LoggedSet {
  const LoggedSet({
    required this.id,
    required this.target,
    this.targetWeightKg,
    this.actualReps,
    this.actualWeightKg,
    this.rpe,
    this.type = SetType.working,
    this.done = false,
  });

  final String id;

  /// The prescribed rep target (fixed / range / to-failure).
  final RepTarget target;

  /// The prescribed load, if the plan set one — used to pre-fill the input.
  final double? targetWeightKg;

  final int? actualReps;
  final double? actualWeightKg;

  /// Rate of perceived exertion — optional, captured now so the progress engine
  /// and future AI can reason about effort.
  final double? rpe;
  final SetType type;
  final bool done;

  LoggedSet copyWith({
    RepTarget? target,
    Object? targetWeightKg = _unset,
    Object? actualReps = _unset,
    Object? actualWeightKg = _unset,
    Object? rpe = _unset,
    SetType? type,
    bool? done,
  }) => LoggedSet(
    id: id,
    target: target ?? this.target,
    targetWeightKg:
        targetWeightKg == _unset ? this.targetWeightKg : targetWeightKg as double?,
    actualReps: actualReps == _unset ? this.actualReps : actualReps as int?,
    actualWeightKg: actualWeightKg == _unset ? this.actualWeightKg : actualWeightKg as double?,
    rpe: rpe == _unset ? this.rpe : rpe as double?,
    type: type ?? this.type,
    done: done ?? this.done,
  );

  @override
  bool operator ==(Object other) =>
      other is LoggedSet &&
      other.id == id &&
      other.target == target &&
      other.targetWeightKg == targetWeightKg &&
      other.actualReps == actualReps &&
      other.actualWeightKg == actualWeightKg &&
      other.rpe == rpe &&
      other.type == type &&
      other.done == done;

  @override
  int get hashCode =>
      Object.hash(id, target, targetWeightKg, actualReps, actualWeightKg, rpe, type, done);
}
