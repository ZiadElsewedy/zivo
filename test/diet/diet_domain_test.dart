import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_format.dart';
import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_plan_status.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/domain/diet_summary.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/meal.dart';
import 'package:zivo/features/diet/presentation/today_diet.dart';

FoodItem _item({
  String name = 'Rice',
  double quantity = 150,
  String unit = 'g',
  int? calories,
  double? proteinG,
  double? carbsG,
  double? fatG,
  bool estimated = false,
}) => FoodItem(
  name: name,
  quantity: quantity,
  unit: unit,
  calories: calories,
  proteinG: proteinG,
  carbsG: carbsG,
  fatG: fatG,
  estimated: estimated,
);

void main() {
  group('foodQtyLabel', () {
    test('trims a whole quantity and omits calories when absent', () {
      expect(foodQtyLabel(_item(quantity: 150, unit: 'g')), '150 g');
    });

    test('keeps a fractional quantity and appends calories when present', () {
      expect(foodQtyLabel(_item(quantity: 22.5, unit: 'g', calories: 210)), '22.5 g · 210 kcal');
    });
  });

  group('macroLabel', () {
    test('null when the item carries no macro', () {
      expect(macroLabel(_item()), isNull);
    });

    test('joins present macros, trimming whole-number grams', () {
      expect(
        macroLabel(_item(proteinG: 40, carbsG: 45.5, fatG: 8)),
        'P 40 · C 45.5 · F 8',
      );
    });

    test('omits absent macros from the join', () {
      expect(macroLabel(_item(proteinG: 62)), 'P 62');
    });
  });

  group('mealCalories', () {
    test('sums item calories, ignoring items without one', () {
      final meal = Meal(
        id: 'm1',
        label: 'Lunch',
        order: 0,
        items: [
          _item(name: 'Rice', calories: 210),
          _item(name: 'Chicken breast', calories: 330),
          _item(name: 'Sauce'),
        ],
      );
      expect(mealCalories(meal), 540);
    });

    test('null when no item has calories', () {
      final meal = Meal(id: 'm1', label: 'Lunch', order: 0, items: [_item()]);
      expect(mealCalories(meal), isNull);
    });
  });

  group('dayCalories', () {
    test('sums meal calories, ignoring meals without any', () {
      final day = DietDay(
        weekday: 1,
        label: 'Monday',
        meals: [
          Meal(id: 'm1', label: 'Breakfast', order: 0, items: [_item(calories: 220)]),
          Meal(id: 'm2', label: 'Lunch', order: 1, items: [_item()]),
          Meal(id: 'm3', label: 'Dinner', order: 2, items: [_item(calories: 400)]),
        ],
      );
      expect(dayCalories(day), 620);
    });

    test('null when no meal has calories', () {
      final day = DietDay(
        weekday: 1,
        label: 'Monday',
        meals: [
          Meal(id: 'm1', label: 'Breakfast', order: 0, items: [_item()]),
        ],
      );
      expect(dayCalories(day), isNull);
    });
  });

  group('dietDaySummary', () {
    DietDay dayWith(List<Meal> meals) =>
        DietDay(weekday: 1, label: 'Monday', meals: meals);

    test('nothing eaten: full kcal left, zero eaten', () {
      final day = dayWith([
        Meal(id: 'm1', label: 'Breakfast', order: 0, items: [_item(calories: 220)]),
        Meal(id: 'm2', label: 'Lunch', order: 1, items: [_item(calories: 330)]),
      ]);
      final summary = dietDaySummary(day, const <String>{});
      expect(summary.eaten, 0);
      expect(summary.total, 2);
      expect(summary.kcalLeft, 550);
    });

    test('some meals eaten: kcal left excludes eaten meals', () {
      final day = dayWith([
        Meal(id: 'm1', label: 'Breakfast', order: 0, items: [_item(calories: 220)]),
        Meal(id: 'm2', label: 'Lunch', order: 1, items: [_item(calories: 330)]),
        Meal(id: 'm3', label: 'Dinner', order: 2, items: [_item(calories: 400)]),
      ]);
      final summary = dietDaySummary(day, {'m1', 'm3'});
      expect(summary.eaten, 2);
      expect(summary.total, 3);
      expect(summary.kcalLeft, 330);
    });

    test('all meals eaten: zero kcal left', () {
      final day = dayWith([
        Meal(id: 'm1', label: 'Breakfast', order: 0, items: [_item(calories: 220)]),
      ]);
      final summary = dietDaySummary(day, {'m1'});
      expect(summary.eaten, 1);
      expect(summary.total, 1);
      expect(summary.kcalLeft, 0);
    });

    test('meals without calories contribute nothing to kcal left', () {
      final day = dayWith([
        Meal(id: 'm1', label: 'Breakfast', order: 0, items: [_item()]),
      ]);
      final summary = dietDaySummary(day, const <String>{});
      expect(summary.total, 1);
      expect(summary.kcalLeft, 0);
    });
  });

  group('DietPlanStatus / DietSource fromName', () {
    test('round-trips known names', () {
      expect(dietPlanStatusFromName('draft'), DietPlanStatus.draft);
      expect(dietPlanStatusFromName('archived'), DietPlanStatus.archived);
      expect(dietSourceFromName('pdf'), DietSource.pdf);
    });

    test('falls back safely for unknown/null values', () {
      expect(dietPlanStatusFromName('mystery'), DietPlanStatus.active);
      expect(dietPlanStatusFromName(null), DietPlanStatus.active);
      expect(dietSourceFromName('mystery'), DietSource.manual);
      expect(dietSourceFromName(null), DietSource.manual);
    });
  });

  group('DietPlan.copyWith', () {
    test('overrides only the given fields', () {
      final plan = DietPlan(
        id: 'p1',
        name: 'Cut — 2200 kcal',
        status: DietPlanStatus.draft,
        source: DietSource.manual,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        days: const [],
      );

      final activated = plan.copyWith(status: DietPlanStatus.active, updatedAt: DateTime(2026, 1, 2));

      expect(activated.id, plan.id);
      expect(activated.name, plan.name);
      expect(activated.status, DietPlanStatus.active);
      expect(activated.source, plan.source);
      expect(activated.createdAt, plan.createdAt);
      expect(activated.updatedAt, DateTime(2026, 1, 2));
      expect(activated.days, plan.days);
    });
  });

  group('dayForDate', () {
    final monday = DateTime(2026, 1, 5); // a Monday
    final tuesday = DateTime(2026, 1, 6);

    DietPlan planWith(List<DietDay> days) => DietPlan(
      id: 'p1',
      name: 'Plan',
      status: DietPlanStatus.active,
      source: DietSource.manual,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      days: days,
    );

    test('null when there is no plan', () {
      expect(dayForDate(null, monday), isNull);
    });

    test('prefers the day whose weekday matches', () {
      final mondayDay = const DietDay(weekday: 1, label: 'Monday', meals: []);
      final everyDay = const DietDay(weekday: null, label: 'Every day', meals: []);
      final plan = planWith([everyDay, mondayDay]);
      expect(dayForDate(plan, monday), mondayDay);
    });

    test('falls back to the every-day template when no weekday matches', () {
      final tuesdayDay = const DietDay(weekday: 2, label: 'Tuesday', meals: []);
      final everyDay = const DietDay(weekday: null, label: 'Every day', meals: []);
      final plan = planWith([tuesdayDay, everyDay]);
      expect(dayForDate(plan, monday), everyDay);
    });

    test('falls back to the single day when the plan has exactly one', () {
      final onlyDay = const DietDay(weekday: 2, label: 'Tuesday', meals: []);
      final plan = planWith([onlyDay]);
      expect(dayForDate(plan, monday), onlyDay);
    });

    test('null when multiple days exist and none resolve', () {
      final tuesdayDay = const DietDay(weekday: 2, label: 'Tuesday', meals: []);
      final wednesdayDay = const DietDay(weekday: 3, label: 'Wednesday', meals: []);
      final plan = planWith([tuesdayDay, wednesdayDay]);
      expect(dayForDate(plan, monday), isNull);
    });

    test('matches the given date, not "today"', () {
      final tuesdayDay = const DietDay(weekday: 2, label: 'Tuesday', meals: []);
      final plan = planWith([tuesdayDay]);
      expect(dayForDate(plan, tuesday), tuesdayDay);
    });
  });

  // Provenance is not decoration. An imported plan's calorie figures were
  // generated by the AI at import time, not measured — a total built from even
  // one of them is an estimate, and every screen that prints it has to say so.
  group('estimation provenance', () {
    Meal mealOf(List<FoodItem> items, {String id = 'm1', String label = 'Meal'}) =>
        Meal(id: id, label: label, order: 0, items: items);

    test('anyEstimated is true when a single item is estimated', () {
      expect(anyEstimated([_item(calories: 100)]), isFalse);
      expect(
        anyEstimated([_item(calories: 100), _item(calories: 50, estimated: true)]),
        isTrue,
      );
      expect(anyEstimated(const <FoodItem>[]), isFalse);
    });

    test('one estimated item makes the whole meal an estimate', () {
      expect(mealEstimated(mealOf([_item(calories: 100)])), isFalse);
      expect(
        mealEstimated(mealOf([
          _item(calories: 100),
          _item(calories: 50, estimated: true),
        ])),
        isTrue,
      );
    });

    test('dayEstimated ignores supplements, exactly as dayCalories does', () {
      // The two must agree about which meals they are talking about, or the
      // "~" would appear on a number the supplement didn't contribute to.
      final day = DietDay(
        label: 'Every day',
        meals: [
          mealOf([_item(calories: 400)], id: 'm1', label: 'Lunch'),
          mealOf(
            [_item(name: 'Omega-3', calories: 10, estimated: true)],
            id: 'm2',
            label: 'Supplements',
          ),
        ],
      );
      expect(dayCalories(day), 400);
      expect(dayEstimated(day), isFalse);
    });

    test('approx marks estimates and only estimates', () {
      expect(approx(true), '~');
      expect(approx(false), '');
    });

    test('kcalLeftEstimated tracks the meals still to eat, not the eaten ones',
        () {
      final day = DietDay(
        label: 'Every day',
        meals: [
          mealOf([_item(calories: 300, estimated: true)], id: 'm1'),
          mealOf([_item(calories: 400)], id: 'm2'),
        ],
      );

      // Nothing eaten: the remaining total includes the estimated meal.
      final fresh = dietDaySummary(day, const <String>{});
      expect(fresh.kcalLeft, 700);
      expect(fresh.kcalLeftEstimated, isTrue);

      // The estimated meal is eaten; what's LEFT is now exact.
      final after = dietDaySummary(day, {'m1'});
      expect(after.kcalLeft, 400);
      expect(after.kcalLeftEstimated, isFalse);
    });
  });
}
