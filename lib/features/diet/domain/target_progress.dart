import 'diet_day.dart';
import 'diet_format.dart';
import 'meal.dart';
import 'nutrition_targets.dart';

/// One macro's target-versus-consumed reading.
class MacroProgress {
  const MacroProgress({
    required this.label,
    required this.target,
    required this.consumed,
    required this.estimated,
  });

  final String label;

  /// The target in grams, or null when the user didn't set one for this
  /// macro — "absent" never reads as 0.
  final double? target;

  /// Grams consumed so far today.
  final double consumed;

  /// Whether [consumed] rests on any AI-estimated plan figure.
  final bool estimated;

  /// Grams still to eat, or null when there's no target to measure against.
  /// Negative when the target is already passed — the UI shows "over", it
  /// doesn't clamp the number away.
  double? get remaining => target == null ? null : target! - consumed;

  /// 0..1 for a progress bar; null with no target. Not clamped at the top:
  /// callers clamp for drawing, but the value itself stays honest.
  double? get fraction =>
      target == null || target! <= 0 ? null : consumed / target!;
}

/// Today measured against what the user is actually trying to do: the seed of
/// the structured diet state the coach will eventually read wholesale.
///
/// **What "consumed" means here.** ZIVO has no food log yet — ticking a meal
/// credits that meal's *planned* figures. So this is "the plan values what you
/// ticked at N kcal", not "you ate N kcal", and [consumedIsFromTickedMeals] is
/// true to say so. Every surface that shows these numbers has to be able to
/// explain that, and the coach is told it explicitly.
class TargetProgress {
  const TargetProgress({
    required this.targets,
    required this.consumedKcal,
    required this.estimated,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.mealsEaten,
    required this.mealsTotal,
  });

  final NutritionTargets targets;

  /// Calories credited so far — the sum of the ticked meals' planned figures.
  final int consumedKcal;

  /// True when any ticked meal carried AI-estimated figures, making every
  /// number derived from it an estimate too.
  final bool estimated;

  final MacroProgress protein;
  final MacroProgress carbs;
  final MacroProgress fat;

  final int mealsEaten;
  final int mealsTotal;

  /// Always true for now — kept as an explicit field rather than a comment so
  /// that when a real food log lands (and this can be false) every caller is
  /// forced to consider both cases instead of silently inheriting the old
  /// meaning.
  bool get consumedIsFromTickedMeals => true;

  /// Calories left in the day's budget. Negative when the target is passed.
  int get remainingKcal => targets.calories - consumedKcal;

  /// True once consumption has gone past the calorie target.
  bool get overTarget => remainingKcal < 0;

  /// 0..1 of the calorie target consumed (unclamped — see [MacroProgress]).
  double get calorieFraction =>
      targets.calories <= 0 ? 0 : consumedKcal / targets.calories;
}

/// Builds today's [TargetProgress] from the user's targets, the day's planned
/// meals, and which of them are ticked.
///
/// Pure and deterministic — the same three inputs always give the same
/// numbers, on device and (mirrored) on the server. Supplements are excluded
/// throughout, exactly as they are from [dayCalories]: a vitamin is not part
/// of the energy budget.
TargetProgress buildTargetProgress({
  required NutritionTargets targets,
  required DietDay? day,
  required Set<String> consumed,
}) {
  final meals = day == null ? const <Meal>[] : regularMeals(day.meals);
  final eatenMeals = meals.where((m) => consumed.contains(m.id)).toList();
  final eatenItems = eatenMeals.expand((m) => m.items).toList();

  final consumedKcal = eatenMeals
      .map(mealCalories)
      .whereType<int>()
      .fold<int>(0, (sum, c) => sum + c);
  final eaten = macroTotals(eatenItems);
  final estimated = anyEstimated(eatenItems);

  MacroProgress macro(String label, double? target, double? consumedG) =>
      MacroProgress(
        label: label,
        target: target,
        // A null macro total over an EATEN set means "none of what you ticked
        // states this nutrient", which for a running total is 0 — unlike a
        // null target, which means "you didn't set one".
        consumed: consumedG ?? 0,
        estimated: estimated,
      );

  return TargetProgress(
    targets: targets,
    consumedKcal: consumedKcal,
    estimated: estimated,
    protein: macro('Protein', targets.proteinG, eaten.proteinG),
    carbs: macro('Carbs', targets.carbsG, eaten.carbsG),
    fat: macro('Fat', targets.fatG, eaten.fatG),
    mealsEaten: eatenMeals.length,
    mealsTotal: meals.length,
  );
}
