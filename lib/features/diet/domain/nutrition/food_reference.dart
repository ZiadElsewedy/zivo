/// Where a nutrition figure came from. Travels with every value the app
/// computes, so any number on screen can be traced back to a record — the
/// property the whole Diet Coach rebuild turns on (see
/// `docs/DIET_COACH_AUDIT.md`, T1/T2).
enum NutritionSource {
  /// A row in the bundled USDA FoodData Central catalog. [FoodReference.sourceRef]
  /// is its real `fdcId`, so the exact record is retrievable.
  usdaFdc,

  /// A food the user defined themselves (their mum's recipe, a local brand).
  /// Trusted because a person entered it deliberately, and labelled as such.
  userCustom,

  /// The figures written on the user's own diet plan. Note this is NOT a
  /// reference value: for an imported plan those numbers were AI-estimated at
  /// import time, which is why a log entry from this source carries the
  /// `estimated` flag onward rather than laundering it into a measurement.
  dietPlan,
}

/// Parses a stored source name, defaulting to [NutritionSource.dietPlan] —
/// the least-verified reading. An unknown value must never be mistaken for a
/// reference figure.
NutritionSource nutritionSourceFromName(String? name) {
  for (final source in NutritionSource.values) {
    if (source.name == name) return source;
  }
  return NutritionSource.dietPlan;
}

/// How a food was prepared, as USDA's own description states it.
///
/// **Not a nicety.** 100 g of raw rice is 365 kcal; 100 g of cooked rice is
/// 130. Resolving "100g rice" without knowing which is a ~3× error, and it is
/// where consumer trackers quietly lose their accuracy. [unknown] is preserved
/// rather than defaulted so the resolver can ask instead of guessing.
enum FoodPreparation { raw, cooked, dry, unknown }

/// Parses the catalog's state string; unknown for anything unrecognized.
FoodPreparation foodPreparationFromName(String? name) => switch (name) {
  'raw' => FoodPreparation.raw,
  'cooked' => FoodPreparation.cooked,
  'dry' => FoodPreparation.dry,
  _ => FoodPreparation.unknown,
};

/// A household measure the source itself states for a food — "1 cup" → 140 g.
/// Only ever a measure USDA recorded for THIS food; ZIVO never converts a
/// volume to a weight by assuming a density.
class FoodPortion {
  const FoodPortion({required this.label, required this.grams});

  /// The measure as the source names it: 'cup', 'large', 'slice', 'serving'.
  final String label;

  /// Grams in exactly one of [label].
  final double grams;
}

/// One food in the nutrition catalog: a name, its per-100g composition, and
/// the record it came from.
///
/// Every field here is read from a source. Nothing on this class is inferred,
/// estimated, or supplied by a model.
class FoodReference {
  const FoodReference({
    required this.id,
    required this.name,
    required this.preparation,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    required this.source,
    required this.sourceRef,
    this.category,
    this.portions = const [],
  });

  /// Stable handle, e.g. `usda:171477`. Safe to persist on a log entry.
  final String id;

  /// The source's own description, verbatim — "Chicken, broilers or fryers,
  /// breast, meat only, cooked, roasted". Deliberately not prettified: the
  /// name is part of the sourced record, and rewriting it would be the app
  /// editorialising data it is claiming to have merely looked up.
  final String name;

  /// USDA's food-group label, when the record carries one.
  final String? category;

  final FoodPreparation preparation;

  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;

  final NutritionSource source;

  /// The identifier within [source] — an `fdcId` for USDA rows. This is what
  /// makes a figure auditable rather than merely asserted.
  final String sourceRef;

  final List<FoodPortion> portions;

  /// The portion matching [label] (case-insensitive), or null.
  FoodPortion? portionNamed(String label) {
    final wanted = label.trim().toLowerCase();
    for (final portion in portions) {
      if (portion.label.toLowerCase() == wanted) return portion;
    }
    return null;
  }
}
