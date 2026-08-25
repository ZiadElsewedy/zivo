import 'diet_day.dart';
import 'diet_format.dart';
import 'meal.dart';
export 'meal.dart' show isSupplementMeal, regularMeals, supplementMeals;

/// Eaten/total meal counts and remaining calories for [day], given the set of
/// meal ids marked eaten. Meals without a calorie total don't count toward
/// `kcalLeft`. Supplements are excluded entirely — see [isSupplementMeal].
({int eaten, int total, int kcalLeft}) dietDaySummary(
  DietDay day,
  Set<String> consumed,
) {
  final meals = regularMeals(day.meals);
  final total = meals.length;
  final eaten = meals.where((m) => consumed.contains(m.id)).length;
  final kcalLeft = meals
      .where((m) => !consumed.contains(m.id))
      .map(mealCalories)
      .whereType<int>()
      .fold<int>(0, (sum, c) => sum + c);
  return (eaten: eaten, total: total, kcalLeft: kcalLeft);
}
