/// Where a [DietPlan]'s content came from.
///
/// This is provenance, not decoration: an imported plan's calories were
/// produced by a model reading the user's material (see `diet/FEATURE.md`),
/// and a hand-written one's were typed by the user. The library screen shows
/// it, so "where did this plan come from" is answerable months later.
///
/// [pdf] predates the others and still means "a document was imported"; a
/// photo import writes [photo], a dictated one writes [dictated], and a plan
/// ZIVO designed writes [generated] — the one case where the app itself chose
/// the food, which is exactly when provenance matters most. An
/// unknown or legacy value reads as [manual] — the honest reading of a value
/// ZIVO can't account for is "a person put this here", never a claim that a
/// model produced it.
enum DietSource { manual, pdf, photo, dictated, generated }

/// Parses a stored [DietSource] name, falling back to `manual` for any
/// unknown or legacy value.
DietSource dietSourceFromName(String? name) => DietSource.values.firstWhere(
  (s) => s.name == name,
  orElse: () => DietSource.manual,
);

/// How a plan's origin reads on screen.
String dietSourceLabel(DietSource source) => switch (source) {
  DietSource.manual => 'Written by hand',
  DietSource.pdf => 'Imported from a document',
  DietSource.photo => 'Imported from a photo',
  DietSource.dictated => 'Dictated',
  DietSource.generated => 'Built by ZIVO',
};

/// Whether this plan's figures came out of an extraction rather than from the
/// user typing them — the plans that carry AI-estimated values.
bool dietSourceIsImported(DietSource source) => source != DietSource.manual;
