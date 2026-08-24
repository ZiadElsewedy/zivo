/// One food item as extracted from an imported PDF (Chunk B+C) — calories
/// and macros are never left null (see [estimated]): the server either read
/// them from the document or estimated them from standard nutritional data
/// for the stated food and quantity.
class ImportedFoodItem {
  const ImportedFoodItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.estimated,
  });

  final String name;
  final double quantity;
  final String unit;
  final int? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;

  /// True if the server had to estimate any of calories/proteinG/carbsG/
  /// fatG for this item because the document didn't state it.
  final bool estimated;
}

/// One meal as extracted from an imported PDF.
class ImportedMeal {
  const ImportedMeal({required this.label, required this.items});

  final String label;
  final List<ImportedFoodItem> items;
}

/// One day as extracted from an imported PDF.
class ImportedDietDay {
  const ImportedDietDay({
    required this.weekday,
    required this.label,
    required this.meals,
  });

  /// 1=Monday..7=Sunday, or null for a single every-day template.
  final int? weekday;
  final String label;
  final List<ImportedMeal> meals;
}

/// The full proposed diet plan extracted from a PDF — never saved directly;
/// the caller reviews/edits it (reusing `DietPlanEditPage`) before it
/// becomes a real, saved plan. See `dietPlanFromImport` in this same
/// feature for the conversion into a domain `DietPlan`.
///
/// Lives in the diet domain (not `ai/domain/`) because it's fundamentally
/// diet-shaped data — the same convention `WorkoutImportResult` follows.
/// `AiRepository.importDietPlan` (a generic AI transport method that
/// happens to produce a diet-specific artifact) imports it from here, not
/// the other way around.
class DietImportResult {
  const DietImportResult({required this.planName, required this.days});

  final String planName;
  final List<ImportedDietDay> days;
}
