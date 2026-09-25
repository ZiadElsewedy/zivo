/// One exercise as extracted from an imported PDF (WORKOUT_SYSTEM.md §3.4,
/// Phase 6) — a flat, compact spec (N identical sets), matching how the plan
/// editor's own exercise sheet already builds a [PlannedExercise].
class ImportedExercise {
  const ImportedExercise({
    required this.name,
    this.muscleGroup,
    required this.sets,
    this.repsMin,
    this.repsMax,
    required this.toFailure,
    this.targetWeightKg,
    this.restSeconds,
  });

  final String name;
  final String? muscleGroup;
  final int sets;
  final int? repsMin;
  final int? repsMax;
  final bool toFailure;
  final double? targetWeightKg;
  final int? restSeconds;
}

/// One day as extracted from an imported PDF.
class ImportedDay {
  const ImportedDay({required this.slot, required this.label, required this.exercises});

  final String slot;
  final String label;
  final List<ImportedExercise> exercises;
}

/// The full proposed split extracted from a PDF — never saved directly; the
/// caller reviews/edits it (reusing `WorkoutPlanEditPage` in `asSplit` mode)
/// before it becomes a real, saved split. See `workoutPlanFromImport` in this
/// same feature for the conversion into a domain `WorkoutPlan`.
///
/// Lives in the workout domain (not `ai/domain/`) because it's fundamentally
/// workout-shaped data — the same convention every other workout type
/// follows. `AiRepository.importWorkoutPlan` (a generic AI transport method
/// that happens to produce a workout-specific artifact) imports it from here,
/// not the other way around.
class WorkoutImportResult {
  const WorkoutImportResult({required this.planName, required this.days});

  final String planName;
  final List<ImportedDay> days;
}
