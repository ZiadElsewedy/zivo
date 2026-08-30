import 'food_reference.dart';

/// Why a food is in the log — the difference between something the user
/// measured and something the app assumed on their behalf.
enum FoodLogOrigin {
  /// The user logged this food themselves: they named it, gave a quantity,
  /// and the catalog resolved it. The most trustworthy entry there is.
  logged,

  /// Materialised from a planned meal the user ticked off. The quantities are
  /// the PLAN's, not a measurement — ticking "Lunch" says "I ate what the plan
  /// says", which is usually close and occasionally not.
  ///
  /// Kept distinct from [logged] because "you ate 1,850 kcal" and "the plan
  /// values what you ticked at 1,850 kcal" are different claims, and the coach
  /// has to be able to tell them apart.
  plannedMeal,
}

/// One thing eaten, at a moment, with the nutrition it was worth and the
/// record that nutrition came from.
///
/// This is the ledger the whole feature was missing. Before it, consumption
/// was a per-meal checkbox: ticking a meal credited its *planned* macros
/// whether the user ate half of it, swapped the rice, or ate out — so
/// "consumed" was an assumption wearing a number's clothes (see
/// `docs/DIET_COACH_AUDIT.md`, T6).
///
/// Every entry carries [foodId] and [sourceRef] so any figure it contributes
/// can be traced back to the catalog row it came from, and stores the computed
/// nutrition alongside them: the catalog can be rebuilt, and a past day must
/// not silently change its totals when it is.
class FoodLogEntry {
  const FoodLogEntry({
    required this.id,
    required this.day,
    required this.loggedAt,
    required this.foodId,
    required this.foodName,
    required this.quantity,
    required this.unit,
    required this.grams,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.source,
    required this.sourceRef,
    required this.origin,
    this.estimated = false,
    this.mealId,
  });

  final String id;

  /// The user's local calendar day this belongs to.
  final DateTime day;
  final DateTime loggedAt;

  /// The catalog handle — `usda:171477`, or `custom:<id>` for a food the user
  /// defined. Null is not allowed: an entry with no food behind it is exactly
  /// the untraceable number this design exists to prevent.
  final String foodId;

  /// The food's name as it was at log time. Denormalised deliberately: a
  /// rebuilt catalog can drop or rename a row, and a past entry must still be
  /// able to say what it was.
  final String foodName;

  final double quantity;
  final String unit;

  /// The mass the figures below were computed from.
  final double grams;

  /// Computed by `nutritionFor` at log time and stored, never recomputed on
  /// read — see the class doc.
  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  final NutritionSource source;
  final String sourceRef;

  final FoodLogOrigin origin;

  /// True when these figures rest on an AI estimate — a plan item whose
  /// calories were filled in at PDF import rather than stated by the document.
  /// Carried onward rather than laundered away: an assumption that passes
  /// through a ledger is still an assumption.
  final bool estimated;

  /// The planned meal this entry came from, when [origin] is
  /// [FoodLogOrigin.plannedMeal] — so un-ticking that meal can remove exactly
  /// the entries it created and nothing else.
  final String? mealId;
}

/// Day totals over a set of log entries, with the honesty flags a caller needs
/// to describe them truthfully.
class FoodLogTotals {
  const FoodLogTotals({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.entryCount,
    required this.loggedCount,
    required this.plannedCount,
    required this.estimated,
  });

  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  final int entryCount;

  /// How many entries the user actually logged, versus materialised from a
  /// ticked meal. A day that is all [FoodLogOrigin.plannedMeal] is a day of
  /// assumptions, and should be described as one.
  final int loggedCount;
  final int plannedCount;

  /// True when any contributing entry rests on an AI-estimated figure, making
  /// the whole total an estimate.
  final bool estimated;

  /// True when every contributing entry came from a ticked meal rather than
  /// something the user logged. Empty days are not "assumed" — there is
  /// nothing to assume about.
  bool get allFromPlannedMeals => entryCount > 0 && loggedCount == 0;

  static const FoodLogTotals empty = FoodLogTotals(
    kcal: 0,
    proteinG: 0,
    carbsG: 0,
    fatG: 0,
    entryCount: 0,
    loggedCount: 0,
    plannedCount: 0,
    estimated: false,
  );
}

/// Sums [entries] into day totals. Pure and deterministic.
FoodLogTotals totalsOf(Iterable<FoodLogEntry> entries) {
  var kcal = 0;
  var protein = 0.0;
  var carbs = 0.0;
  var fat = 0.0;
  var count = 0;
  var logged = 0;
  var planned = 0;
  var estimated = false;
  for (final entry in entries) {
    if (entry.estimated) estimated = true;
    kcal += entry.kcal;
    protein += entry.proteinG;
    carbs += entry.carbsG;
    fat += entry.fatG;
    count++;
    if (entry.origin == FoodLogOrigin.logged) {
      logged++;
    } else {
      planned++;
    }
  }
  double round1(double v) => (v * 10).round() / 10;
  return FoodLogTotals(
    kcal: kcal,
    proteinG: round1(protein),
    carbsG: round1(carbs),
    fatG: round1(fat),
    entryCount: count,
    loggedCount: logged,
    plannedCount: planned,
    estimated: estimated,
  );
}

/// Parses a stored origin name, defaulting to [FoodLogOrigin.plannedMeal] —
/// the more cautious reading. Mistaking an assumption for a measurement is the
/// worse error of the two.
FoodLogOrigin foodLogOriginFromName(String? name) =>
    name == 'logged' ? FoodLogOrigin.logged : FoodLogOrigin.plannedMeal;
