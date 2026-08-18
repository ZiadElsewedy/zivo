import 'logged_set.dart';

/// One exercise inside a session — its [sets] plus enough identity to keep
/// history continuous. [exerciseId] is the *canonical* movement id (stable
/// across sessions, so "previous weight" and trends line up even after a machine
/// swap), while [id] is this session-instance's own id.
class SessionExercise {
  const SessionExercise({
    required this.id,
    required this.exerciseId,
    required this.name,
    this.muscleGroup,
    required this.restSeconds,
    required this.sets,
  });

  final String id;
  final String exerciseId;
  final String name;
  final String? muscleGroup;
  final int restSeconds;
  final List<LoggedSet> sets;

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
    String? name,
    String? muscleGroup,
    int? restSeconds,
    List<LoggedSet>? sets,
  }) => SessionExercise(
    id: id,
    exerciseId: exerciseId,
    name: name ?? this.name,
    muscleGroup: muscleGroup ?? this.muscleGroup,
    restSeconds: restSeconds ?? this.restSeconds,
    sets: sets ?? this.sets,
  );
}
