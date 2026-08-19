import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/reactive_state_views.dart';
import '../../domain/task.dart';
import '../../domain/task_repository.dart';
import 'task_capture_page.dart';

/// The Tasks list — open tasks first (overdue/priority surfaced, then by due
/// date, undated last), completed tasks below. Tapping a checkbox toggles
/// done; tapping the rest of a row opens it for editing.
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
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TaskCapturePage()),
        ),
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
            return const EmptyStateView('Nothing to do — enjoy the quiet.');
          }
          final now = DateTime.now();
          final open = _sortedOpen(items, now);
          final done = items.where((t) => t.done).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 100),
            children: [
              for (final task in open)
                _TaskRow(
                  task,
                  now: now,
                  onToggle: () => tasks.setDone(task.id, true),
                  onEdit: () => _openEdit(context, tasks, task),
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
                  _TaskRow(
                    task,
                    now: now,
                    onToggle: () => tasks.setDone(task.id, false),
                    onEdit: () => _openEdit(context, tasks, task),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openEdit(
    BuildContext context,
    TaskRepository tasks,
    Task task,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskCapturePage(initial: task)),
    );
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
  });

  final Task task;
  final DateTime now;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final meta = _relativeDue(task.due, now);
    final showOverdue = meta == 'Overdue' && !task.done;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                key: Key('task-toggle-${task.id}'),
                onTap: onToggle,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _CheckBox(checked: task.done),
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
