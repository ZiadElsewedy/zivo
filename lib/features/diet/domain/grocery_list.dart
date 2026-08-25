import 'diet_plan.dart';

/// One aggregated shopping line — a food and its total quantity in a single
/// unit, summed across every day and meal of the plan.
class GroceryItem {
  const GroceryItem({
    required this.name,
    required this.quantity,
    required this.unit,
  });

  /// Display name (first-seen casing); aggregation itself is case-insensitive.
  final String name;

  /// Total across all occurrences in the plan.
  final double quantity;
  final String unit;
}

/// Aggregates a plan's every item into a shopping list: quantities summed per
/// (case-insensitive name, unit) pair — "150g oats" at breakfast and "50g
/// Oats" on another day become one "200 g Oats" line, while the same food in
/// different units stays separate (60 g rice ≠ 1 plate rice).
///
/// Every day counts once, regardless of `weekday` specificity: an every-day
/// template is one pass through its meals, not seven. The result is "what one
/// shop for this plan looks like", sorted alphabetically for scanning in an
/// aisle.
List<GroceryItem> buildGroceryList(DietPlan plan) {
  final order = <String>[];
  final totals = <String, ({double quantity, String unit})>{};
  final displayNames = <String, String>{};

  for (final day in plan.days) {
    for (final meal in day.meals) {
      for (final item in meal.items) {
        final name = item.name.trim();
        if (name.isEmpty) continue;
        final key =
            '${name.toLowerCase()}\u{0000}${item.unit.trim().toLowerCase()}';
        if (totals.containsKey(key)) {
          totals[key] = (
            quantity: totals[key]!.quantity + item.quantity,
            unit: totals[key]!.unit,
          );
        } else {
          order.add(key);
          displayNames[key] = name;
          totals[key] = (quantity: item.quantity, unit: item.unit.trim());
        }
      }
    }
  }

  final items = [
    for (final key in order)
      GroceryItem(
        name: displayNames[key]!,
        quantity: totals[key]!.quantity,
        unit: totals[key]!.unit,
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return items;
}
