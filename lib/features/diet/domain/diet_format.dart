import 'diet_day.dart';
import 'food_item.dart';
import 'meal.dart';

/// A quantity without a trailing ".0": 60 → "60", 22.5 → "22.5".
String _trimQty(double v) =>
    v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

/// "150 g" or "150 g · 210 kcal" when the item has calories — the calorie
/// figure gets a "~" prefix when [FoodItem.estimated] (AI-filled at import
/// time, not stated in the source).
String foodQtyLabel(FoodItem item) {
  final base = '${_trimQty(item.quantity)} ${item.unit}';
  if (item.calories == null) return base;
  final tilde = item.estimated ? '~' : '';
  return '$base · $tilde${item.calories} kcal';
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
/// Supplements are excluded — the day's energy target is about FOOD; the
/// vitamins block isn't part of "kcal left" (see [isSupplementMeal]).
int? dayCalories(DietDay day) {
  final mealTotals = regularMeals(day.meals).map(mealCalories).whereType<int>();
  if (mealTotals.isEmpty) return null;
  return mealTotals.fold<int>(0, (sum, c) => sum + c);
}

/// Summed protein/carbs/fat (grams) across [items]; each component is null
/// when none of the items carry it — same "absent, not zero" semantics as
/// [mealCalories], so a partially-filled plan doesn't read as "0g protein".
({double? proteinG, double? carbsG, double? fatG}) macroTotals(
  Iterable<FoodItem> items,
) {
  double? sum(double? Function(FoodItem) pick) {
    final values = items.map(pick).whereType<double>();
    if (values.isEmpty) return null;
    return values.fold<double>(0, (s, v) => s + v);
  }

  return (
    proteinG: sum((i) => i.proteinG),
    carbsG: sum((i) => i.carbsG),
    fatG: sum((i) => i.fatG),
  );
}
