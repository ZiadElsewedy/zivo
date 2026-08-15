/// A single food item within a [Meal] — a quantity of a named food, with
/// optional calories and macros (all nullable: a manual entry may skip them,
/// and a future PDF extractor may not recover every value either).
class FoodItem {
  const FoodItem({
    required this.name,
    required this.quantity,
    required this.unit, // 'g', 'ml', 'pcs'
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
  });

  final String name;
  final double quantity;
  final String unit;
  final int? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
}
