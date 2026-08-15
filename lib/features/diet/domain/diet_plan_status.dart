/// The lifecycle status of a [DietPlan] — `draft` while a (future) PDF import
/// awaits review, `active` once the user is following it, `archived` once
/// replaced by a newer plan.
enum DietPlanStatus { draft, active, archived }

/// Parses a stored [DietPlanStatus] name, falling back to `active` for any
/// unknown or legacy value.
DietPlanStatus dietPlanStatusFromName(String? name) => DietPlanStatus.values
    .firstWhere((s) => s.name == name, orElse: () => DietPlanStatus.active);
