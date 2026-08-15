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
