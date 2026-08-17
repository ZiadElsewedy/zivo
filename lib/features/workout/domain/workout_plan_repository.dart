import 'workout_plan.dart';

/// The seam between the app and workout plan storage (in-memory demo for now,
/// Firestore-backed later). There is at most one *active* plan at a time —
/// [savePlan] creates or replaces it by id (idempotent edit).
abstract interface class WorkoutPlanRepository {
  WorkoutPlan? get activePlan;
  Stream<WorkoutPlan?> watchActivePlan();

  /// Creates or replaces [plan] by id (idempotent edit).
  Future<void> savePlan(WorkoutPlan plan);

  /// Removes the plan, returning the page to its empty "create" state.
  Future<void> deletePlan(String id);
}
