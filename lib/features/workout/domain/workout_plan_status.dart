/// The lifecycle status of a [WorkoutPlan] — `active` while the user is
/// following it, `archived` once replaced by a newer plan.
enum WorkoutPlanStatus { active, archived }

/// Parses a stored [WorkoutPlanStatus] name, falling back to `active` for any
/// unknown or legacy value.
WorkoutPlanStatus workoutPlanStatusFromName(String? name) => WorkoutPlanStatus.values
    .firstWhere((s) => s.name == name, orElse: () => WorkoutPlanStatus.active);
