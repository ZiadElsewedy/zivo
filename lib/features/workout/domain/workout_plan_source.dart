/// Where a [WorkoutPlan]'s content came from. Every route that isn't a plan
/// the user built by hand (`manual`) records how it arrived, mirroring diet's
/// `DietSource`: a `pdf` document, a `photo`/screenshot of one, a `dictated`
/// spoken description, or a `typed` one. The distinction is provenance only —
/// all routes land in the same review editor and the same saved split.
enum WorkoutPlanSource { manual, pdf, photo, dictated, typed }

/// Parses a stored [WorkoutPlanSource] name, falling back to `manual` for any
/// unknown or legacy value.
WorkoutPlanSource workoutPlanSourceFromName(String? name) => WorkoutPlanSource.values
    .firstWhere((s) => s.name == name, orElse: () => WorkoutPlanSource.manual);
