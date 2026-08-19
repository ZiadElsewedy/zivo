/// The role of a planned set within an exercise: a warmup ramp, a working
/// set, a dropset, or a set taken to failure.
enum SetType { warmup, working, dropset, failure }

/// Parses a stored [SetType] name, falling back to `working` for any unknown
/// or legacy value.
SetType setTypeFromName(String? name) =>
    SetType.values.firstWhere((t) => t.name == name, orElse: () => SetType.working);
