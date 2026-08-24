/// A single food item within a [Meal] — a quantity of a named food, with
/// optional calories and macros (all nullable: a manual entry may skip them).
class FoodItem {
  const FoodItem({
    required this.name,
    required this.quantity,
    required this.unit, // 'g', 'ml', 'pcs'
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.estimated = false,
  });

  final String name;
  final double quantity;
  final String unit;
  final int? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;

  /// True when calories/macros were AI-estimated at PDF import time rather
  /// than stated in the source document — never true for a manually-added
  /// item (the add-item sheet never sets it). Purely a display hint ("~" on
  /// the calorie figure); the values themselves are used identically either
  /// way.
  final bool estimated;
}
