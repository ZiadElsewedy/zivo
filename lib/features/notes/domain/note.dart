/// A fast-captured thought. Body-first; title optional.
class Note {
  const Note({
    required this.id,
    required this.body,
    required this.updatedAt,
    this.title,
  });

  final String id;
  final String body;
  final DateTime updatedAt;
  final String? title;

  /// Title if present, otherwise the first line of the body.
  String get displayTitle {
    if (title != null && title!.trim().isNotEmpty) return title!.trim();
    final firstLine = body.trim().split('\n').first;
    return firstLine.isEmpty ? 'Untitled' : firstLine;
  }
}
