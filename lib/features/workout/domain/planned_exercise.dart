import 'set_type.dart';
import 'workout_set.dart';

/// One movement within a [WorkoutDay] — the planned sets to perform, not the
/// executed outcome (execution is a later phase).
class PlannedExercise {
  const PlannedExercise({
    required this.id,
    required this.name,
    required this.order,
    this.muscleGroup,
    this.notes,
    required this.defaultRestSeconds,
    required this.sets,
  });

  final String id;
  final String name;
  final int order;
  final String? muscleGroup;
  final String? notes;
  final int defaultRestSeconds;
  final List<PlannedSet> sets;

  int get setCount => sets.length;

  int get workingSetCount => sets.where((s) => s.type == SetType.working).length;

  PlannedExercise copyWith({
    String? name,
    int? order,
    String? muscleGroup,
    String? notes,
    int? defaultRestSeconds,
    List<PlannedSet>? sets,
  }) => PlannedExercise(
    id: id,
    name: name ?? this.name,
    order: order ?? this.order,
    muscleGroup: muscleGroup ?? this.muscleGroup,
    notes: notes ?? this.notes,
    defaultRestSeconds: defaultRestSeconds ?? this.defaultRestSeconds,
    sets: sets ?? this.sets,
  );
}
