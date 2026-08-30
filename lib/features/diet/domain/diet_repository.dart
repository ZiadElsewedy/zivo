import 'body_profile.dart';
import 'diet_plan.dart';
import 'diet_plan_status.dart';
import 'nutrition/custom_food.dart';
import 'nutrition/food_log_entry.dart';
import 'nutrition_targets.dart';

/// The seam between the app and diet plan storage (in-memory demo for now,
/// Firestore-backed later).
///
/// The user keeps a **library** of plans — a cut, a bulk, the one their coach
/// wrote — of which **exactly one is active**. That invariant is the
/// repository's to hold, not its callers': [savePlan] of an active plan and
/// [setActivePlan] both archive whatever was active before, so no caller can
/// leave two plans claiming to be the one in force. Everything else in the app
/// reads [activePlan] and is unaffected by the library existing.
abstract interface class DietRepository {
  /// The plan currently in force, or null when every plan is archived (or
  /// there are none). Derived from status — not from there being one document.
  DietPlan? get activePlan;
  Stream<DietPlan?> watchActivePlan();

  /// Every plan the user has, newest first, whatever its status.
  List<DietPlan> get plans;
  Stream<List<DietPlan>> watchPlans();

  /// Creates or replaces a plan by id (idempotent edit). Saving one with
  /// [DietPlanStatus.active] archives whichever plan was active before.
  Future<void> savePlan(DietPlan plan);

  /// Makes [id] the plan in force, archiving the one that was. A no-op if
  /// [id] doesn't exist — activating a plan that isn't there must not
  /// silently leave the user with no active plan at all.
  Future<void> setActivePlan(String id);

  /// Puts a plan away without deleting it: it leaves the Diet screen, keeps
  /// its history, and can be brought back with [setActivePlan]. This — not
  /// [deletePlan] — is what "I'm not following this any more" means.
  Future<void> archivePlan(String id);

  /// Permanently removes the plan. `dietEntries` referencing its meal ids are
  /// left in place (a benign orphan — no bulk-delete of the consumption log),
  /// which is also why archiving is the softer option offered first.
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

  /// The user's stored body data, or null when they haven't given it.
  ///
  /// Null is a real state, like [currentTargets] is: without it ZIVO cannot
  /// say what a plan does to this person, and the honest response is to ask
  /// rather than to assume an average body. Note that saving this **never**
  /// implies a target — see [BodyProfile].
  BodyProfile? get currentBodyProfile;
  Stream<BodyProfile?> watchBodyProfile();

  /// Creates or replaces the body profile (there is only ever one).
  Future<void> saveBodyProfile(BodyProfile profile);

  /// Removes it, back to the unset state.
  Future<void> clearBodyProfile();

  /// The set of meal ids marked eaten on [day].
  Stream<Set<String>> watchConsumed(DateTime day);

  /// Ticks or un-ticks a planned meal.
  ///
  /// This also **materialises the meal's items into the food log** (as
  /// [FoodLogOrigin.plannedMeal] entries) and removes exactly those on
  /// un-tick. The interaction the user sees is unchanged; what changes is that
  /// the data underneath becomes a ledger of foods rather than a row of
  /// checkboxes — so a user who ate three of the four items can say so, and
  /// "consumed" stops being an assumption (see `docs/DIET_COACH_AUDIT.md`, T6).
  Future<void> setMealEaten({
    required String mealId,
    required DateTime day,
    required bool eaten,
  });

  /// Everything logged on [day], oldest first.
  ///
  /// **This is the consumption ledger.** An empty log for a past day means
  /// nothing was recorded then, not that nothing was eaten — callers fall back
  /// to the planned figures of ticked meals and must say that they did.
  Stream<List<FoodLogEntry>> watchFoodLog(DateTime day);

  /// Appends [entries] to the log. Takes a list because one thing a person
  /// says ("two eggs and 100g rice") is often several entries, and they should
  /// land together or not at all.
  Future<void> logFood(List<FoodLogEntry> entries);

  /// Removes one entry by id.
  Future<void> removeFoodLogEntry(String id);

  /// The foods the user has defined themselves, newest first.
  Stream<List<CustomFood>> watchCustomFoods();

  /// A one-shot read, for the resolver — which needs the current list on every
  /// lookup and can't hold a subscription.
  Future<List<CustomFood>> listCustomFoods();

  /// Creates or replaces a user-defined food by id.
  Future<void> saveCustomFood(CustomFood food);

  /// Deletes a user-defined food. Past log entries keep their stored figures
  /// and name — deleting the definition must not rewrite history.
  Future<void> deleteCustomFood(String id);
}
