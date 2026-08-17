/// Where a [WorkoutPlan]'s content came from. `pdf` is reserved for a future
/// document-extraction pipeline — this slice only ever writes `manual`.
enum WorkoutPlanSource { manual, pdf }
