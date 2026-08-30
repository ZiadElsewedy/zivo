import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_goal.dart';
import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_plan_status.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/domain/diet_state.dart';
import 'package:zivo/features/diet/domain/diet_state_builder.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/meal.dart';
import 'package:zivo/features/diet/domain/nutrition/food_log_entry.dart';
import 'package:zivo/features/diet/domain/nutrition/food_reference.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/presentation/today_diet.dart';

/// The Dart half of the shared diet-state vectors.
///
/// `test/fixtures/diet_state_vectors.json` is run by BOTH this file and
/// `functions/diet/state.test.js`. The Diet screen renders a state built here;
/// the coach reads one built in JavaScript. Change either and the other's test
/// fails until they agree again (docs/DIET_COACH_AUDIT.md, T13).

DietDay? _dayFrom(Map<String, dynamic>? raw) {
  if (raw == null) return null;
  return DietDay(
    label: raw['label'] as String,
    meals: [
      for (final m in (raw['meals'] as List).cast<Map<String, dynamic>>())
        Meal(
          id: m['id'] as String,
          label: m['label'] as String,
          order: 0,
          items: [
            for (final i in (m['items'] as List).cast<Map<String, dynamic>>())
              FoodItem(
                name: i['name'] as String,
                quantity: (i['quantity'] as num).toDouble(),
                unit: i['unit'] as String,
                calories: (i['calories'] as num?)?.toInt(),
                proteinG: (i['proteinG'] as num?)?.toDouble(),
                carbsG: (i['carbsG'] as num?)?.toDouble(),
                fatG: (i['fatG'] as num?)?.toDouble(),
                estimated: i['estimated'] == true,
              ),
          ],
        ),
    ],
  );
}

NutritionTargets? _targetsFrom(Map<String, dynamic>? raw) {
  if (raw == null) return null;
  return NutritionTargets(
    goal: dietGoalFromName(raw['goal'] as String?)!,
    calories: (raw['calories'] as num).toInt(),
    proteinG: (raw['proteinG'] as num?)?.toDouble(),
    carbsG: (raw['carbsG'] as num?)?.toDouble(),
    fatG: (raw['fatG'] as num?)?.toDouble(),
    source: targetSourceFromName(raw['source'] as String?),
    updatedAt: DateTime(2026, 8, 30),
  );
}

List<FoodLogEntry> _logFrom(List<dynamic> raw) => [
  for (final e in raw.cast<Map<String, dynamic>>())
    FoodLogEntry(
      id: e['id'] as String,
      day: DateTime(2026, 8, 30),
      loggedAt: DateTime(2026, 8, 30, 12),
      foodId: e['foodId'] as String,
      foodName: e['foodName'] as String,
      quantity: (e['quantity'] as num).toDouble(),
      unit: e['unit'] as String,
      grams: (e['grams'] as num).toDouble(),
      kcal: (e['kcal'] as num).toInt(),
      proteinG: (e['proteinG'] as num).toDouble(),
      carbsG: (e['carbsG'] as num).toDouble(),
      fatG: (e['fatG'] as num).toDouble(),
      source: nutritionSourceFromName(e['source'] as String?),
      sourceRef: e['sourceRef'] as String,
      origin: foodLogOriginFromName(e['origin'] as String?),
      estimated: e['estimated'] == true,
      mealId: e['mealId'] as String?,
    ),
];

void main() {
  late Map<String, dynamic> vectors;

  setUpAll(() {
    vectors = json.decode(
      File('test/fixtures/diet_state_vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  test('golden vectors: every state case rebuilds exactly', () {
    for (final spec in (vectors['cases'] as List).cast<Map<String, dynamic>>()) {
      final input = spec['input'] as Map<String, dynamic>;
      final expected = spec['expected'] as Map<String, dynamic>;
      final name = spec['name'] as String;

      final state = buildDietState(
        dayKey: input['dayKey'] as String,
        weekday: (input['weekday'] as num).toInt(),
        targets: _targetsFrom(input['targets'] as Map<String, dynamic>?),
        planName: input['planName'] as String?,
        day: _dayFrom(input['day'] as Map<String, dynamic>?),
        consumedMealIds:
            (input['consumedMealIds'] as List).cast<String>().toSet(),
        log: _logFrom(input['log'] as List),
      );

      expect(state.dayKey, expected['dayKey'], reason: name);
      expect(state.weekday, expected['weekday'], reason: name);
      expect(state.planName, expected['planName'], reason: name);
      expect(state.dayLabel, expected['dayLabel'], reason: name);
      expect(state.plannedKcal, expected['plannedKcal'], reason: name);
      expect(state.mealsEaten, expected['mealsEaten'], reason: name);
      expect(state.mealsTotal, expected['mealsTotal'], reason: name);

      final consumed = expected['consumed'] as Map<String, dynamic>;
      expect(state.consumed.kcal, consumed['kcal'], reason: name);
      expect(state.consumed.proteinG, consumed['proteinG'], reason: name);
      expect(state.consumed.carbsG, consumed['carbsG'], reason: name);
      expect(state.consumed.fatG, consumed['fatG'], reason: name);
      expect(state.consumed.basis.name, consumed['basis'], reason: name);
      expect(state.consumed.estimated, consumed['estimated'], reason: name);
      expect(state.consumed.entryCount, consumed['entryCount'], reason: name);
      expect(state.consumed.loggedCount, consumed['loggedCount'], reason: name);

      final remaining = expected['remaining'] as Map<String, dynamic>?;
      if (remaining == null) {
        expect(state.remaining, isNull, reason: name);
      } else {
        expect(state.remaining!.kcal, remaining['kcal'], reason: name);
        expect(state.remaining!.proteinG, remaining['proteinG'], reason: name);
        expect(state.remaining!.carbsG, remaining['carbsG'], reason: name);
        expect(state.remaining!.fatG, remaining['fatG'], reason: name);
      }

      final quality = expected['quality'] as Map<String, dynamic>;
      expect(state.quality.targetsUnset, quality['targetsUnset'], reason: name);
      expect(state.quality.noPlanForDay, quality['noPlanForDay'], reason: name);
      expect(state.quality.nothingLogged, quality['nothingLogged'],
          reason: name);
      expect(state.quality.consumedIsAssumed, quality['consumedIsAssumed'],
          reason: name);
      expect(state.quality.hasEstimatedValues, quality['hasEstimatedValues'],
          reason: name);
      expect(state.quality.untrackedMacros,
          (quality['untrackedMacros'] as List).cast<String>(), reason: name);

      final meals = (expected['meals'] as List).cast<Map<String, dynamic>>();
      expect(state.meals.length, meals.length, reason: name);
      for (var i = 0; i < meals.length; i++) {
        expect(state.meals[i].id, meals[i]['id'], reason: name);
        expect(state.meals[i].eaten, meals[i]['eaten'], reason: name);
        expect(state.meals[i].kcal, meals[i]['kcal'], reason: name);
        expect(state.meals[i].estimated, meals[i]['estimated'], reason: name);
        expect(state.meals[i].isSupplement, meals[i]['isSupplement'],
            reason: name);
      }
    }
  });

  test('golden vectors: the plan-day resolver agrees for every weekday', () {
    // `dayForDate` here and `resolveDietDay` on the server are separate
    // implementations of one rule. A disagreement means the screen and the
    // coach are reading different days of the same plan.
    final plans = vectors['plans'] as Map<String, dynamic>;
    for (final spec
        in (vectors['resolutions'] as List).cast<Map<String, dynamic>>()) {
      final days = [
        for (final d
            in (plans[spec['plan']] as List).cast<Map<String, dynamic>>())
          DietDay(
            weekday: (d['weekday'] as num?)?.toInt(),
            label: d['label'] as String,
            meals: const [],
          ),
      ];
      final plan = DietPlan(
        id: 'p',
        name: 'p',
        status: DietPlanStatus.active,
        source: DietSource.manual,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        days: days,
      );
      final date = DateTime.parse('${spec['dayKey']}T12:00:00');
      expect(
        dayForDate(plan, date)?.label,
        spec['expectedLabel'],
        reason: '${spec['plan']} on ${spec['dayKey']}',
      );
    }
  });

  group('rules the state enforces in one place', () {
    DietDay planDay() => _dayFrom(
      (vectors['planDay'] as Map<String, dynamic>),
    )!;

    test('an empty log is "nothing logged", never a measured zero', () {
      final state = buildDietState(
        dayKey: '2026-08-30',
        weekday: 7,
        targets: null,
        planName: 'Cut',
        day: planDay(),
        consumedMealIds: const <String>{},
        log: const [],
      );
      expect(state.consumed.basis, ConsumedBasis.nothingLogged);
      expect(state.quality.nothingLogged, isTrue);
      expect(state.quality.consumedIsAssumed, isFalse);
    });

    test('supplements are tracked but never counted', () {
      final state = buildDietState(
        dayKey: '2026-08-30',
        weekday: 7,
        targets: null,
        planName: 'Cut',
        day: planDay(),
        consumedMealIds: const {'m3-supplements'},
        log: const [],
      );
      expect(
        state.meals.any((m) => m.id == 'm3-supplements' && m.isSupplement),
        isTrue,
      );
      expect(state.mealsTotal, 2);
      expect(state.mealsEaten, 0);
      expect(state.consumed.kcal, 0);
      expect(state.plannedKcal, 760);
    });

    test("a plan's own sum is reported apart from the user's target", () {
      final state = buildDietState(
        dayKey: '2026-08-30',
        weekday: 7,
        targets: NutritionTargets(
          goal: DietGoal.fatLoss,
          calories: 2200,
          source: TargetSource.manual,
          updatedAt: DateTime(2026, 8, 30),
        ),
        planName: 'Cut',
        day: planDay(),
        consumedMealIds: const <String>{},
        log: const [],
      );
      expect(state.targets!.calories, 2200);
      expect(state.plannedKcal, 760);
      expect(state.goal, DietGoal.fatLoss);
    });

    test('isComplete is false while anything is unset or assumed', () {
      final assumed = buildDietState(
        dayKey: '2026-08-30',
        weekday: 7,
        targets: NutritionTargets(
          goal: DietGoal.fatLoss,
          calories: 2200,
          source: TargetSource.manual,
          updatedAt: DateTime(2026, 8, 30),
        ),
        planName: 'Cut',
        day: planDay(),
        consumedMealIds: const {'m2-lunch'},
        log: const [],
      );
      expect(assumed.quality.consumedIsAssumed, isTrue);
      expect(assumed.quality.isComplete, isFalse);
    });
  });
}
