import 'food_reference.dart';

/// A computed nutrition figure, inseparable from where it came from.
///
/// There is no constructor that produces one of these without a
/// [FoodReference] behind it, which is the point: a calorie figure in ZIVO
/// cannot exist without a record it can be traced to.
class ResolvedNutrition {
  const ResolvedNutrition({
    required this.food,
    required this.quantity,
    required this.unit,
    required this.grams,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final FoodReference food;

  /// What the user asked for — "200" / "g", or "1" / "cup".
  final double quantity;
  final String unit;

  /// The mass the figures were computed from, after resolving [unit].
  final double grams;

  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// Where these numbers came from, for display and for the coach.
  NutritionSource get source => food.source;
  String get sourceRef => food.sourceRef;
}

/// Why a quantity could not be turned into a mass.
enum QuantityProblem {
  /// The number was zero, negative or unparseable.
  invalidQuantity,

  /// A volume (ml, cup, tbsp…) with no measure recorded for THIS food.
  ///
  /// ZIVO will not convert volume to weight by assuming a density — "100ml of
  /// olive oil is 100g" is wrong by about 8%, and for flour or rice it's wrong
  /// by a third. When the source doesn't state the measure for this food, the
  /// honest answer is to ask for a weight.
  unknownMeasure,
}

/// A quantity that couldn't be resolved into grams, with the reason and the
/// measures that WOULD work — so the caller can ask a useful question rather
/// than just refusing.
class QuantityUnresolved {
  const QuantityUnresolved({
    required this.problem,
    required this.unit,
    required this.availableMeasures,
  });

  final QuantityProblem problem;
  final String unit;

  /// The portion labels this food does have, e.g. ['cup', 'large', 'slice'].
  final List<String> availableMeasures;
}

/// Mass units the catalog can convert exactly, with no assumption about the
/// food. Volume is deliberately absent — see [QuantityProblem.unknownMeasure].
const Map<String, double> _gramsPerMassUnit = {
  'g': 1,
  'gram': 1,
  'grams': 1,
  'kg': 1000,
  'oz': 28.349523125,
  'ounce': 28.349523125,
  'ounces': 28.349523125,
  'lb': 453.59237,
  'pound': 453.59237,
  'pounds': 453.59237,
};

/// Unit names that mean "one of whatever the source calls a single item".
/// Mapped onto the food's own portion list, never to a fixed gram value.
const List<String> _pieceUnits = ['pcs', 'pc', 'piece', 'pieces', 'each', 'item'];

/// The portion labels a "piece" should try, in order — a source rarely calls
/// it "piece"; it calls it "large", "medium", "fillet", "slice".
const List<String> _pieceCandidates = [
  'piece', 'each', 'medium', 'large', 'small', 'fillet', 'slice', 'serving',
];

/// Converts [quantity] of [unit] into grams of [food], or explains why it
/// can't. Pure and total: every input produces either a mass or a stated
/// reason, never a silent fallback.
Object /* double | QuantityUnresolved */ gramsFor({
  required FoodReference food,
  required double quantity,
  required String unit,
}) {
  final measures = food.portions.map((p) => p.label).toList();
  if (!quantity.isFinite || quantity <= 0) {
    return QuantityUnresolved(
      problem: QuantityProblem.invalidQuantity,
      unit: unit,
      availableMeasures: measures,
    );
  }

  final normalized = unit.trim().toLowerCase();

  final massFactor = _gramsPerMassUnit[normalized];
  if (massFactor != null) return quantity * massFactor;

  // A measure the source recorded for this exact food.
  final named = food.portionNamed(normalized);
  if (named != null) return quantity * named.grams;

  if (_pieceUnits.contains(normalized)) {
    for (final candidate in _pieceCandidates) {
      final portion = food.portionNamed(candidate);
      if (portion != null) return quantity * portion.grams;
    }
  }

  return QuantityUnresolved(
    problem: QuantityProblem.unknownMeasure,
    unit: unit,
    availableMeasures: measures,
  );
}

/// The nutrition of [quantity] [unit] of [food], or a [QuantityUnresolved]
/// explaining why it can't be computed.
///
/// Deterministic and pure — the same three inputs always give the same
/// numbers, on device and on the server. This is the ONLY place in the app
/// that turns a food and an amount into calories; nothing else is allowed to
/// do this arithmetic, least of all a language model.
Object /* ResolvedNutrition | QuantityUnresolved */ nutritionFor({
  required FoodReference food,
  required double quantity,
  required String unit,
}) {
  final grams = gramsFor(food: food, quantity: quantity, unit: unit);
  if (grams is QuantityUnresolved) return grams;

  final mass = grams as double;
  final factor = mass / 100;
  return ResolvedNutrition(
    food: food,
    quantity: quantity,
    unit: unit,
    grams: _round1(mass),
    // Calories are whole numbers everywhere in the app; macros keep one
    // decimal. Rounding is fixed here so the stored value and the displayed
    // value can never disagree.
    kcal: (food.kcalPer100g * factor).round(),
    proteinG: _round1(food.proteinPer100g * factor),
    carbsG: _round1(food.carbsPer100g * factor),
    fatG: _round1(food.fatPer100g * factor),
  );
}

double _round1(double value) => (value * 10).round() / 10;
