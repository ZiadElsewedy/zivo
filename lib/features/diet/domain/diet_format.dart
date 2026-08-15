import 'diet_day.dart';
import 'food_item.dart';
import 'meal.dart';

/// A quantity without a trailing ".0": 60 → "60", 22.5 → "22.5".
String _trimQty(double v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

/// "150 g" or "150 g · 210 kcal" when the item has calories.
String foodQtyLabel(FoodItem item) {
  final base = '${_trimQty(item.quantity)} ${item.unit}';
  if (item.calories == null) return base;
  return '$base · ${item.calories} kcal';
}

/// "P 40 · C 45 · F 8" (grams, trimmed) — null when the item carries no macro.
String? macroLabel(FoodItem item) {
  final parts = [
    if (item.proteinG != null) 'P ${_trimQty(item.proteinG!)}',
    if (item.carbsG != null) 'C ${_trimQty(item.carbsG!)}',
    if (item.fatG != null) 'F ${_trimQty(item.fatG!)}',
  ];
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

/// Sum of item calories in [meal]; null if none of its items carry calories.
int? mealCalories(Meal meal) {
  final withCalories = meal.items.where((i) => i.calories != null);
  if (withCalories.isEmpty) return null;
  return withCalories.fold<int>(0, (sum, i) => sum + i.calories!);
}

/// Sum of meal calories in [day]; null if none of its meals carry calories.
int? dayCalories(DietDay day) {
  final mealTotals = day.meals.map(mealCalories).whereType<int>();
  if (mealTotals.isEmpty) return null;
  return mealTotals.fold<int>(0, (sum, c) => sum + c);
}
