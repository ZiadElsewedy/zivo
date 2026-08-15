import '../../tasks/domain/task.dart';
import '../../university/domain/university_item.dart';
import '../domain/today_snapshot.dart';
import 'widgets/hue.dart';

/// Merges live tasks with live university items into Today's focus list,
/// ordered by relevance: overdue → due today → tomorrow → the rest.
List<FocusItem> buildFocus({
  required List<Task> tasks,
  required List<UniversityItem> universityItems,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));

  String? metaFor(DateTime? due, {required bool done}) {
    if (done || due == null) return null;
    final d = DateTime(due.year, due.month, due.day);
    if (d.isBefore(today)) return 'overdue';
    if (d == today) return 'due today';
    if (d == tomorrow) return 'tomorrow';
    return null;
  }

  final taskItems = tasks.map((t) {
    final meta = metaFor(t.due, done: t.done);
    return FocusItem(
      title: t.title,
      hue: meta == 'overdue' ? ZHue.flare : ZHue.neutral,
      meta: meta,
      done: t.done,
      taskId: t.id,
    );
  }).toList();

  final universityFocusItems = universityItems.map((u) {
    return FocusItem(
      title: u.title,
      hue: ZHue.iris,
      meta: metaFor(u.due, done: u.done),
      done: u.done,
    );
  }).toList();

  final all = [...taskItems, ...universityFocusItems];

  int rank(FocusItem f) => switch (f.meta) {
    'overdue' => 0,
    'due today' => 1,
    'tomorrow' => 2,
    _ => 3,
  };

  final indexed =
      [
        for (var i = 0; i < all.length; i++)
          (rank: rank(all[i]), i: i, item: all[i]),
      ]..sort(
        (a, b) =>
            a.rank != b.rank ? a.rank.compareTo(b.rank) : a.i.compareTo(b.i),
      );

  return [for (final e in indexed) e.item];
}
