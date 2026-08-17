import 'planned_exercise.dart';
import 'workout_day.dart';
import 'workout_plan.dart';

/// [plan] with its days (and each day's exercises, and each exercise's sets)
/// sorted by their current `order` and reassigned contiguous 0-based `order`
/// values. [WorkoutPlan.nextDay] looks days up by `order` while
/// [WorkoutPlan.advanceCursor] wraps `cycleCursor % days.length` — both stay
/// consistent only if orders are contiguous and 0-based, so repositories call
/// this on every [WorkoutPlanRepository.savePlan].
WorkoutPlan normalizeWorkoutPlanOrder(WorkoutPlan plan) {
  final days = [...plan.days]..sort((a, b) => a.order.compareTo(b.order));
  return plan.copyWith(days: [for (var i = 0; i < days.length; i++) _normalizeDay(days[i], i)]);
}

WorkoutDay _normalizeDay(WorkoutDay day, int order) {
  final exercises = [...day.exercises]..sort((a, b) => a.order.compareTo(b.order));
  return day.copyWith(
    order: order,
    exercises: [
      for (var i = 0; i < exercises.length; i++) _normalizeExercise(exercises[i], i),
    ],
  );
}

PlannedExercise _normalizeExercise(PlannedExercise exercise, int order) {
  final sets = [...exercise.sets]..sort((a, b) => a.order.compareTo(b.order));
  return exercise.copyWith(
    order: order,
    sets: [for (var i = 0; i < sets.length; i++) sets[i].copyWith(order: i)],
  );
}
