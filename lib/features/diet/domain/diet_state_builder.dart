import 'diet_day.dart';
import 'diet_format.dart';
import 'diet_state.dart';
import 'meal.dart';
import 'nutrition/food_log_entry.dart';
import 'nutrition_targets.dart';

/// Builds the one [DietState] the Diet screen renders and the coach reads.
///
/// **Pure and total.** No clock, no repository, no network: every input is
/// passed in, so the same inputs always produce the same state — on this
/// device, on another, and (mirrored in `functions/diet/state.js`) on the
/// server. The mirror is what `test/fixtures/diet_state_vectors.json` pins
/// down: two implementations agreeing by comment discipline is not a
/// guarantee, and a coach quoting different numbers from the screen is the
/// exact failure this whole rebuild exists to end (`docs/DIET_COACH_AUDIT.md`,
/// T13).
///
/// Ordering rules it enforces, in one place instead of five call sites:
/// - supplements never count toward meal counts or the energy budget;
/// - the food log is the source of consumption when it has anything, and the
///   planned figures of ticked meals are a labelled fallback when it doesn't;
/// - a missing target is null, never zero;
/// - an empty log is "nothing recorded", never a measured zero.
DietState buildDietState({
  required String dayKey,
  required int weekday,
  required NutritionTargets? targets,
  required String? planName,
  required DietDay? day,
  required Set<String> consumedMealIds,
  required List<FoodLogEntry> log,
  DietHistorySummary history = DietHistorySummary.empty,
}) {
  final allMeals = day?.meals ?? const <Meal>[];
  final meals = [
    for (final meal in allMeals)
      MealState(
        id: meal.id,
        label: meal.label,
        eaten: consumedMealIds.contains(meal.id),
        kcal: mealCalories(meal),
        estimated: mealEstimated(meal),
        isSupplement: isSupplementMeal(meal),
      ),
  ]..sort((a, b) => a.id.compareTo(b.id));

  final consumed = _consumedFrom(log, allMeals, consumedMealIds);
  final remaining = targets == null
      ? null
      : RemainingTotals(
          kcal: targets.calories - consumed.kcal,
          proteinG: _left(targets.proteinG, consumed.proteinG),
          carbsG: _left(targets.carbsG, consumed.carbsG),
          fatG: _left(targets.fatG, consumed.fatG),
        );

  return DietState(
    dayKey: dayKey,
    weekday: weekday,
    targets: targets,
    planName: planName,
    dayLabel: day?.label,
    meals: meals,
    consumed: consumed,
    remaining: remaining,
    log: log,
    history: history,
    quality: DietQuality(
      targetsUnset: targets == null,
      noPlanForDay: day == null,
      nothingLogged: consumed.basis == ConsumedBasis.nothingLogged,
      consumedIsAssumed: consumed.basis == ConsumedBasis.tickedPlanMeals,
      hasEstimatedValues: consumed.estimated,
      untrackedMacros: [
        if (targets?.proteinG == null) 'protein',
        if (targets?.carbsG == null) 'carbs',
        if (targets?.fatG == null) 'fat',
      ],
    ),
  );
}

/// The log when it has anything; the planned figures of ticked meals when it
/// doesn't. The [ConsumedBasis] says which — see [ConsumedTotals].
ConsumedTotals _consumedFrom(
  List<FoodLogEntry> log,
  List<Meal> allMeals,
  Set<String> consumedMealIds,
) {
  if (log.isNotEmpty) {
    final totals = totalsOf(log);
    return ConsumedTotals(
      kcal: totals.kcal,
      proteinG: totals.proteinG,
      carbsG: totals.carbsG,
      fatG: totals.fatG,
      basis: totals.allFromPlannedMeals
          ? ConsumedBasis.tickedPlanMeals
          : ConsumedBasis.logged,
      estimated: totals.estimated,
      entryCount: totals.entryCount,
      loggedCount: totals.loggedCount,
    );
  }

  // Nothing logged. Fall back to the planned figures of whatever is ticked —
  // and say so, rather than passing the assumption off as a measurement.
  final eaten = regularMeals(
    allMeals,
  ).where((m) => consumedMealIds.contains(m.id)).toList();
  if (eaten.isEmpty) return ConsumedTotals.none;

  final items = eaten.expand((m) => m.items).toList();
  final macros = macroTotals(items);
  return ConsumedTotals(
    kcal: eaten
        .map(mealCalories)
        .whereType<int>()
        .fold<int>(0, (sum, k) => sum + k),
    proteinG: macros.proteinG ?? 0,
    carbsG: macros.carbsG ?? 0,
    fatG: macros.fatG ?? 0,
    basis: ConsumedBasis.tickedPlanMeals,
    estimated: anyEstimated(items),
    entryCount: 0,
    loggedCount: 0,
  );
}

/// Target minus consumed, or null when no target was set for that macro.
double? _left(double? target, double consumed) =>
    target == null ? null : ((target - consumed) * 10).round() / 10;
