import '../../tasks/domain/task.dart';
import '../domain/today_snapshot.dart';
import 'widgets/hue.dart';

/// Merges live tasks with demo university deadlines into Today's focus list,
/// ordered by relevance: overdue → due today → tomorrow → the rest.
List<FocusItem> buildFocus({
  required List<Task> tasks,
  required List<FocusItem> deadlines,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));

  final taskItems = tasks.map((t) {
    ZHue hue = ZHue.neutral;
    String? meta;
    if (!t.done && t.due != null) {
      final d = DateTime(t.due!.year, t.due!.month, t.due!.day);
      if (d.isBefore(today)) {
        hue = ZHue.flare;
        meta = 'overdue';
      } else if (d == today) {
        meta = 'due today';
      } else if (d == tomorrow) {
        meta = 'tomorrow';
      }
    }
    return FocusItem(
      title: t.title,
      hue: hue,
      meta: meta,
      done: t.done,
      taskId: t.id,
    );
  }).toList();

  final all = [...taskItems, ...deadlines];

  int rank(FocusItem f) => switch (f.meta) {
        'overdue' => 0,
        'due today' => 1,
        'tomorrow' => 2,
        _ => 3,
      };

  final indexed = [
    for (var i = 0; i < all.length; i++) (rank: rank(all[i]), i: i, item: all[i]),
  ]..sort((a, b) => a.rank != b.rank ? a.rank.compareTo(b.rank) : a.i.compareTo(b.i));

  return [for (final e in indexed) e.item];
}
