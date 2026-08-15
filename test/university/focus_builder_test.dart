import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/home/presentation/focus_builder.dart';
import 'package:zivo/features/home/presentation/widgets/hue.dart';
import 'package:zivo/features/tasks/domain/task.dart';
import 'package:zivo/features/university/domain/university_item.dart';
import 'package:zivo/features/university/domain/university_item_type.dart';

void main() {
  final now = DateTime(2026, 1, 10);
  final today = DateTime(2026, 1, 10);
  final yesterday = DateTime(2026, 1, 9);
  final tomorrow = DateTime(2026, 1, 11);

  group('buildFocus', () {
    test('an overdue iris university item ranks above a non-urgent task', () {
      final tasks = [Task(id: 't1', title: 'Someday task', createdAt: now)];
      final universityItems = [
        UniversityItem(
          id: 'u1',
          title: 'Overdue assignment',
          type: UniversityItemType.assignment,
          createdAt: now,
          due: yesterday,
        ),
      ];

      final result = buildFocus(
        tasks: tasks,
        universityItems: universityItems,
        now: now,
      );

      expect(result.first.title, 'Overdue assignment');
      expect(result.first.hue, ZHue.iris);
      expect(result.first.meta, 'overdue');
      expect(result.first.taskId, isNull);
      expect(result.last.title, 'Someday task');
    });

    test('university items carry no taskId (display-only in Today)', () {
      final universityItems = [
        UniversityItem(
          id: 'u1',
          title: 'Due today exam',
          type: UniversityItemType.exam,
          createdAt: now,
          due: today,
          done: true,
        ),
      ];

      final result = buildFocus(
        tasks: const [],
        universityItems: universityItems,
        now: now,
      );

      expect(result.single.taskId, isNull);
      expect(result.single.done, isTrue);
      // done items get no urgency meta, even if due today.
      expect(result.single.meta, isNull);
    });

    test('due-today, tomorrow, and unranked items keep relative order', () {
      final universityItems = [
        UniversityItem(
          id: 'u-tomorrow',
          title: 'Tomorrow',
          type: UniversityItemType.assignment,
          createdAt: now,
          due: tomorrow,
        ),
        UniversityItem(
          id: 'u-today',
          title: 'Today',
          type: UniversityItemType.assignment,
          createdAt: now,
          due: today,
        ),
      ];

      final result = buildFocus(
        tasks: const [],
        universityItems: universityItems,
        now: now,
      );

      expect(result.map((f) => f.title).toList(), ['Today', 'Tomorrow']);
    });
  });
}
