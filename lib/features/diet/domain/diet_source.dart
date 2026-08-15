/// Where a [DietPlan]'s content came from. `pdf` is reserved for the
/// document-extraction pipeline in `docs/DECISIONS/ADR-002-document-pdf-pipeline.md`,
/// which is not built yet — this slice only ever writes `manual`.
enum DietSource { manual, pdf }

/// Parses a stored [DietSource] name, falling back to `manual` for any
/// unknown or legacy value.
DietSource dietSourceFromName(String? name) =>
    DietSource.values.firstWhere((s) => s.name == name, orElse: () => DietSource.manual);
