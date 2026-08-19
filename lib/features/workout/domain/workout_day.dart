import 'planned_exercise.dart';

/// One day within a [WorkoutPlan]'s rotating cycle — keyed by [slot] (e.g.
/// "A", "B", "C") and [order], its position in the rotation. Not tied to a
/// weekday: the cycle advances regardless of which day of the week it is.
class WorkoutDay {
  const WorkoutDay({
    required this.id,
    required this.slot,
    required this.label,
    this.notes,
    required this.order,
    required this.exercises,
  });

  final String id;
  final String slot;
  final String label;
  final String? notes;
  final int order;
  final List<PlannedExercise> exercises;

  int get exerciseCount => exercises.length;

  WorkoutDay copyWith({
    String? slot,
    String? label,
    String? notes,
    int? order,
    List<PlannedExercise>? exercises,
  }) => WorkoutDay(
    id: id,
    slot: slot ?? this.slot,
    label: label ?? this.label,
    notes: notes ?? this.notes,
    order: order ?? this.order,
    exercises: exercises ?? this.exercises,
  );
}
