import 'diet_plan.dart';

/// The seam between the app and diet plan storage (in-memory demo for now,
/// Firestore-backed later). There is at most one *active* plan at a time —
/// [savePlan] creates or replaces it by id (idempotent edit).
abstract interface class DietRepository {
  DietPlan? get activePlan;
  Stream<DietPlan?> watchActivePlan();
  Future<void> savePlan(DietPlan plan);

  /// Removes the plan, returning the page to its empty "create" state.
  /// `dietEntries` referencing the deleted plan's meal ids are left in place
  /// (a benign orphan — no bulk-delete of the consumption log).
  Future<void> deletePlan(String id);

  /// The set of meal ids marked eaten on [day].
  Stream<Set<String>> watchConsumed(DateTime day);
  Future<void> setMealEaten({
    required String mealId,
    required DateTime day,
    required bool eaten,
  });
}
