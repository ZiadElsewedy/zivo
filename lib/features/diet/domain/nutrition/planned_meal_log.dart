import '../meal.dart';
import 'food_log_entry.dart';
import 'food_reference.dart';

/// Turns a planned meal into food-log entries.
///
/// This is what makes ticking a meal honest. The interaction stays a single
/// tap, but instead of writing "meal X was eaten" it writes what the plan says
/// that meal WAS — one entry per item, each carrying the plan's own figures,
/// its `estimated` provenance, and a link back to the meal so un-ticking can
/// remove exactly these and nothing else.
///
/// The figures come from the plan document, not the nutrition catalog, and are
/// labelled [NutritionSource.dietPlan] to say so. For an imported plan they
/// were AI-estimated at import time; that flag rides along rather than being
/// laundered into a measurement.
///
/// Pure: [now] and [idPrefix] are injected so the result is deterministic.
List<FoodLogEntry> entriesForPlannedMeal({
  required Meal meal,
  required DateTime day,
  required DateTime now,
  required String idPrefix,
}) {
  final entries = <FoodLogEntry>[];
  for (var i = 0; i < meal.items.length; i++) {
    final item = meal.items[i];
    // An item with no calorie figure contributes nothing countable. It is
    // still logged, at zero, so the day's list shows everything the user
    // ticked rather than quietly dropping the parts the plan never costed.
    entries.add(
      FoodLogEntry(
        id: '$idPrefix-$i',
        day: DateTime(day.year, day.month, day.day),
        loggedAt: now,
        foodId: 'plan:${meal.id}#$i',
        foodName: item.name,
        quantity: item.quantity,
        unit: item.unit,
        // The plan states a quantity in its own unit; it does not state a
        // mass, and inferring one would be a guess. Zero means "not weighed".
        grams: item.unit.toLowerCase() == 'g' ? item.quantity : 0,
        kcal: item.calories ?? 0,
        proteinG: item.proteinG ?? 0,
        carbsG: item.carbsG ?? 0,
        fatG: item.fatG ?? 0,
        source: NutritionSource.dietPlan,
        sourceRef: '${meal.id}#$i',
        origin: FoodLogOrigin.plannedMeal,
        estimated: item.estimated,
        mealId: meal.id,
      ),
    );
  }
  return entries;
}
