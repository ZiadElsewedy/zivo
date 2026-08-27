import 'food_item.dart';

/// A named meal within a [DietDay] — e.g. "Breakfast" — holding an ordered
/// list of [FoodItem]s. `id` is stable within the plan so a day's consumption
/// can be logged per meal.
class Meal {
  const Meal({
    required this.id,
    required this.label,
    required this.order,
    required this.items,
  });

  final String id;
  final String label;
  final int order;
  final List<FoodItem> items;
}

/// Whether [meal] is a SUPPLEMENTS entry rather than a real meal. Imported
/// plans routinely carry vitamins, omega-3, creatine and friends as their own
/// block; the AI import is instructed to label that block exactly
/// "Supplements". They stay tracked (checkable per day) but are never counted
/// as meals anywhere — "2 of 4 meals eaten" must not depend on whether you
/// took your vitamins.
bool isSupplementMeal(Meal meal) =>
    meal.label.trim().toLowerCase().contains('supplement');

/// [meals] minus the supplements block, order preserved.
List<Meal> regularMeals(Iterable<Meal> meals) =>
    meals.where((m) => !isSupplementMeal(m)).toList();

/// Just the supplements block, order preserved (empty when the plan has none).
List<Meal> supplementMeals(Iterable<Meal> meals) =>
    meals.where(isSupplementMeal).toList();
