/// Where a [WorkoutPlan]'s content came from. `pdf` is reserved for a future
/// document-extraction pipeline — this slice only ever writes `manual`.
enum WorkoutPlanSource { manual, pdf }

/// Parses a stored [WorkoutPlanSource] name, falling back to `manual` for any
/// unknown or legacy value.
WorkoutPlanSource workoutPlanSourceFromName(String? name) => WorkoutPlanSource.values
    .firstWhere((s) => s.name == name, orElse: () => WorkoutPlanSource.manual);
