import 'diet_day.dart';
import 'diet_import_result.dart';
import 'diet_plan.dart';
import 'diet_plan_status.dart';
import 'diet_source.dart';
import 'food_item.dart';
import 'meal.dart';

/// Converts an AI-extracted [DietImportResult] (Chunk B+C) into a real,
/// editable [DietPlan] draft — with freshly-minted meal ids, so the result
/// is a genuinely new plan the moment it's saved (never collides with an
/// existing one). [source] is always [DietSource.pdf], the marker reserved
/// for exactly this.
///
/// This produces a DRAFT for review, not a saved plan — the caller pushes
/// it into `DietPlanEditPage(initialPlan: ...)` so the user can fix
/// anything (including any AI-estimated calorie/macro value) before
/// tapping Save; nothing here touches `DietRepository`.
DietPlan dietPlanFromImport(
  DietImportResult result, {
  required String id,
  required DateTime now,
}) {
  final days = <DietDay>[];
  for (var i = 0; i < result.days.length; i++) {
    final importedDay = result.days[i];
    final meals = <Meal>[];
    for (var j = 0; j < importedDay.meals.length; j++) {
      meals.add(_mealFrom(importedDay.meals[j], id: '$id-d$i-m$j', order: j));
    }
    days.add(
      DietDay(
        weekday: importedDay.weekday,
        label: importedDay.label,
        meals: meals,
      ),
    );
  }

  return DietPlan(
    id: id,
    name: result.planName,
    status: DietPlanStatus.active,
    source: DietSource.pdf,
    createdAt: now,
    updatedAt: now,
    days: days,
  );
}

Meal _mealFrom(ImportedMeal meal, {required String id, required int order}) {
  return Meal(
    id: id,
    label: meal.label,
    order: order,
    items: [for (final item in meal.items) _foodItemFrom(item)],
  );
}

FoodItem _foodItemFrom(ImportedFoodItem item) {
  return FoodItem(
    name: item.name,
    quantity: item.quantity,
    unit: item.unit,
    calories: item.calories,
    proteinG: item.proteinG,
    carbsG: item.carbsG,
    fatG: item.fatG,
    estimated: item.estimated,
  );
}
