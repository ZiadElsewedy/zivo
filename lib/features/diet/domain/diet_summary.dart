import 'diet_day.dart';
import 'diet_format.dart';

/// Eaten/total meal counts and remaining calories for [day], given the set of
/// meal ids marked eaten. Meals without a calorie total don't count toward
/// `kcalLeft`.
({int eaten, int total, int kcalLeft}) dietDaySummary(
  DietDay day,
  Set<String> consumed,
) {
  final total = day.meals.length;
  final eaten = day.meals.where((m) => consumed.contains(m.id)).length;
  final kcalLeft = day.meals
      .where((m) => !consumed.contains(m.id))
      .map(mealCalories)
      .whereType<int>()
      .fold<int>(0, (sum, c) => sum + c);
  return (eaten: eaten, total: total, kcalLeft: kcalLeft);
}
