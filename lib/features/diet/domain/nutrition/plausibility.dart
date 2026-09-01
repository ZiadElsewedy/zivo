/// Does a food's stated calorie figure agree with its own macros?
///
/// The audit's T14: nothing in ZIVO ever checked a nutrition value against
/// anything. Every calorie in an imported plan is a model's guess, and a guess
/// can be internally contradictory — "600 kcal, 12 g protein, 8 g carbs, 3 g
/// fat" is not a plan the user should be shown without a word, because the
/// macros come to 107.
///
/// This is that check, and only that check. It reads a single item against
/// **itself** — no catalog, no lookup, no network — using the Atwater factors
/// every nutrition label is built on. It cannot tell you a figure is *right*;
/// it can tell you a figure disagrees with the numbers printed beside it, and
/// that is enough to stop showing the two as if they agreed.
///
/// **Deliberately generous.** A false flag on a real plan trains the user to
/// ignore the flag, which is worse than the occasional miss — the same
/// precision-over-recall call the Phase 7 validator makes. Alcohol (7 kcal/g)
/// is not an Atwater macro, fibre and sugar alcohols don't burn at 4, and
/// whole-gram rounding costs a few kcal per item, so the tolerance is wide and
/// only a clear contradiction is reported.
///
/// Nothing here is stored. The verdict is derivable from the item at any time,
/// so there is no flag to migrate, no field to keep in sync, and no way for a
/// stored verdict to go stale against the numbers it describes.
library;

import 'dart:math' as math;

import '../food_item.dart';

/// Energy per gram, as every nutrition label computes it.
const double kKcalPerGramProtein = 4;
const double kKcalPerGramCarb = 4;
const double kKcalPerGramFat = 9;

/// Below this, a difference isn't worth a word — whole-gram rounding alone
/// costs several kcal per item.
const double _kMinAbsoluteTolerance = 30;

/// And a proportional floor on top, so a 1,200 kcal meal isn't flagged for
/// being 40 kcal out.
const double _kRelativeTolerance = 0.20;

/// What the cross-check found.
enum NutritionAgreement {
  /// Nothing to compare: no calorie figure, or no macros beside it. **Not a
  /// pass** — most items are here, and treating "unchecked" as "checked and
  /// fine" is how a check becomes decoration.
  unchecked,

  /// The stated figure and the macros are within tolerance of each other.
  agrees,

  /// The stated figure is *lower* than the macros alone require. This is the
  /// stronger finding: it holds even when some macros are missing, because
  /// the macros present are a floor, not a total.
  statedBelowMacros,

  /// The stated figure is higher than the macros account for. Only reported
  /// when all three macros are present — with one missing, the gap is exactly
  /// what the missing macro would explain.
  statedAboveMacros,
}

/// One item's stated calories measured against its own macros.
class NutritionCrossCheck {
  const NutritionCrossCheck({
    required this.agreement,
    this.statedKcal,
    this.impliedKcal,
    this.macrosPartial = false,
  });

  static const NutritionCrossCheck unchecked = NutritionCrossCheck(
    agreement: NutritionAgreement.unchecked,
  );

  final NutritionAgreement agreement;

  /// The figure the item claims, or null when it states none.
  final int? statedKcal;

  /// What the macros present come to, rounded. A **floor** rather than a
  /// total when [macrosPartial].
  final int? impliedKcal;

  /// True when at least one macro is absent, so [impliedKcal] can only be
  /// argued upward.
  final bool macrosPartial;

  /// True when the two numbers contradict each other in either direction.
  bool get disagrees =>
      agreement == NutritionAgreement.statedBelowMacros ||
      agreement == NutritionAgreement.statedAboveMacros;
}

/// Cross-checks a stated calorie figure against the macros stated with it.
///
/// Absent macros are absent, never zero: an item with only protein recorded is
/// checked against protein alone, and the result says so through
/// [NutritionCrossCheck.macrosPartial].
NutritionCrossCheck crossCheckNutrition({
  int? calories,
  double? proteinG,
  double? carbsG,
  double? fatG,
}) {
  if (calories == null) return NutritionCrossCheck.unchecked;
  if (proteinG == null && carbsG == null && fatG == null) {
    return NutritionCrossCheck.unchecked;
  }

  final implied =
      (proteinG ?? 0) * kKcalPerGramProtein +
      (carbsG ?? 0) * kKcalPerGramCarb +
      (fatG ?? 0) * kKcalPerGramFat;
  final partial = proteinG == null || carbsG == null || fatG == null;
  final stated = calories.toDouble();
  final tolerance = math.max(
    _kMinAbsoluteTolerance,
    math.max(stated, implied) * _kRelativeTolerance,
  );

  final NutritionAgreement agreement;
  if (stated < implied - tolerance) {
    // Impossible either way round: the macros on their own already cost more
    // than the item claims to contain.
    agreement = NutritionAgreement.statedBelowMacros;
  } else if (!partial && stated > implied + tolerance) {
    agreement = NutritionAgreement.statedAboveMacros;
  } else {
    agreement = NutritionAgreement.agrees;
  }

  return NutritionCrossCheck(
    agreement: agreement,
    statedKcal: calories,
    impliedKcal: implied.round(),
    macrosPartial: partial,
  );
}

/// [crossCheckNutrition] for a plan's [FoodItem].
NutritionCrossCheck crossCheckItem(FoodItem item) => crossCheckNutrition(
  calories: item.calories,
  proteinG: item.proteinG,
  carbsG: item.carbsG,
  fatG: item.fatG,
);

/// The disagreement in one line, or null when there is nothing to say.
///
/// States both numbers rather than a verdict, for the same reason a coaching
/// finding carries its evidence: "this looks wrong" is an assertion, "says 600,
/// its macros come to 107" is something the user can check for themselves.
String? nutritionCrossCheckNote(NutritionCrossCheck check) {
  if (!check.disagrees) return null;
  final macros = check.macrosPartial
      ? 'its macros need at least ${check.impliedKcal}'
      : 'its macros come to ${check.impliedKcal}';
  return 'Says ${check.statedKcal} kcal; $macros';
}
