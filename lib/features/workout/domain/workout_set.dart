import 'rep_target.dart';
import 'set_type.dart';

/// One planned set within a [PlannedExercise] — the target ("what I SHOULD
/// do"), not the actual outcome of performing it (that's a later phase).
class PlannedSet {
  const PlannedSet({
    required this.order,
    required this.repTarget,
    required this.restSeconds,
    this.targetWeightKg,
    this.rpe,
    required this.type,
  });

  final int order;
  final RepTarget repTarget;
  final int restSeconds;
  final double? targetWeightKg;
  final double? rpe;
  final SetType type;

  PlannedSet copyWith({
    int? order,
    RepTarget? repTarget,
    int? restSeconds,
    double? targetWeightKg,
    double? rpe,
    SetType? type,
  }) => PlannedSet(
    order: order ?? this.order,
    repTarget: repTarget ?? this.repTarget,
    restSeconds: restSeconds ?? this.restSeconds,
    targetWeightKg: targetWeightKg ?? this.targetWeightKg,
    rpe: rpe ?? this.rpe,
    type: type ?? this.type,
  );

  @override
  bool operator ==(Object other) =>
      other is PlannedSet &&
      other.order == order &&
      other.repTarget == repTarget &&
      other.restSeconds == restSeconds &&
      other.targetWeightKg == targetWeightKg &&
      other.rpe == rpe &&
      other.type == type;

  @override
  int get hashCode => Object.hash(order, repTarget, restSeconds, targetWeightKg, rpe, type);
}
