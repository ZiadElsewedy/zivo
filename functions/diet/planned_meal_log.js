/**
 * The server's mirror of `lib/features/diet/domain/nutrition/
 * planned_meal_log.dart` (`entriesForPlannedMeal`): ticking a planned meal
 * writes what the plan says that meal WAS — one food-log entry per item, with
 * the plan's own figures, its `estimated` provenance, and a link back to the
 * meal so un-ticking removes exactly these and nothing else.
 *
 * Until this existed a meal ticked from Ask wrote only its `dietEntries` tick,
 * so on any day that also had a logged food the meal silently dropped out of
 * "what was eaten" (consumption reads the log whenever it has anything). The
 * ids and fields match the app's byte for byte, so a meal ticked on either
 * side and un-ticked on the other still removes cleanly.
 *
 * Pure: the caller writes the rows.
 */

/**
 * @param {!Object} meal A plan Meal (`{id, items}`).
 * @param {string} dayKey 'yyyy-MM-dd'
 * @return {!Array<!Object>} Rows in `store.writeFoodLog`'s shape.
 */
function entriesForPlannedMeal(meal, dayKey) {
  return (meal.items || []).map((item, i) => ({
    id: `${dayKey}__${meal.id}-${i}`,
    dayKey,
    foodId: `plan:${meal.id}#${i}`,
    foodName: item.name,
    quantity: item.quantity,
    unit: item.unit,
    // The plan states a quantity in its own unit, not a mass; zero means
    // "not weighed" rather than a guessed conversion.
    grams: String(item.unit || "").toLowerCase() === "g" ? item.quantity : 0,
    kcal: typeof item.calories === "number" ? item.calories : 0,
    proteinG: typeof item.proteinG === "number" ? item.proteinG : 0,
    carbsG: typeof item.carbsG === "number" ? item.carbsG : 0,
    fatG: typeof item.fatG === "number" ? item.fatG : 0,
    source: "dietPlan",
    sourceRef: `${meal.id}#${i}`,
    origin: "plannedMeal",
    estimated: item.estimated === true,
    mealId: meal.id,
  }));
}

module.exports = {entriesForPlannedMeal};
