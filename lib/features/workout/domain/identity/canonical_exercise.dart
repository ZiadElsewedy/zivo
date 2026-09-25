import 'equipment.dart';

/// **What an exercise IS** — the exact movement, variation and equipment,
/// independent of any split, day or position in a plan.
///
/// Three concepts that used to be one id:
///
/// - a [CanonicalExercise] is the identity ("Incline Dumbbell Press");
/// - a plan **slot** (`PlannedExercise`) is where it appears in a split —
///   its own sets, rep range and rest — and points here through
///   `PlannedExercise.exerciseId`;
/// - **progression history** is every logged `SessionExercise` whose
///   `exerciseId` resolves to this [id], whichever slot, day or split it was
///   performed in.
///
/// So the same Incline Dumbbell Press on Push and on Chest & Back is ONE
/// canonical exercise with two slots and one history, while an Incline
/// Machine Chest Press stays its own exercise however similar the name.
///
/// Deliberately clean: no list of the old ids it absorbed. Legacy-id mapping
/// is a separate layer (`ExerciseAlias`) so the identity never carries its
/// own migration history.
///
/// A slot that has never been assigned one is its own canonical exercise,
/// with the slot id as the canonical id — which is exactly how every plan
/// behaved before identities existed, so nothing needs one to keep working.
class CanonicalExercise {
  const CanonicalExercise({
    required this.id,
    required this.name,
    this.equipment,
    this.muscleGroup,
    required this.createdAt,
  });

  final String id;

  /// The display name. Renaming changes this and nothing else — the [id],
  /// and with it the whole history, stays exactly where it was.
  final String name;

  /// Null when not known. Matching falls back to what the name implies
  /// (`inferEquipmentFromTokens`) and never treats "unknown" as a confirmed match.
  final Equipment? equipment;

  final String? muscleGroup;
  final DateTime createdAt;

  CanonicalExercise copyWith({
    String? name,
    Equipment? equipment,
    String? muscleGroup,
  }) => CanonicalExercise(
    id: id,
    name: name ?? this.name,
    equipment: equipment ?? this.equipment,
    muscleGroup: muscleGroup ?? this.muscleGroup,
    createdAt: createdAt,
  );
}
