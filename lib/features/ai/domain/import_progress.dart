/// Live progress from a PDF/photo import, as the model writes its answer.
///
/// A plan import is one long, opaque model call: it emits no assistant text at
/// all (the extractor forces a tool call), so the only thing that genuinely
/// moves is the **structured output being written** — days and exercises,
/// meals and food items, appearing one at a time. The gateway scans that
/// partially-streamed tool input and forwards these snapshots.
///
/// This replaced a timer that cycled three hardcoded lines every 1.6s
/// regardless of what the backend was doing. The distinction that matters:
/// every field here is something the model has *actually extracted*, so an
/// import that stalls now visibly stalls instead of animating reassuringly.
///
/// One type serves both importers, because both are "sections containing
/// items" and the screens render them the same way:
///
/// | | [sections] | [items] |
/// |---|---|---|
/// | Workout | training day labels (`Push`, `Pull`) | exercises |
/// | Diet | day **and** meal labels (`Every day`, `Breakfast`) | food items |
///
/// The diet schema reuses one key for days and meals, so its labels arrive as
/// a single ordered list; [latestSection] is the honest thing to show for both.
class ImportProgress {
  const ImportProgress({
    this.planName,
    this.sections = const [],
    this.items = 0,
  });

  /// The plan's name, once the model has written it. Null early on — it is
  /// usually the first field, but nothing guarantees that.
  final String? planName;

  /// Section labels extracted so far, in the order the model wrote them.
  final List<String> sections;

  /// How many leaf items (exercises, or food items) have landed so far.
  final int items;

  /// The section being extracted right now — the last one to appear.
  ///
  /// Only complete labels are ever reported, so this is never a half-written
  /// word: a label still streaming simply isn't here yet.
  String? get latestSection => sections.isEmpty ? null : sections.last;

  /// True before anything at all has been extracted, so a caller can keep
  /// showing its opening line rather than an empty progress row.
  bool get isEmpty => planName == null && sections.isEmpty && items == 0;

  /// Parses one `{type: 'progress', ...}` chunk from either importer, or null
  /// if it isn't one. The two callables name their list differently — `days`
  /// for workouts, `labels` for diet — because on the server they mean
  /// different things; both land in [sections].
  static ImportProgress? fromChunk(Object? chunk) {
    if (chunk is! Map) return null;
    if (chunk['type'] != 'progress') return null;
    final raw = chunk['days'] ?? chunk['labels'];
    final sections = raw is List
        ? raw.whereType<String>().where((s) => s.isNotEmpty).toList()
        : const <String>[];
    final count = chunk['exercises'] ?? chunk['items'];
    final name = chunk['planName'];
    return ImportProgress(
      planName: name is String && name.isNotEmpty ? name : null,
      sections: sections,
      items: count is int ? count : 0,
    );
  }
}
