import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_repository.dart';
import 'package:zivo/features/diet/domain/nutrition/custom_food.dart';
import 'package:zivo/features/diet/domain/nutrition/food_log_entry.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';

/// A do-nothing [DietRepository] for tests that only care about one corner of
/// it.
///
/// Extend it and override just the members under test. Without this, every
/// addition to the repository interface breaks every hand-written fake in the
/// suite — which is how a green run turns into a compile error that looks
/// like a test failure in an unrelated file.
abstract class DietRepositoryStub implements DietRepository {
  @override
  DietPlan? get activePlan => null;

  @override
  Stream<DietPlan?> watchActivePlan() => const Stream.empty();

  @override
  Future<void> savePlan(DietPlan plan) async {}

  @override
  Future<void> deletePlan(String id) async {}

  @override
  NutritionTargets? get currentTargets => null;

  @override
  Stream<NutritionTargets?> watchTargets() => Stream.value(null);

  @override
  Future<void> saveTargets(NutritionTargets targets) async {}

  @override
  Future<void> clearTargets() async {}

  @override
  Stream<Set<String>> watchConsumed(DateTime day) =>
      Stream.value(const <String>{});

  @override
  Future<void> setMealEaten({
    required String mealId,
    required DateTime day,
    required bool eaten,
  }) async {}

  @override
  Stream<List<FoodLogEntry>> watchFoodLog(DateTime day) =>
      Stream.value(const <FoodLogEntry>[]);

  @override
  Future<void> logFood(List<FoodLogEntry> entries) async {}

  @override
  Future<void> removeFoodLogEntry(String id) async {}

  @override
  Stream<List<CustomFood>> watchCustomFoods() =>
      Stream.value(const <CustomFood>[]);

  @override
  Future<List<CustomFood>> listCustomFoods() async => const [];

  @override
  Future<void> saveCustomFood(CustomFood food) async {}

  @override
  Future<void> deleteCustomFood(String id) async {}
}
