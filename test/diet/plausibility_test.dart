import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/nutrition/plausibility.dart';

/// The cross-check exists to catch a model contradicting itself, and it is
/// tuned so that a *real* plan never trips it — a flag the user learns to
/// ignore is worse than no flag. Half of these assert it stays quiet.

void main() {
  group('stays quiet', () {
    test('an item with no calorie figure is unchecked, not passed', () {
      final check = crossCheckNutrition(proteinG: 30, carbsG: 40, fatG: 10);
      expect(check.agreement, NutritionAgreement.unchecked);
      expect(check.disagrees, isFalse);
      expect(nutritionCrossCheckNote(check), isNull);
    });

    test('an item with no macros is unchecked — most of the plan is here', () {
      // The common case by far: a calorie figure and nothing to compare it
      // to. Reporting this as "fine" would make the check decoration.
      expect(
        crossCheckNutrition(calories: 400).agreement,
        NutritionAgreement.unchecked,
      );
    });

    test('a real item agrees: 165 kcal of chicken breast', () {
      final check = crossCheckNutrition(
        calories: 165,
        proteinG: 31,
        carbsG: 0,
        fatG: 3.6,
      );
      expect(check.agreement, NutritionAgreement.agrees);
      expect(check.impliedKcal, 156);
    });

    test('whole-gram rounding and a few kcal of slop never trip it', () {
      // 40/45/8 → 412 implied. A label saying 430 is not a contradiction.
      expect(
        crossCheckNutrition(
          calories: 430,
          proteinG: 40,
          carbsG: 45,
          fatG: 8,
        ).agreement,
        NutritionAgreement.agrees,
      );
    });

    test('a missing macro explains a high figure, so it is never flagged', () {
      // 20 g protein recorded and nothing else: 80 implied, 500 stated. The
      // carbs and fat nobody wrote down are exactly what fills that gap.
      final check = crossCheckNutrition(calories: 500, proteinG: 20);
      expect(check.macrosPartial, isTrue);
      expect(check.agreement, NutritionAgreement.agrees);
    });

    test('alcohol-shaped items are left alone — 7 kcal/g is not Atwater', () {
      // A 150 kcal glass of wine with ~4 g of carbs. Flagging every drink
      // would train the user to ignore the flag.
      final check = crossCheckNutrition(calories: 150, carbsG: 4);
      expect(check.agreement, NutritionAgreement.agrees);
    });
  });

  group('speaks up', () {
    test('a figure its own macros already exceed', () {
      // The audit's example: 600 kcal against macros worth 107.
      final check = crossCheckNutrition(
        calories: 600,
        proteinG: 12,
        carbsG: 8,
        fatG: 3,
      );
      expect(check.agreement, NutritionAgreement.statedAboveMacros);
      expect(check.disagrees, isTrue);
      expect(check.impliedKcal, 107);
      expect(
        nutritionCrossCheckNote(check),
        'Says 600 kcal; its macros come to 107',
      );
    });

    test('a figure lower than the macros alone require', () {
      // 50 g protein + 60 g carbs + 20 g fat = 620. Claiming 300 is not
      // possible whatever else is in it.
      final check = crossCheckNutrition(
        calories: 300,
        proteinG: 50,
        carbsG: 60,
        fatG: 20,
      );
      expect(check.agreement, NutritionAgreement.statedBelowMacros);
      expect(check.impliedKcal, 620);
    });

    test('a too-low figure IS reported even with a macro missing — the '
        'macros present are a floor, and a floor can only go up', () {
      final check = crossCheckNutrition(calories: 100, proteinG: 60);
      expect(check.macrosPartial, isTrue);
      expect(check.agreement, NutritionAgreement.statedBelowMacros);
      expect(
        nutritionCrossCheckNote(check),
        'Says 100 kcal; its macros need at least 240',
      );
    });

    test('explicit zero macros beside a calorie figure is a contradiction, '
        'not a missing value', () {
      final check = crossCheckNutrition(
        calories: 500,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
      );
      expect(check.macrosPartial, isFalse);
      expect(check.agreement, NutritionAgreement.statedAboveMacros);
    });
  });

  test('crossCheckItem reads a plan item', () {
    const item = FoodItem(
      name: 'Rice',
      quantity: 200,
      unit: 'g',
      calories: 900,
      proteinG: 5,
      carbsG: 20,
      fatG: 1,
      estimated: true,
    );
    expect(
      crossCheckItem(item).agreement,
      NutritionAgreement.statedAboveMacros,
    );
    expect(
      crossCheckItem(
        const FoodItem(name: 'Water', quantity: 1, unit: 'pcs'),
      ).agreement,
      NutritionAgreement.unchecked,
    );
  });
}
