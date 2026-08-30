import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/data/bundled_food_database.dart';
import 'package:zivo/features/diet/domain/nutrition/food_reference.dart';
import 'package:zivo/features/diet/domain/nutrition/nutrition_calculator.dart';
import 'package:zivo/features/diet/domain/nutrition/resolved_food.dart';

/// Reads the real shipped catalog off disk rather than through `rootBundle`,
/// so these tests exercise the ACTUAL asset the app ships. A fixture would
/// prove the code works; only the real file proves the data does.
BundledFoodDatabase realCatalog() => BundledFoodDatabase(
  loadAsset: () => File('assets/nutrition/foods.json').readAsString(),
);

void main() {
  group('the shipped catalog', () {
    test('every row carries a traceable USDA source reference', () async {
      // The property the whole feature rests on: no figure exists in ZIVO
      // without a record behind it.
      final db = realCatalog();
      final foods = await db.search('chicken', limit: 50);
      expect(foods, isNotEmpty);
      for (final food in foods) {
        expect(food.source, NutritionSource.usdaFdc);
        expect(food.sourceRef, isNotEmpty);
        expect(int.tryParse(food.sourceRef), isNotNull,
            reason: 'sourceRef must be a real fdcId, not a label');
        expect(food.id, 'usda:${food.sourceRef}');
      }
    });

    test('known foods carry the published USDA values', () async {
      // If these drift, the catalog was rebuilt from different data — which
      // is exactly the thing a test should catch, not absorb.
      final db = realCatalog();

      // Chicken breast, meat only, cooked, roasted (fdcId 171477).
      final chicken = await db.byId('usda:171477');
      expect(chicken, isNotNull);
      expect(chicken!.kcalPer100g, 165);
      expect(chicken.proteinPer100g, 31);
      expect(chicken.fatPer100g, 3.6);
      expect(chicken.preparation, FoodPreparation.cooked);

      // Rice, white, long-grain, regular, raw, enriched (fdcId 168877).
      final rawRice = await db.byId('usda:168877');
      expect(rawRice!.kcalPer100g, 365);
      expect(rawRice.preparation, FoodPreparation.raw);

      // ...and its cooked form (fdcId 168878) — the ~3x difference that makes
      // preparation a real dimension rather than a nicety.
      final cookedRice = await db.byId('usda:168878');
      expect(cookedRice!.kcalPer100g, 130);
      expect(cookedRice.preparation, FoodPreparation.cooked);

      // Oil, olive, salad or cooking (fdcId 171413) — pure fat.
      final oil = await db.byId('usda:171413');
      expect(oil!.kcalPer100g, 884);
      expect(oil.fatPer100g, 100);
      expect(oil.proteinPer100g, 0);
    });

    test('a food that was never in the catalog resolves to null, not a '
        'lookalike', () async {
      final db = realCatalog();
      expect(await db.byId('usda:999999999'), isNull);
      expect(await db.byId('nonsense'), isNull);
    });
  });

  group('resolve', () {
    test('an unknown food is NotFound — never a nearest guess', () async {
      // The honest outcome. USDA covers regional cooking poorly, so this
      // happens often and must never be papered over with something close.
      final db = realCatalog();
      final match = await db.resolve('koshari');
      expect(match, isA<FoodNotFound>());
      expect((match as FoodNotFound).query, 'koshari');
    });

    test('"rice" is ambiguous, because raw and cooked are a 3x fork',
        () async {
      final db = realCatalog();
      final match = await db.resolve('rice white long-grain regular');

      expect(match, isA<FoodAmbiguous>(),
          reason: 'raw 365 kcal vs cooked 130 kcal is not a choice the app '
              'may make on the user\'s behalf');
      final candidates = (match as FoodAmbiguous).candidates;
      expect(candidates.length, greaterThan(1));
      expect(
        candidates.map((f) => f.preparation).toSet(),
        containsAll([FoodPreparation.raw, FoodPreparation.cooked]),
      );
    });

    test('naming the preparation resolves that same query cleanly', () async {
      // The answer to the question the ambiguity asked.
      final db = realCatalog();
      final match = await db.resolve(
        'rice white long-grain regular',
        preparation: FoodPreparation.cooked,
      );
      expect(match, isA<FoodResolved>());
      final food = (match as FoodResolved).food;
      expect(food.preparation, FoodPreparation.cooked);
      expect(food.kcalPer100g, 130);
    });

    test('close matches that AGREE on the numbers resolve without a question',
        () async {
      // Asking when the answer doesn't change anything is noise, not rigour.
      final db = realCatalog();
      final match = await db.resolve('egg whole raw fresh');
      expect(match, isA<FoodResolved>());
      expect((match as FoodResolved).food.kcalPer100g, 143);
    });

    test('every query word must appear — no partial-match drift', () async {
      // The failure mode this guards: "chicken breast" quietly matching
      // "chicken soup" because one word hit.
      final db = realCatalog();
      final results = await db.search('chicken breast', limit: 30);
      expect(results, isNotEmpty);
      for (final food in results) {
        final name = food.name.toLowerCase();
        expect(name, contains('chicken'));
        expect(name, contains('breast'));
      }
    });

    test('an empty query returns nothing rather than everything', () async {
      final db = realCatalog();
      expect(await db.search(''), isEmpty);
      expect(await db.resolve('   '), isA<FoodNotFound>());
    });

    test('ranking is deterministic across repeated calls', () async {
      final db = realCatalog();
      final first = await db.search('oats', limit: 10);
      final second = await db.search('oats', limit: 10);
      expect(first.map((f) => f.id).toList(), second.map((f) => f.id).toList());
    });
  });

  group('nutritionFor', () {
    late FoodReference chicken;
    late FoodReference oil;

    setUp(() async {
      final db = realCatalog();
      chicken = (await db.byId('usda:171477'))!;
      oil = (await db.byId('usda:171413'))!;
    });

    test('scales the source values by mass, exactly', () {
      // 200g of a 165 kcal/100g food is 330 kcal. No estimation anywhere.
      final result = nutritionFor(food: chicken, quantity: 200, unit: 'g')
          as ResolvedNutrition;
      expect(result.grams, 200);
      expect(result.kcal, 330);
      expect(result.proteinG, 62);
      expect(result.fatG, 7.2);
      // And it still knows where it came from.
      expect(result.source, NutritionSource.usdaFdc);
      expect(result.sourceRef, '171477');
    });

    test('converts mass units exactly', () {
      final oz = nutritionFor(food: chicken, quantity: 4, unit: 'oz')
          as ResolvedNutrition;
      expect(oz.grams, closeTo(113.4, 0.1));
      expect(oz.kcal, 187);

      final kg = nutritionFor(food: chicken, quantity: 0.5, unit: 'kg')
          as ResolvedNutrition;
      expect(kg.grams, 500);
      expect(kg.kcal, 825);
    });

    test('refuses a volume it has no measure for, instead of assuming a '
        'density', () {
      // "100ml of olive oil is 100g" is wrong by ~8%; for flour it is wrong by
      // a third. Refusing is the honest answer, and it says what WOULD work.
      final result = nutritionFor(food: oil, quantity: 100, unit: 'ml');
      expect(result, isA<QuantityUnresolved>());
      final problem = result as QuantityUnresolved;
      expect(problem.problem, QuantityProblem.unknownMeasure);
      expect(problem.unit, 'ml');
    });

    test('uses a measure the source recorded for THAT food', () {
      // Only ever the food's own portions — never a generic table.
      final withPortions = FoodReference(
        id: 'usda:1',
        name: 'Test food',
        preparation: FoodPreparation.raw,
        kcalPer100g: 100,
        proteinPer100g: 10,
        carbsPer100g: 10,
        fatPer100g: 1,
        source: NutritionSource.usdaFdc,
        sourceRef: '1',
        portions: const [FoodPortion(label: 'cup', grams: 240)],
      );

      final cup = nutritionFor(food: withPortions, quantity: 1, unit: 'cup')
          as ResolvedNutrition;
      expect(cup.grams, 240);
      expect(cup.kcal, 240);

      // A measure this food does NOT have is refused, and the refusal lists
      // the ones it does.
      final slice = nutritionFor(
        food: withPortions,
        quantity: 1,
        unit: 'slice',
      );
      expect(slice, isA<QuantityUnresolved>());
      expect((slice as QuantityUnresolved).availableMeasures, ['cup']);
    });

    test('rejects a zero or negative quantity', () {
      for (final quantity in [0.0, -5.0, double.nan]) {
        final result = nutritionFor(
          food: chicken,
          quantity: quantity,
          unit: 'g',
        );
        expect(result, isA<QuantityUnresolved>());
        expect(
          (result as QuantityUnresolved).problem,
          QuantityProblem.invalidQuantity,
        );
      }
    });

    test('is deterministic', () {
      final a = nutritionFor(food: chicken, quantity: 173, unit: 'g')
          as ResolvedNutrition;
      final b = nutritionFor(food: chicken, quantity: 173, unit: 'g')
          as ResolvedNutrition;
      expect(a.kcal, b.kcal);
      expect(a.proteinG, b.proteinG);
    });
  });
}
