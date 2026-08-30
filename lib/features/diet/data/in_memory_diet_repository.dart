import 'dart:async';

import '../domain/diet_day.dart';
import '../domain/diet_format.dart';
import '../domain/diet_plan.dart';
import '../domain/diet_plan_status.dart';
import '../domain/diet_repository.dart';
import '../domain/diet_source.dart';
import '../domain/food_item.dart';
import '../domain/meal.dart';
import '../domain/nutrition/custom_food.dart';
import '../domain/nutrition/food_log_entry.dart';
import '../domain/nutrition/planned_meal_log.dart';
import '../domain/nutrition_targets.dart';

/// 'yyyy-MM-dd' for [day]'s local calendar date.
String _dayKey(DateTime day) => dietDayKey(day);

/// Demo store: one active diet plan plus per-day consumption, in memory,
/// broadcasting changes. Seeded with a balanced every-day plan (Breakfast /
/// Lunch / Dinner) so the page opens with something to show.
class InMemoryDietRepository implements DietRepository {
  InMemoryDietRepository() {
    _plan = _seedPlan();
  }

  DietPlan? _plan;
  final Map<String, Set<String>> _consumed = {};

  /// Deliberately null at seed. The demo plan exists so the page has something
  /// to render; a demo *target* would be a number the user never chose, which
  /// is the one thing this feature must never show.
  NutritionTargets? _targets;

  final StreamController<NutritionTargets?> _targetsController =
      StreamController<NutritionTargets?>.broadcast();

  /// The food log, keyed by day. Empty at seed: the demo plan gives the page
  /// something to render, but a demo *meal you ate* would be a fabricated
  /// measurement, which is the one thing this ledger must never contain.
  final Map<String, List<FoodLogEntry>> _foodLog = {};
  final StreamController<String> _foodLogController =
      StreamController<String>.broadcast();

  final List<CustomFood> _customFoods = [];
  final StreamController<List<CustomFood>> _customFoodsController =
      StreamController<List<CustomFood>>.broadcast();

  final StreamController<DietPlan?> _planController =
      StreamController<DietPlan?>.broadcast();

  /// Emits the `dayKey` whose consumption changed; [watchConsumed] filters to
  /// the day it was asked to watch.
  final StreamController<String> _consumedController =
      StreamController<String>.broadcast();

  DietPlan _seedPlan() {
    final now = DateTime.now();
    return DietPlan(
      id: 'seed-diet-1',
      name: 'Balanced — 2200 kcal',
      status: DietPlanStatus.active,
      source: DietSource.manual,
      createdAt: now,
      updatedAt: now,
      days: const [
        DietDay(
          weekday: null,
          label: 'Every day',
          meals: [
            Meal(
              id: 'seed-meal-breakfast',
              label: 'Breakfast',
              order: 0,
              items: [
                FoodItem(
                  name: 'Oats',
                  quantity: 60,
                  unit: 'g',
                  calories: 220,
                  proteinG: 8,
                  carbsG: 38,
                  fatG: 4,
                ),
                FoodItem(name: 'Banana', quantity: 1, unit: 'pcs', calories: 90, carbsG: 23),
              ],
            ),
            Meal(
              id: 'seed-meal-lunch',
              label: 'Lunch',
              order: 1,
              items: [
                FoodItem(
                  name: 'Rice',
                  quantity: 150,
                  unit: 'g',
                  calories: 210,
                  proteinG: 4,
                  carbsG: 45,
                ),
                FoodItem(
                  name: 'Chicken breast',
                  quantity: 200,
                  unit: 'g',
                  calories: 330,
                  proteinG: 62,
                  fatG: 7,
                ),
              ],
            ),
            Meal(
              id: 'seed-meal-dinner',
              label: 'Dinner',
              order: 2,
              items: [
                FoodItem(
                  name: 'Salmon',
                  quantity: 180,
                  unit: 'g',
                  calories: 370,
                  proteinG: 40,
                  fatG: 22,
                ),
                FoodItem(name: 'Broccoli', quantity: 150, unit: 'g', calories: 50, carbsG: 10),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  DietPlan? get activePlan => _plan;

  @override
  Stream<DietPlan?> watchActivePlan() async* {
    yield activePlan;
    yield* _planController.stream;
  }

  @override
  Future<void> savePlan(DietPlan plan) async {
    _plan = plan;
    _planController.add(_plan);
  }

  @override
  Future<void> deletePlan(String id) async {
    if (_plan?.id != id) return;
    _plan = null;
    _planController.add(_plan);
  }

  @override
  NutritionTargets? get currentTargets => _targets;

  @override
  Stream<NutritionTargets?> watchTargets() async* {
    yield _targets;
    yield* _targetsController.stream;
  }

  @override
  Future<void> saveTargets(NutritionTargets targets) async {
    _targets = targets;
    _targetsController.add(_targets);
  }

  @override
  Future<void> clearTargets() async {
    _targets = null;
    _targetsController.add(null);
  }

  @override
  Stream<Set<String>> watchConsumed(DateTime day) async* {
    final key = _dayKey(day);
    yield Set.unmodifiable(_consumed[key] ?? const <String>{});
    yield* _consumedController.stream
        .where((changedKey) => changedKey == key)
        .map((_) => Set<String>.unmodifiable(_consumed[key] ?? const <String>{}));
  }

  @override
  Future<void> setMealEaten({
    required String mealId,
    required DateTime day,
    required bool eaten,
  }) async {
    final key = _dayKey(day);
    final set = _consumed.putIfAbsent(key, () => <String>{});
    final log = _foodLog.putIfAbsent(key, () => <FoodLogEntry>[]);

    if (eaten) {
      set.add(mealId);
      // Materialise the meal's items into the log — see
      // `entriesForPlannedMeal`. Guarded so a double-tick can't double-count.
      if (!log.any((e) => e.mealId == mealId)) {
        final meal = _mealById(mealId);
        if (meal != null) {
          log.addAll(
            entriesForPlannedMeal(
              meal: meal,
              day: day,
              now: DateTime.now(),
              idPrefix: '$key-$mealId',
            ),
          );
        }
      }
    } else {
      set.remove(mealId);
      // Remove exactly the entries this meal created, never a user's own.
      log.removeWhere((e) => e.mealId == mealId);
    }
    _consumedController.add(key);
    _foodLogController.add(key);
  }

  Meal? _mealById(String mealId) {
    for (final day in _plan?.days ?? const <DietDay>[]) {
      for (final meal in day.meals) {
        if (meal.id == mealId) return meal;
      }
    }
    return null;
  }

  @override
  Stream<List<FoodLogEntry>> watchFoodLog(DateTime day) async* {
    final key = _dayKey(day);
    yield List.unmodifiable(_foodLog[key] ?? const <FoodLogEntry>[]);
    yield* _foodLogController.stream
        .where((changed) => changed == key)
        .map((_) =>
            List<FoodLogEntry>.unmodifiable(_foodLog[key] ?? const []));
  }

  @override
  Future<void> logFood(List<FoodLogEntry> entries) async {
    for (final entry in entries) {
      final key = _dayKey(entry.day);
      _foodLog.putIfAbsent(key, () => <FoodLogEntry>[]).add(entry);
      _foodLogController.add(key);
    }
  }

  @override
  Future<void> removeFoodLogEntry(String id) async {
    for (final key in _foodLog.keys.toList()) {
      final before = _foodLog[key]!.length;
      _foodLog[key]!.removeWhere((e) => e.id == id);
      if (_foodLog[key]!.length != before) {
        // An entry materialised from a ticked meal: removing it by hand also
        // un-ticks the meal, so the two views can't contradict each other.
        _reconcileConsumed(key);
        _foodLogController.add(key);
      }
    }
  }

  /// Keeps the tick set consistent with the log after a manual removal.
  void _reconcileConsumed(String key) {
    final mealIds = _foodLog[key]!
        .map((e) => e.mealId)
        .whereType<String>()
        .toSet();
    final consumed = _consumed[key];
    if (consumed == null) return;
    final gone = consumed.difference(mealIds);
    if (gone.isEmpty) return;
    consumed.removeAll(gone);
    _consumedController.add(key);
  }

  @override
  Stream<List<CustomFood>> watchCustomFoods() async* {
    yield List.unmodifiable(_customFoods);
    yield* _customFoodsController.stream;
  }

  @override
  Future<List<CustomFood>> listCustomFoods() async =>
      List.unmodifiable(_customFoods);

  @override
  Future<void> saveCustomFood(CustomFood food) async {
    _customFoods.removeWhere((f) => f.id == food.id);
    _customFoods.insert(0, food);
    _customFoodsController.add(List.unmodifiable(_customFoods));
  }

  @override
  Future<void> deleteCustomFood(String id) async {
    _customFoods.removeWhere((f) => f.id == id);
    _customFoodsController.add(List.unmodifiable(_customFoods));
  }

  void dispose() {
    _planController.close();
    _consumedController.close();
    _targetsController.close();
    _foodLogController.close();
    _customFoodsController.close();
  }
}
