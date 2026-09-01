import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_goal.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/meal.dart';
import 'package:zivo/features/diet/domain/nutrition/composite_food_resolver.dart';
import 'package:zivo/features/diet/domain/nutrition/custom_food.dart';
import 'package:zivo/features/diet/domain/nutrition/food_log_entry.dart';
import 'package:zivo/features/diet/domain/nutrition/food_reference.dart';
import 'package:zivo/features/diet/domain/nutrition/food_resolver.dart';
import 'package:zivo/features/diet/domain/nutrition/planned_meal_log.dart';
import 'package:zivo/features/diet/domain/nutrition/resolved_food.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/domain/diet_state.dart';
import 'package:zivo/features/diet/domain/diet_state_builder.dart';

FoodLogEntry _entry({
  String id = 'e1',
  int kcal = 300,
  double protein = 20,
  double carbs = 30,
  double fat = 10,
  FoodLogOrigin origin = FoodLogOrigin.logged,
  bool estimated = false,
  String? mealId,
}) => FoodLogEntry(
  id: id,
  day: DateTime(2026, 8, 30),
  loggedAt: DateTime(2026, 8, 30, 12),
  foodId: 'usda:1',
  foodName: 'Test food',
  quantity: 100,
  unit: 'g',
  grams: 100,
  kcal: kcal,
  proteinG: protein,
  carbsG: carbs,
  fatG: fat,
  source: NutritionSource.usdaFdc,
  sourceRef: '1',
  origin: origin,
  estimated: estimated,
  mealId: mealId,
);

NutritionTargets _targets({int calories = 2000}) => NutritionTargets(
  goal: DietGoal.fatLoss,
  calories: calories,
  proteinG: 150,
  source: TargetSource.manual,
  updatedAt: DateTime(2026, 8, 30),
);

void main() {
  group('totalsOf', () {
    test('sums entries and counts where they came from', () {
      final totals = totalsOf([
        _entry(id: 'a', kcal: 300),
        _entry(id: 'b', kcal: 200, origin: FoodLogOrigin.plannedMeal),
      ]);
      expect(totals.kcal, 500);
      expect(totals.proteinG, 40);
      expect(totals.entryCount, 2);
      expect(totals.loggedCount, 1);
      expect(totals.plannedCount, 1);
      expect(totals.allFromPlannedMeals, isFalse);
    });

    test('a day of only ticked meals is flagged as assumed', () {
      // "You ate 1,850" and "the plan values what you ticked at 1,850" are
      // different claims, and something has to be able to tell them apart.
      final totals = totalsOf([
        _entry(id: 'a', origin: FoodLogOrigin.plannedMeal),
        _entry(id: 'b', origin: FoodLogOrigin.plannedMeal),
      ]);
      expect(totals.allFromPlannedMeals, isTrue);
    });

    test('an empty day is not "assumed" — there is nothing to assume', () {
      expect(totalsOf(const []).allFromPlannedMeals, isFalse);
      expect(FoodLogTotals.empty.kcal, 0);
    });

    test('one estimated entry makes the whole total an estimate', () {
      expect(totalsOf([_entry(), _entry(id: 'b')]).estimated, isFalse);
      expect(
        totalsOf([_entry(), _entry(id: 'b', estimated: true)]).estimated,
        isTrue,
      );
    });
  });

  group('entriesForPlannedMeal', () {
    const meal = Meal(
      id: 'm1',
      label: 'Lunch',
      order: 0,
      items: [
        FoodItem(
          name: 'Rice',
          quantity: 150,
          unit: 'g',
          calories: 210,
          proteinG: 4,
          carbsG: 45,
          estimated: true,
        ),
        FoodItem(name: 'Chicken', quantity: 200, unit: 'g', calories: 330),
      ],
    );

    test('one entry per item, carrying the plan as its source', () {
      final entries = entriesForPlannedMeal(
        meal: meal,
        day: DateTime(2026, 8, 30, 15),
        now: DateTime(2026, 8, 30, 15),
        idPrefix: '2026-08-30__m1',
      );

      expect(entries.length, 2);
      expect(entries.map((e) => e.id), ['2026-08-30__m1-0', '2026-08-30__m1-1']);
      expect(entries.every((e) => e.mealId == 'm1'), isTrue);
      expect(
        entries.every((e) => e.origin == FoodLogOrigin.plannedMeal),
        isTrue,
      );
      // Not a reference value and it says so.
      expect(
        entries.every((e) => e.source == NutritionSource.dietPlan),
        isTrue,
      );
      // The day is normalised to midnight regardless of when it was ticked.
      expect(entries.first.day, DateTime(2026, 8, 30));
    });

    test("the item's estimate provenance rides along, not laundered away", () {
      final entries = entriesForPlannedMeal(
        meal: meal,
        day: DateTime(2026, 8, 30),
        now: DateTime(2026, 8, 30),
        idPrefix: 'x',
      );
      expect(entries[0].estimated, isTrue);
      expect(entries[1].estimated, isFalse);
    });

    test('a non-gram unit records no mass rather than inferring one', () {
      const pieces = Meal(
        id: 'm2',
        label: 'Snack',
        order: 0,
        items: [
          FoodItem(name: 'Banana', quantity: 1, unit: 'pcs', calories: 90),
        ],
      );
      final entries = entriesForPlannedMeal(
        meal: pieces,
        day: DateTime(2026, 8, 30),
        now: DateTime(2026, 8, 30),
        idPrefix: 'x',
      );
      expect(entries.single.grams, 0);
      expect(entries.single.quantity, 1);
      expect(entries.single.unit, 'pcs');
    });
  });

  group('ticking a meal writes the log', () {
    test('materialises the meal, and un-ticking removes exactly those entries',
        () async {
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final day = DateTime.now();

      // Something the user logged themselves, which must survive everything.
      await diet.logFood([
        FoodLogEntry(
          id: 'mine',
          day: DateTime(day.year, day.month, day.day),
          loggedAt: day,
          foodId: 'usda:1',
          foodName: 'Coffee',
          quantity: 200,
          unit: 'g',
          grams: 200,
          kcal: 5,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
          source: NutritionSource.usdaFdc,
          sourceRef: '1',
          origin: FoodLogOrigin.logged,
        ),
      ]);

      await diet.setMealEaten(
        mealId: 'seed-meal-breakfast',
        day: day,
        eaten: true,
      );
      var log = await diet.watchFoodLog(day).first;
      // Breakfast has two items in the seeded plan.
      expect(log.where((e) => e.mealId == 'seed-meal-breakfast').length, 2);
      expect(log.any((e) => e.id == 'mine'), isTrue);

      await diet.setMealEaten(
        mealId: 'seed-meal-breakfast',
        day: day,
        eaten: false,
      );
      log = await diet.watchFoodLog(day).first;
      expect(log.any((e) => e.mealId == 'seed-meal-breakfast'), isFalse);
      expect(
        log.any((e) => e.id == 'mine'),
        isTrue,
        reason: "un-ticking a meal must never touch the user's own entries",
      );
    });

    test('double-ticking does not double-count', () async {
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final day = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await diet.setMealEaten(
          mealId: 'seed-meal-lunch',
          day: day,
          eaten: true,
        );
      }
      final log = await diet.watchFoodLog(day).first;
      expect(log.length, 2);
    });

    test('removing ONE item of a ticked meal leaves it ticked — that is what '
        'a half-eaten meal looks like', () async {
      // The tick says "I ate from this meal"; the log carries how much. A user
      // who skipped the rice still ate the chicken, and neither un-ticking the
      // whole meal nor pretending they ate all of it would be true.
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final day = DateTime.now();
      await diet.setMealEaten(
        mealId: 'seed-meal-lunch',
        day: day,
        eaten: true,
      );
      final log = await diet.watchFoodLog(day).first;
      expect(log.length, 2);

      await diet.removeFoodLogEntry(log.first.id);

      expect(await diet.watchConsumed(day).first, contains('seed-meal-lunch'));
      expect((await diet.watchFoodLog(day).first).length, 1);
    });

    test('removing the LAST of a meal\'s items un-ticks it', () async {
      // Otherwise the meal reads as eaten while none of its food is in the
      // ledger — two views of the same thing, disagreeing.
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final day = DateTime.now();
      await diet.setMealEaten(
        mealId: 'seed-meal-lunch',
        day: day,
        eaten: true,
      );

      for (final entry in await diet.watchFoodLog(day).first) {
        await diet.removeFoodLogEntry(entry.id);
      }

      expect(
        await diet.watchConsumed(day).first,
        isNot(contains('seed-meal-lunch')),
      );
    });
  });

  group('buildTargetProgress with a log', () {
    final day = DietDay(
      label: 'Every day',
      meals: [
        Meal(
          id: 'm1',
          label: 'Lunch',
          order: 0,
          items: const [
            FoodItem(name: 'Rice', quantity: 150, unit: 'g', calories: 400),
          ],
        ),
      ],
    );

    test('the log wins over the plan when it has anything in it', () {
      // The user ticked the 400 kcal meal but the log says 300 — because they
      // ate less of it, or swapped it. The measurement wins.
      final progress = buildDietState(
        dayKey: '2026-08-30',
        weekday: 7,
        planName: null,
        targets: _targets(),
        day: day,
        consumedMealIds: {'m1'},
        log: [_entry(kcal: 300)],
      );
      expect(progress.consumed.kcal, 300);
      expect(progress.remainingKcal, 1700);
      expect(progress.consumed.basis, ConsumedBasis.logged);
      expect(progress.quality.consumedIsAssumed, isFalse);
      expect(progress.consumed.loggedCount, 1);
    });

    test('an empty log falls back to ticked meals, and says that it did', () {
      final progress = buildDietState(
        dayKey: '2026-08-30',
        weekday: 7,
        planName: null,
        targets: _targets(),
        day: day,
        consumedMealIds: {'m1'},
        log: const [],
      );
      expect(progress.consumed.kcal, 400);
      expect(progress.consumed.basis, ConsumedBasis.tickedPlanMeals);
      expect(progress.quality.consumedIsAssumed, isTrue);
      expect(progress.consumed.loggedCount, 0);
    });

    test('a log of only materialised entries is still flagged as assumed', () {
      final progress = buildDietState(
        dayKey: '2026-08-30',
        weekday: 7,
        planName: null,
        targets: _targets(),
        day: day,
        consumedMealIds: {'m1'},
        log: [_entry(kcal: 400, origin: FoodLogOrigin.plannedMeal)],
      );
      expect(progress.consumed.kcal, 400);
      expect(progress.consumed.basis, ConsumedBasis.tickedPlanMeals);
      expect(progress.quality.consumedIsAssumed, isTrue);
    });

    test('logged food counts even with no plan for the day', () {
      final progress = buildDietState(
        dayKey: '2026-08-30',
        weekday: 7,
        planName: null,
        targets: _targets(),
        day: null,
        consumedMealIds: const <String>{},
        log: [_entry(kcal: 550)],
      );
      expect(progress.consumed.kcal, 550);
      expect(progress.remainingKcal, 1450);
    });
  });

  group('CompositeFoodResolver', () {
    final custom = CustomFood(
      id: 'c1',
      name: 'Koshari (mum)',
      kcalPer100g: 150,
      proteinPer100g: 5,
      carbsPer100g: 27,
      fatPer100g: 3,
      createdAt: DateTime(2026, 8, 30),
    );

    FoodResolver resolverWith(List<CustomFood> foods) => CompositeFoodResolver(
      catalog: _EmptyCatalog(),
      customFoods: () async => foods,
    );

    test("a user's own food resolves, and is labelled as theirs", () async {
      final match = await resolverWith([custom]).resolve('koshari');
      expect(match, isA<FoodResolved>());
      final food = (match as FoodResolved).food;
      expect(food.source, NutritionSource.userCustom);
      expect(food.id, 'custom:c1');
      expect(food.kcalPer100g, 150);
    });

    test('falls through to the reference catalog when nothing matches',
        () async {
      final match = await resolverWith([custom]).resolve('chicken');
      expect(match, isA<FoodNotFound>());
    });

    test('byId returns null for a deleted custom food, never a lookalike',
        () async {
      // Substituting here would silently rewrite what a past log entry meant.
      final match = await resolverWith(const []).byId('custom:c1');
      expect(match, isNull);
    });

    test('every query word must match, same rule as the bundled catalog',
        () async {
      final resolver = resolverWith([custom]);
      expect(await resolver.resolve('koshari mum'), isA<FoodResolved>());
      expect(await resolver.resolve('koshari chicken'), isA<FoodNotFound>());
    });
  });

  group('custom foods round-trip', () {
    test('save, list and delete through the repository', () async {
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      expect(await diet.listCustomFoods(), isEmpty);

      final food = CustomFood(
        id: 'c1',
        name: 'Ful medames',
        kcalPer100g: 110,
        proteinPer100g: 7,
        carbsPer100g: 16,
        fatPer100g: 2,
        createdAt: DateTime(2026, 8, 30),
      );
      await diet.saveCustomFood(food);
      expect((await diet.listCustomFoods()).single.name, 'Ful medames');

      await diet.deleteCustomFood('c1');
      expect(await diet.listCustomFoods(), isEmpty);
    });
  });
}

/// A catalog with nothing in it, so composite behaviour is tested in isolation
/// from the real 1 MB asset.
class _EmptyCatalog implements FoodResolver {
  @override
  Future<FoodReference?> byId(String id) async => null;

  @override
  Future<List<FoodReference>> search(String query, {int limit = 20}) async =>
      const [];

  @override
  Future<FoodMatch> resolve(String query, {FoodPreparation? preparation}) async =>
      FoodNotFound(query: query);
}
