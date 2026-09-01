import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/data/bundled_food_database.dart';
import 'package:zivo/features/diet/domain/nutrition/food_reference.dart';
import 'package:zivo/features/diet/domain/nutrition/nutrition_calculator.dart';
import 'package:zivo/features/diet/domain/nutrition/resolved_food.dart';

/// The Dart half of the shared golden vectors.
///
/// `test/fixtures/nutrition_vectors.json` is run by BOTH this file and
/// `functions/nutrition/food_db.test.js`. The app resolves and computes
/// nutrition in Dart; the coach does it in JavaScript. Comment discipline is
/// not a guarantee that two implementations agree — a fixture both must
/// reproduce exactly is. Change one side and this fails until they match
/// again, which is the intended friction (docs/DIET_COACH_AUDIT.md, T13).
void main() {
  late Map<String, dynamic> vectors;
  late BundledFoodDatabase db;

  setUpAll(() {
    vectors = json.decode(
      File('test/fixtures/nutrition_vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    db = BundledFoodDatabase(
      loadAsset: () => File('assets/nutrition/foods.json').readAsString(),
    );
  });

  test('the catalog is the one the vectors were generated from', () {
    // Rebuilding the catalog without regenerating the vectors would leave both
    // suites asserting stale numbers. This makes that a failure, not a drift.
    final raw = File('assets/nutrition/foods.json').readAsStringSync();
    final digest = sha256.convert(utf8.encode(raw.trimRight())).toString();
    expect(digest, vectors['catalogSha256']);
  });

  test('golden vectors: lookups resolve identically to the fixture', () async {
    for (final spec in (vectors['lookups'] as List).cast<Map<String, dynamic>>()) {
      final query = spec['query'] as String;
      final preparation = foodPreparationFromName(spec['preparation'] as String?);
      final expected = spec['expected'] as Map<String, dynamic>;
      final label = '$query${spec['preparation'] == null ? '' : ' [${spec['preparation']}]'}';

      final match = await db.resolve(
        query,
        preparation: spec['preparation'] == null ? null : preparation,
      );

      switch (expected['kind'] as String) {
        case 'resolved':
          expect(match, isA<FoodResolved>(), reason: label);
          final food = (match as FoodResolved).food;
          expect(food.id, expected['foodId'], reason: label);
          expect(food.kcalPer100g, expected['kcalPer100g'], reason: label);
          expect(food.preparation.name, expected['preparation'], reason: label);
        case 'ambiguous':
          expect(match, isA<FoodAmbiguous>(), reason: label);
          final candidates = (match as FoodAmbiguous).candidates;
          expect(
            candidates.map((f) => f.id).toList(),
            (expected['candidateIds'] as List).cast<String>(),
            reason: label,
          );
        case 'notFound':
          expect(match, isA<FoodNotFound>(), reason: label);
        default:
          fail('unknown expected kind for $label');
      }
    }
  });

  test('golden vectors: computations match the fixture exactly', () async {
    for (final spec
        in (vectors['computations'] as List).cast<Map<String, dynamic>>()) {
      final food = await db.byId(spec['foodId'] as String);
      expect(food, isNotNull, reason: 'missing food ${spec['foodId']}');
      final expected = spec['expected'] as Map<String, dynamic>;
      final label =
          '${spec['foodId']} ${spec['quantity']}${spec['unit']}';

      final result = nutritionFor(
        food: food!,
        quantity: (spec['quantity'] as num).toDouble(),
        unit: spec['unit'] as String,
      );

      if (expected.containsKey('unresolved')) {
        expect(result, isA<QuantityUnresolved>(), reason: label);
        expect(
          (result as QuantityUnresolved).problem.name,
          expected['unresolved'],
          reason: label,
        );
        continue;
      }

      expect(result, isA<ResolvedNutrition>(), reason: label);
      final nutrition = result as ResolvedNutrition;
      expect(nutrition.grams, expected['grams'], reason: label);
      expect(nutrition.kcal, expected['kcal'], reason: label);
      expect(nutrition.proteinG, expected['proteinG'], reason: label);
      expect(nutrition.carbsG, expected['carbsG'], reason: label);
      expect(nutrition.fatG, expected['fatG'], reason: label);
      expect(nutrition.sourceRef, expected['sourceRef'], reason: label);
    }
  });

  test('the app and server ship the identical catalog', () {
    // Two copies exist so the server never reaches into the Flutter asset
    // tree. They are written together by the build script; if they diverge,
    // the screen and the coach start quoting different numbers, silently.
    expect(
      File('assets/nutrition/foods.json').readAsStringSync(),
      File('functions/nutrition/foods.json').readAsStringSync(),
    );
  });
}
