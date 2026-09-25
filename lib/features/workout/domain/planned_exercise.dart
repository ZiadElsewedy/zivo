import 'set_type.dart';
import 'workout_set.dart';

/// One **slot** within a [WorkoutDay] — where an exercise sits in a split and
/// what it prescribes there (sets, rep range, rest), not the exercise itself.
///
/// [id] identifies the slot. [exerciseId] points at the canonical exercise
/// performed in it (`CanonicalExercise`), so two slots on two days can share
/// one exercise and one progression history. Null means the slot has never
/// been given one and is its own exercise — see [canonicalId].
class PlannedExercise {
  const PlannedExercise({
    required this.id,
    this.exerciseId,
    required this.name,
    required this.order,
    this.muscleGroup,
    this.notes,
    required this.defaultRestSeconds,
    required this.sets,
  });

  final String id;

  /// The canonical exercise this slot performs; null for "itself".
  final String? exerciseId;

  final String name;
  final int order;
  final String? muscleGroup;
  final String? notes;
  final int defaultRestSeconds;
  final List<PlannedSet> sets;

  /// The canonical exercise id this slot performs. A slot never given an
  /// identity is its own exercise, keyed by its own id — exactly how every
  /// plan behaved before identities existed, so older plans need no
  /// migration to keep their history.
  String get canonicalId => exerciseId ?? id;

  int get setCount => sets.length;

  int get workingSetCount =>
      sets.where((s) => s.type == SetType.working).length;

  PlannedExercise copyWith({
    String? exerciseId,
    String? name,
    int? order,
    String? muscleGroup,
    String? notes,
    int? defaultRestSeconds,
    List<PlannedSet>? sets,
  }) => PlannedExercise(
    id: id,
    exerciseId: exerciseId ?? this.exerciseId,
    name: name ?? this.name,
    order: order ?? this.order,
    muscleGroup: muscleGroup ?? this.muscleGroup,
    notes: notes ?? this.notes,
    defaultRestSeconds: defaultRestSeconds ?? this.defaultRestSeconds,
    sets: sets ?? this.sets,
  );
}
