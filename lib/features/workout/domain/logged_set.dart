import 'rep_target.dart';
import 'set_outcome.dart';
import 'set_type.dart';

const Object _unset = Object();

/// One set inside a live/completed session — the plan's prescription
/// ([target] reps + [targetWeightKg]) alongside what was actually performed
/// ([actualReps]/[actualWeightKg]/[rpe]) and its [outcome]. Immutable; edits
/// go through [copyWith], which can *clear* a nullable field back to null by
/// passing an explicit `null`.
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
    this.outcome = SetOutcome.pending,
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

  /// Never touched / actually performed / deliberately passed over. The
  /// [LiveSession] cursor (`currentSet`) is derived from this — only
  /// [SetOutcome.pending] sets are "not yet handled" — so a skip advances
  /// past a set the same way completing one does.
  final SetOutcome outcome;

  /// True iff [outcome] is [SetOutcome.completed] — the set counts as
  /// logged volume (history, `completedSetCount`, progress). A skipped set
  /// is deliberately NOT "done": it must never be counted as performed.
  bool get done => outcome == SetOutcome.completed;

  bool get skipped => outcome == SetOutcome.skipped;

  bool get pending => outcome == SetOutcome.pending;

  LoggedSet copyWith({
    RepTarget? target,
    Object? targetWeightKg = _unset,
    Object? actualReps = _unset,
    Object? actualWeightKg = _unset,
    Object? rpe = _unset,
    SetType? type,
    SetOutcome? outcome,
  }) => LoggedSet(
    id: id,
    target: target ?? this.target,
    targetWeightKg:
        targetWeightKg == _unset ? this.targetWeightKg : targetWeightKg as double?,
    actualReps: actualReps == _unset ? this.actualReps : actualReps as int?,
    actualWeightKg: actualWeightKg == _unset ? this.actualWeightKg : actualWeightKg as double?,
    rpe: rpe == _unset ? this.rpe : rpe as double?,
    type: type ?? this.type,
    outcome: outcome ?? this.outcome,
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
      other.outcome == outcome;

  @override
  int get hashCode =>
      Object.hash(id, target, targetWeightKg, actualReps, actualWeightKg, rpe, type, outcome);
}
