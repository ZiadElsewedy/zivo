import 'workout_plan.dart';

/// The seam between the app and workout plan storage (in-memory demo for now,
/// Firestore-backed later).
///
/// A *split* IS a [WorkoutPlan]. There may be many saved splits, with at most
/// one *active* at a time. The original single-plan API ([activePlan] /
/// [watchActivePlan] / [savePlan] / [deletePlan]) is preserved as a back-compat
/// facade over the active split; the multi-split API below is additive.
abstract interface class WorkoutPlanRepository {
  // --- Back-compat: unchanged signatures, must keep working ---

  /// The active split (or null).
  WorkoutPlan? get activePlan;

  /// The active split, reactive.
  Stream<WorkoutPlan?> watchActivePlan();

  /// Creates or replaces [plan] by id (idempotent edit). Alias for [saveSplit];
  /// if there is no active split yet, the saved plan becomes active.
  Future<void> savePlan(WorkoutPlan plan);

  /// Removes the plan. Alias for [deleteSplit].
  Future<void> deletePlan(String id);

  // --- New: multi-split (additive) ---

  /// All saved splits in createdAt order; `[]` if none.
  List<WorkoutPlan> get splits;

  /// All splits, reactive, in createdAt order.
  Stream<List<WorkoutPlan>> watchSplits();

  /// Id of the active split, or null.
  String? get activeSplitId;

  /// Moves the active pointer to an existing split. Never touches the split
  /// history; emits the new active on [watchActivePlan].
  Future<void> setActiveSplit(String id);

  /// Creates or replaces [plan] by id (normalized). If there is no active split
  /// yet, the just-saved split becomes active.
  Future<void> saveSplit(WorkoutPlan plan);

  /// Removes the split. If it was active, the pointer falls to the first
  /// remaining split (createdAt order) or null if none remain.
  Future<void> deleteSplit(String id);
}
