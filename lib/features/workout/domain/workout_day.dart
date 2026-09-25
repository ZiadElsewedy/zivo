import 'planned_exercise.dart';

/// What a day in the rotation asks of the user.
///
/// Persisted by `name` (absent ⇒ [workout], so every plan written before rest
/// days existed reads back unchanged). A rest day is a real slot in the cycle,
/// NOT an empty workout: nothing may treat it as something to start, and it
/// never carries exercises.
enum TrainingDayType { workout, rest }

/// Parses a stored [TrainingDayType], defaulting to [TrainingDayType.workout].
TrainingDayType trainingDayTypeFromName(String? name) => TrainingDayType.values
    .firstWhere((t) => t.name == name, orElse: () => TrainingDayType.workout);

/// One day within a [WorkoutPlan]'s rotating cycle — keyed by [slot] (e.g.
/// "A", "B", "C") and [order], its position in the rotation. Not tied to a
/// weekday: the cycle advances regardless of which day of the week it is.
///
/// A [TrainingDayType.rest] day sits in the cycle after the workout it follows
/// ("Lower → Rest → Push"): see `training_days.dart` for how a rest slot is
/// placed on the calendar.
class WorkoutDay {
  const WorkoutDay({
    required this.id,
    required this.slot,
    required this.label,
    this.notes,
    required this.order,
    required this.exercises,
    this.type = TrainingDayType.workout,
  });

  final String id;
  final String slot;
  final String label;
  final String? notes;
  final int order;
  final List<PlannedExercise> exercises;
  final TrainingDayType type;

  bool get isRest => type == TrainingDayType.rest;
  bool get isWorkout => type == TrainingDayType.workout;

  int get exerciseCount => exercises.length;

  WorkoutDay copyWith({
    String? slot,
    String? label,
    String? notes,
    int? order,
    List<PlannedExercise>? exercises,
    TrainingDayType? type,
  }) => WorkoutDay(
    id: id,
    slot: slot ?? this.slot,
    label: label ?? this.label,
    notes: notes ?? this.notes,
    order: order ?? this.order,
    exercises: exercises ?? this.exercises,
    type: type ?? this.type,
  );
}
