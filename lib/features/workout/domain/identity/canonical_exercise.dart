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
    this.distinctFrom = const {},
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

  /// Exercises the user said are NOT this one, when the names suggested they
  /// might be — so "same exercise?" is asked once, not on every visit.
  final Set<String> distinctFrom;

  CanonicalExercise copyWith({
    String? name,
    Equipment? equipment,
    String? muscleGroup,
    Set<String>? distinctFrom,
  }) => CanonicalExercise(
    id: id,
    name: name ?? this.name,
    equipment: equipment ?? this.equipment,
    muscleGroup: muscleGroup ?? this.muscleGroup,
    createdAt: createdAt,
    distinctFrom: distinctFrom ?? this.distinctFrom,
  );
}

int _idCounter = 0;

/// A fresh canonical exercise id. Prefixed so it can never collide with a
/// plan slot id — slot ids are what legacy records carry, and a canonical id
/// equal to one would make "this slot is its own exercise" and "this slot
/// performs that exercise" indistinguishable.
String newCanonicalExerciseId(DateTime now) =>
    'x-${now.microsecondsSinceEpoch.toRadixString(36)}'
    '${(_idCounter++).toRadixString(36)}';

/// The canonical id the identity migration gives the group of legacy ids
/// represented by [legacyId]. Deterministic, so two devices migrating the
/// same account at once write the same documents instead of duplicates.
String migratedCanonicalExerciseId(String legacyId) =>
    'x-${legacyId.replaceAll('/', '_')}';

/// Whether [id] was minted as a canonical id ([newCanonicalExerciseId] or
/// [migratedCanonicalExerciseId]) rather than being a legacy slot id.
bool isCanonicalExerciseId(String id) => id.startsWith('x-');
