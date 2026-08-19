/// The shape of a [RepTarget] — a fixed count, a min–max range, or AMRAP
/// ("to failure").
enum RepTargetKind { fixed, range, toFailure }

/// Parses a stored [RepTargetKind] name, falling back to `fixed` for any
/// unknown or legacy value.
RepTargetKind repTargetKindFromName(String? name) =>
    RepTargetKind.values.firstWhere((k) => k.name == name, orElse: () => RepTargetKind.fixed);

/// A target for reps on a planned set — a fixed number (10), a range
/// (8–12), or "to failure". Modeled as a value type (not a bare int) so a
/// later progression engine can compare actual reps against min/max targets.
class RepTarget {
  const RepTarget.fixed(int reps)
    : kind = RepTargetKind.fixed,
      min = reps,
      max = reps;

  const RepTarget.range(int min, int max)
    : assert(min <= max),
      kind = RepTargetKind.range,
      min = min,
      max = max;

  const RepTarget.toFailure() : kind = RepTargetKind.toFailure, min = null, max = null;

  final RepTargetKind kind;
  final int? min;
  final int? max;

  @override
  bool operator ==(Object other) =>
      other is RepTarget && other.kind == kind && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(kind, min, max);
}
