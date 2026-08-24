import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/reactive_state_views.dart';
import '../../../workout/presentation/widgets/staggered_reveal.dart';
import '../../domain/task.dart';
import '../../domain/task_repository.dart';
import 'task_capture_page.dart';

/// The Tasks list — open tasks first (overdue/priority surfaced, then by due
/// date, undated last), completed tasks below. Tapping a checkbox toggles
/// done; tapping the rest of a row opens it for editing; swiping a row left
/// deletes it (same confirm-sheet convention as the Ask chat's session
/// delete — see `_confirmDeleteTask`).
class TaskListPage extends StatelessWidget {
  const TaskListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = AppScope.of(context).tasks;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Tasks', style: AppText.cardTitle),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.ink,
        elevation: 2,
        tooltip: 'New task',
        onPressed: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TaskCapturePage()),
          );
        },
        child: const Icon(Icons.add_rounded, color: AppColors.ground),
      ),
      body: StreamBuilder<List<Task>>(
        stream: tasks.watchAll(),
        initialData: tasks.current,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const ErrorStateView();
          }
          final items = snapshot.data ?? const <Task>[];
          if (items.isEmpty &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingStateView();
          }
          if (items.isEmpty) {
            return const _TasksEmptyState();
          }
          final now = DateTime.now();
          final open = _sortedOpen(items, now);
          final done = items.where((t) => t.done).toList();
          var index = 0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 100),
            children: [
              for (final task in open)
                StaggeredReveal(
                  index: index++,
                  child: _TaskRow(
                    task,
                    now: now,
                    onToggle: () {
                      HapticFeedback.selectionClick();
                      tasks.setDone(task.id, true);
                    },
                    onEdit: () => _openEdit(context, task),
                    onDelete: () => _deleteTask(context, tasks, task),
                  ),
                ),
              if (done.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
                  child: Text(
                    'Done',
                    style: AppText.meta.copyWith(
                      color: AppColors.ink3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final task in done)
                  StaggeredReveal(
                    index: index++,
                    child: _TaskRow(
                      task,
                      now: now,
                      onToggle: () {
                        HapticFeedback.selectionClick();
                        tasks.setDone(task.id, false);
                      },
                      onEdit: () => _openEdit(context, task),
                      onDelete: () => _deleteTask(context, tasks, task),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openEdit(BuildContext context, Task task) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskCapturePage(initial: task)),
    );
  }

  Future<void> _deleteTask(
    BuildContext context,
    TaskRepository tasks,
    Task task,
  ) async {
    await tasks.delete(task.id);
  }

  List<Task> _sortedOpen(List<Task> items, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final open = items.where((t) => !t.done).toList()
      ..sort((a, b) {
        final aOverdue = _isOverdue(a, today);
        final bOverdue = _isOverdue(b, today);
        if (aOverdue != bOverdue) return aOverdue ? -1 : 1;
        if (a.priority != b.priority) return a.priority ? -1 : 1;
        final aDue = a.due;
        final bDue = b.due;
        if (aDue == null && bDue == null) return 0;
        if (aDue == null) return 1;
        if (bDue == null) return -1;
        return aDue.compareTo(bDue);
      });
    return open;
  }

  bool _isOverdue(Task task, DateTime today) {
    final due = task.due;
    if (due == null) return false;
    final day = DateTime(due.year, due.month, due.day);
    return day.isBefore(today);
  }
}

/// A calm, on-brand empty state — the shared [EmptyStateView] is just
/// centered text; this adds the small tinted icon-chip language the rest of
/// the app's empty states use (e.g. Workout's `_NoPlanState` family), so an
/// empty task list reads as "the app is fine, you just have nothing due"
/// rather than a bare line of italic text floating in the dark.
class _TasksEmptyState extends StatelessWidget {
  const _TasksEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.pulse.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 28,
                color: AppColors.pulse,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Nothing to do',
              style: AppText.cardTitle.copyWith(color: AppColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Enjoy the quiet, or tap + to add something.',
              style: AppText.body.copyWith(color: AppColors.ink3),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact, human relative-due label, e.g. "Overdue", "Due today", "Due
/// tomorrow", or "Due 5 Sep". Null if there is no due date.
String? _relativeDue(DateTime? due, DateTime now) {
  if (due == null) return null;
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  if (day.isBefore(today)) return 'Overdue';
  if (day == today) return 'Due today';
  if (day == today.add(const Duration(days: 1))) return 'Due tomorrow';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return 'Due ${day.day} ${months[day.month - 1]}';
}

class _TaskRow extends StatelessWidget {
  const _TaskRow(
    this.task, {
    required this.now,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Task task;
  final DateTime now;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final meta = _relativeDue(task.due, now);
    final showOverdue = meta == 'Overdue' && !task.done;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Dismissible(
        key: ValueKey(task.id),
        direction: DismissDirection.endToStart,
        background: const _DeleteTaskSwipeBackground(),
        onUpdate: (details) {
          // Fires once, right as the swipe crosses the dismiss threshold —
          // same "point of no return" haptic as the chat-delete swipe.
          if (details.reached && !details.previousReached) {
            HapticFeedback.mediumImpact();
          }
        },
        confirmDismiss: (_) => _confirmDeleteTask(context, task.title),
        onDismissed: (_) => onDelete(),
        child: PressableScale(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PressableScale(
                      child: InkWell(
                        key: Key('task-toggle-${task.id}'),
                        onTap: onToggle,
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: _CheckBox(checked: task.done),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    task.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.rowTitle.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: task.done
                                          ? AppColors.ink3
                                          : AppColors.ink,
                                      decoration: task.done
                                          ? TextDecoration.lineThrough
                                          : TextDecoration.none,
                                      decorationColor: AppColors.ink3,
                                    ),
                                  ),
                                ),
                                if (task.priority && !task.done) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.priority_high_rounded,
                                    size: 15,
                                    color: AppColors.flareText,
                                  ),
                                ],
                              ],
                            ),
                            if (meta != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                meta,
                                style: AppText.meta.copyWith(
                                  color: showOverdue
                                      ? AppColors.flareText
                                      : AppColors.ink3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The red trailing reveal shown as a task row is swiped left to delete —
/// same visual language as the Ask chat's `_DeleteChatSwipeBackground`. The
/// confirm sheet ([_confirmDeleteTask]) still gates the actual delete.
class _DeleteTaskSwipeBackground extends StatelessWidget {
  const _DeleteTaskSwipeBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.flare.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: AppColors.flare),
    );
  }
}

/// Confirms deleting a task — a bottom sheet, not a centered dialog, so the
/// destructive action sits right under the thumb that just swiped it (same
/// convention as the Ask chat's `_confirmDeleteChat`).
Future<bool> _confirmDeleteTask(BuildContext context, String title) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screen,
          14,
          AppSpacing.screen,
          8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.hairline2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Delete this task?',
              style: AppText.cardTitle.copyWith(color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'This permanently removes "$title". '
              "This can't be undone.",
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: AppColors.ink2),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: _SheetAction(
                label: 'Delete task',
                color: AppColors.flare,
                background: AppColors.flareWash,
                onTap: () => Navigator.pop(context, true),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: _SheetAction(
                label: 'Cancel',
                color: AppColors.ink2,
                background: Colors.transparent,
                onTap: () => Navigator.pop(context, false),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return confirmed ?? false;
}

/// One full-width row in [_confirmDeleteTask]'s action sheet.
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.label,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                label,
                style: AppText.button.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: checked ? AppColors.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: checked ? AppColors.ink : AppColors.hairline2,
          width: 1.6,
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 13, color: AppColors.ground)
          : null,
    );
  }
}
