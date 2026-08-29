import 'diet_day.dart';
import 'diet_format.dart';
import 'meal.dart';
export 'meal.dart' show isSupplementMeal, regularMeals, supplementMeals;

/// Eaten/total meal counts and remaining calories for [day], given the set of
/// meal ids marked eaten. Meals without a calorie total don't count toward
/// `kcalLeft`. Supplements are excluded entirely — see [isSupplementMeal].
///
/// `kcalLeftEstimated` reports whether that remaining figure rests on any
/// AI-estimated item ([mealEstimated]) — it travels with the number so a
/// caller can't print the total while dropping the fact that it's a guess.
({int eaten, int total, int kcalLeft, bool kcalLeftEstimated}) dietDaySummary(
  DietDay day,
  Set<String> consumed,
) {
  final meals = regularMeals(day.meals);
  final total = meals.length;
  final eaten = meals.where((m) => consumed.contains(m.id)).length;
  final remaining = meals.where((m) => !consumed.contains(m.id)).toList();
  final kcalLeft = remaining
      .map(mealCalories)
      .whereType<int>()
      .fold<int>(0, (sum, c) => sum + c);
  return (
    eaten: eaten,
    total: total,
    kcalLeft: kcalLeft,
    kcalLeftEstimated: remaining.any(mealEstimated),
  );
}
