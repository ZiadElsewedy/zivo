import 'diet_plan.dart';
import 'nutrition_targets.dart';

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

  /// The user's active nutrition objective, or null when they haven't set
  /// one. **Null is a real, expected state** — ZIVO never invents a target, so
  /// "unset" has to be representable and every caller has to handle it rather
  /// than falling back to a number nobody chose.
  NutritionTargets? get currentTargets;
  Stream<NutritionTargets?> watchTargets();

  /// Creates or replaces the user's targets (there is only ever one set).
  Future<void> saveTargets(NutritionTargets targets);

  /// Removes the targets, returning the app to the honest "not set" state.
  Future<void> clearTargets();

  /// The set of meal ids marked eaten on [day].
  Stream<Set<String>> watchConsumed(DateTime day);
  Future<void> setMealEaten({
    required String mealId,
    required DateTime day,
    required bool eaten,
  });
}
