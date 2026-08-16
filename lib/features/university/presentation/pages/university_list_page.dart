import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/university_item.dart';
import '../../domain/university_item_type.dart';
import '../relative_due.dart';
import 'university_capture_page.dart';

const _otherCourse = 'Other';

/// The University list — assignments and exams grouped by course, soonest
/// due first within each group. A calm, iris-themed surface.
class UniversityListPage extends StatelessWidget {
  const UniversityListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final university = AppScope.of(context).university;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('University', style: AppText.cardTitle),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.iris,
        elevation: 2,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const UniversityCapturePage()),
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: StreamBuilder<List<UniversityItem>>(
        stream: university.watchAll(),
        initialData: university.current,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <UniversityItem>[];
          if (items.isEmpty &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.ink3),
            );
          }
          if (items.isEmpty) {
            return Center(
              child: Text(
                'Nothing due — enjoy the quiet.',
                style: AppText.aside,
              ),
            );
          }
          final now = DateTime.now();
          final groups = _groupByCourse(items);
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 100),
            children: [
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
                  child: Text(
                    entry.key,
                    style: AppText.meta.copyWith(
                      color: AppColors.irisText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final item in entry.value)
                  _UniversityRow(
                    item,
                    now: now,
                    onToggle: () => university.setDone(item.id, !item.done),
                    onEdit: () => _openEdit(context, item),
                    onDelete: () => university.remove(item.id),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openEdit(BuildContext context, UniversityItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UniversityCapturePage(initial: item)),
    );
  }

  Map<String, List<UniversityItem>> _groupByCourse(List<UniversityItem> items) {
    final byCourse = <String, List<UniversityItem>>{};
    for (final item in items) {
      final course = item.courseName?.trim();
      final key = (course == null || course.isEmpty) ? _otherCourse : course;
      byCourse.putIfAbsent(key, () => []).add(item);
    }
    for (final list in byCourse.values) {
      list.sort((a, b) {
        final aDue = a.due;
        final bDue = b.due;
        if (aDue == null && bDue == null) return 0;
        if (aDue == null) return 1;
        if (bDue == null) return -1;
        return aDue.compareTo(bDue);
      });
    }
    final keys = byCourse.keys.toList()
      ..sort((a, b) {
        if (a == _otherCourse && b != _otherCourse) return 1;
        if (b == _otherCourse && a != _otherCourse) return -1;
        return a.compareTo(b);
      });
    return {for (final key in keys) key: byCourse[key]!};
  }
}

class _UniversityRow extends StatelessWidget {
  const _UniversityRow(
    this.item, {
    required this.now,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final UniversityItem item;
  final DateTime now;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final meta = relativeDue(item.due, now);
    final metaText = [item.type.label, ?meta].join(' · ');
    return Dismissible(
      key: Key('university-row-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 14),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppColors.flareText,
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  key: Key('university-toggle-${item.id}'),
                  onTap: onToggle,
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _CheckBox(checked: item.done),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.rowTitle.copyWith(
                          fontWeight: FontWeight.w600,
                          color: item.done ? AppColors.ink3 : AppColors.ink,
                          decoration: item.done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          decorationColor: AppColors.ink3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        metaText,
                        style: AppText.meta.copyWith(
                          color: meta == 'Overdue'
                              ? AppColors.flareText
                              : AppColors.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: checked ? AppColors.iris : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: checked ? AppColors.iris : AppColors.hairline2,
          width: 1.6,
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : null,
    );
  }
}
