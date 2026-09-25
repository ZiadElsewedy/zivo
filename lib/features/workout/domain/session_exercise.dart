import 'logged_set.dart';

/// One exercise inside a session — its [sets] plus enough identity to keep
/// history continuous. Three ids, three jobs:
///
/// - [exerciseId] — the *canonical* exercise (`CanonicalExercise`): what was
///   performed. Every progression engine keys on it, so the same exercise
///   shares one history across days and splits.
/// - [slotId] — the plan slot this came from (`PlannedExercise.id`): where it
///   sat in the split. Adherence and slot-first goals key on it.
/// - [id] — this session instance's own id.
///
/// Before identities existed all three were the slot id. Those records are
/// read as they were written — see [effectiveSlotId] and
/// `ExerciseIdentityResolver` — and never rewritten.
class SessionExercise {
  const SessionExercise({
    required this.id,
    required this.exerciseId,
    this.slotId,
    required this.name,
    this.muscleGroup,
    required this.restSeconds,
    required this.sets,
  });

  final String id;
  final String exerciseId;

  /// The plan slot this exercise was started from, or null for an exercise
  /// with no slot (one added during the session). Null on every record
  /// written before slots were stored — see [effectiveSlotId].
  final String? slotId;

  final String name;
  final String? muscleGroup;
  final int restSeconds;
  final List<LoggedSet> sets;

  /// The slot this exercise came from, reading older records correctly: a
  /// session logged before [slotId] existed used the slot id as its own
  /// [id], so that is the slot.
  String get effectiveSlotId => slotId ?? id;

  int get setCount => sets.length;
  int get doneSetCount => sets.where((s) => s.done).length;

  /// The heaviest weight lifted on a done set — a compact "top set" summary.
  double? get topWeightKg {
    double? top;
    for (final s in sets) {
      if (!s.done) continue;
      final w = s.actualWeightKg;
      if (w != null && (top == null || w > top)) top = w;
    }
    return top;
  }

  SessionExercise copyWith({
    String? exerciseId,
    String? name,
    String? muscleGroup,
    int? restSeconds,
    List<LoggedSet>? sets,
  }) => SessionExercise(
    id: id,
    exerciseId: exerciseId ?? this.exerciseId,
    slotId: slotId,
    name: name ?? this.name,
    muscleGroup: muscleGroup ?? this.muscleGroup,
    restSeconds: restSeconds ?? this.restSeconds,
    sets: sets ?? this.sets,
  );
}
