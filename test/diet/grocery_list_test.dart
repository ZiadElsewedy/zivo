import 'package:flutter_test/flutter_test.dart';

import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_plan_status.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/grocery_list.dart';
import 'package:zivo/features/diet/domain/meal.dart';

DietPlan _plan(List<DietDay> days) => DietPlan(
      id: 'p1',
      name: 'Cut',
      status: DietPlanStatus.active,
      source: DietSource.manual,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
      days: days,
    );

Meal _meal(String id, List<FoodItem> items) =>
    Meal(id: id, label: id, order: 0, items: items);

void main() {
  test('sums the same food across meals and days, case-insensitively', () {
    final plan = _plan([
      DietDay(label: 'Every day', meals: [
        _meal('b1', [
          const FoodItem(name: 'Oats', quantity: 60, unit: 'g'),
        ]),
        _meal('l1', [
          const FoodItem(name: 'oats', quantity: 40, unit: 'g'),
          const FoodItem(name: 'Chicken', quantity: 150, unit: 'g'),
        ]),
      ]),
      DietDay(weekday: 3, label: 'Wednesday', meals: [
        _meal('b2', [
          const FoodItem(name: 'OATS', quantity: 50, unit: 'g'),
        ]),
      ]),
    ]);

    final list = buildGroceryList(plan);

    expect(list, hasLength(2));
    // First-seen casing wins; quantities collapse into one line.
    expect(list[0].name, 'Chicken');
    expect(list[0].quantity, 150);
    expect(list[1].name, 'Oats');
    expect(list[1].quantity, 150);
    expect(list[1].unit, 'g');
  });

  test('keeps the same food in different units separate', () {
    final plan = _plan([
      DietDay(label: 'Every day', meals: [
        _meal('m1', [
          const FoodItem(name: 'Rice', quantity: 80, unit: 'g'),
          const FoodItem(name: 'Rice', quantity: 1, unit: 'pcs'),
        ]),
      ]),
    ]);

    final list = buildGroceryList(plan);

    // Same name sorts equal, so both unit lines survive as separate entries.
    expect(
      list.map((i) => '${i.quantity} ${i.unit}'),
      unorderedEquals(['1.0 pcs', '80.0 g']),
    );
  });

  test('sorts alphabetically case-insensitively and skips blank names', () {
    final plan = _plan([
      DietDay(label: 'Every day', meals: [
        _meal('m1', [
          const FoodItem(name: 'banana', quantity: 2, unit: 'pcs'),
          const FoodItem(name: '   ', quantity: 5, unit: 'g'),
          const FoodItem(name: 'Apple', quantity: 3, unit: 'pcs'),
        ]),
      ]),
    ]);

    final list = buildGroceryList(plan);

    expect(list.map((i) => i.name).toList(), ['Apple', 'banana']);
  });

  test('an empty plan yields an empty list', () {
    expect(buildGroceryList(_plan([])), isEmpty);
  });
}
