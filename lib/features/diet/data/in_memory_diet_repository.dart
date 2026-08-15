import 'dart:async';

import '../domain/diet_day.dart';
import '../domain/diet_plan.dart';
import '../domain/diet_plan_status.dart';
import '../domain/diet_repository.dart';
import '../domain/diet_source.dart';
import '../domain/food_item.dart';
import '../domain/meal.dart';

/// 'yyyy-MM-dd' for [day]'s local calendar date.
String _dayKey(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '$y-$m-$dd';
}

/// Demo store: one active diet plan plus per-day consumption, in memory,
/// broadcasting changes. Seeded with a balanced every-day plan (Breakfast /
/// Lunch / Dinner) so the page opens with something to show.
class InMemoryDietRepository implements DietRepository {
  InMemoryDietRepository() {
    _plan = _seedPlan();
  }

  late DietPlan _plan;
  final Map<String, Set<String>> _consumed = {};

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
    if (eaten) {
      set.add(mealId);
    } else {
      set.remove(mealId);
    }
    _consumedController.add(key);
  }

  void dispose() {
    _planController.close();
    _consumedController.close();
  }
}
