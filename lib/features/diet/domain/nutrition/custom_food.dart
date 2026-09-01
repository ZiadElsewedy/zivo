import 'food_reference.dart';

/// A food the user defined themselves.
///
/// The bundled catalog is USDA, so it describes US foods well and everything
/// else poorly — koshari, ful, a local brand of bread. Rather than let the app
/// guess (or let a model fill the gap, which is the whole failure this design
/// exists to end), the honest answer to "not found" is to let the user state
/// the values once and reuse them forever.
///
/// The numbers are theirs, and are labelled [NutritionSource.userCustom]
/// everywhere they surface — trusted because a person entered them
/// deliberately, and never presented as a verified reference value.
class CustomFood {
  const CustomFood({
    required this.id,
    required this.name,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    required this.createdAt,
    this.preparation = FoodPreparation.unknown,
    this.portions = const [],
  });

  /// Stable id; surfaces as `custom:<id>` so a log entry's `foodId` always
  /// says which catalog it came from.
  final String id;
  final String name;

  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;

  final FoodPreparation preparation;

  /// Household measures the user defined ("1 plate" → 350 g).
  final List<FoodPortion> portions;

  final DateTime createdAt;

  /// The catalog handle for this food.
  String get referenceId => 'custom:$id';

  /// As the resolver returns it — the same shape a USDA row has, so every
  /// caller downstream is indifferent to which catalog a food came from and
  /// only the provenance label differs.
  FoodReference toReference() => FoodReference(
    id: referenceId,
    name: name,
    preparation: preparation,
    kcalPer100g: kcalPer100g,
    proteinPer100g: proteinPer100g,
    carbsPer100g: carbsPer100g,
    fatPer100g: fatPer100g,
    source: NutritionSource.userCustom,
    sourceRef: id,
    portions: portions,
  );
}
