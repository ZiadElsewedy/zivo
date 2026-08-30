import 'diet_day.dart';
import 'diet_format.dart';
import 'meal.dart';
import 'nutrition/food_log_entry.dart';
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
    required this.consumedIsFromTickedMeals,
    required this.loggedEntryCount,
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

  /// How many entries the user logged themselves today (as opposed to
  /// materialised by ticking a meal). Zero with a non-empty day means the
  /// numbers rest entirely on the plan.
  final int loggedEntryCount;

  /// Whether every consumed figure came from ticking a planned meal rather
  /// than from something the user logged.
  ///
  /// The difference is the difference between "you ate 1,850 kcal" and "the
  /// plan values what you ticked at 1,850 kcal". Both are useful; only one is
  /// a measurement, and a coach has to know which it is holding.
  final bool consumedIsFromTickedMeals;

  /// Calories left in the day's budget. Negative when the target is passed.
  int get remainingKcal => targets.calories - consumedKcal;

  /// True once consumption has gone past the calorie target.
  bool get overTarget => remainingKcal < 0;

  /// 0..1 of the calorie target consumed (unclamped — see [MacroProgress]).
  double get calorieFraction =>
      targets.calories <= 0 ? 0 : consumedKcal / targets.calories;
}

/// Builds today's [TargetProgress] from the user's targets, the day's food
/// log, and the plan's ticked meals.
///
/// **The log is the source of truth when it has anything in it.** [log] is
/// what the user actually recorded — including the entries materialised by
/// ticking a meal — so it captures a half-eaten meal, a substituted side, or
/// a snack the plan never mentioned. Only when the log is empty (a day
/// recorded before the log existed) does this fall back to summing the
/// planned figures of ticked meals, and it says so through
/// [TargetProgress.consumedIsFromTickedMeals] rather than passing the
/// assumption off as a measurement.
///
/// Pure and deterministic. Supplements are excluded from the MEAL COUNTS
/// exactly as they are from [dayCalories] — a vitamin is not part of the
/// energy budget — while the log is summed as recorded.
TargetProgress buildTargetProgress({
  required NutritionTargets targets,
  required DietDay? day,
  required Set<String> consumed,
  List<FoodLogEntry> log = const [],
}) {
  final meals = day == null ? const <Meal>[] : regularMeals(day.meals);
  final eatenMeals = meals.where((m) => consumed.contains(m.id)).toList();

  final int consumedKcal;
  final bool estimated;
  final double? protein;
  final double? carbs;
  final double? fat;
  final bool fromTickedMeals;
  final int loggedCount;

  if (log.isNotEmpty) {
    final totals = totalsOf(log);
    consumedKcal = totals.kcal;
    estimated = totals.estimated;
    protein = totals.proteinG;
    carbs = totals.carbsG;
    fat = totals.fatG;
    fromTickedMeals = totals.allFromPlannedMeals;
    loggedCount = totals.loggedCount;
  } else {
    final eatenItems = eatenMeals.expand((m) => m.items).toList();
    final eaten = macroTotals(eatenItems);
    consumedKcal = eatenMeals
        .map(mealCalories)
        .whereType<int>()
        .fold<int>(0, (sum, c) => sum + c);
    estimated = anyEstimated(eatenItems);
    protein = eaten.proteinG;
    carbs = eaten.carbsG;
    fat = eaten.fatG;
    fromTickedMeals = true;
    loggedCount = 0;
  }

  MacroProgress macro(String label, double? target, double? consumedG) =>
      MacroProgress(
        label: label,
        target: target,
        // A null macro total over what was consumed means "none of it states
        // this nutrient", which for a running total is 0 — unlike a null
        // target, which means "you didn't set one".
        consumed: consumedG ?? 0,
        estimated: estimated,
      );

  return TargetProgress(
    targets: targets,
    consumedKcal: consumedKcal,
    estimated: estimated,
    protein: macro('Protein', targets.proteinG, protein),
    carbs: macro('Carbs', targets.carbsG, carbs),
    fat: macro('Fat', targets.fatG, fat),
    mealsEaten: eatenMeals.length,
    mealsTotal: meals.length,
    consumedIsFromTickedMeals: fromTickedMeals,
    loggedEntryCount: loggedCount,
  );
}
