import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/university/domain/university_item.dart';
import 'package:zivo/features/university/domain/university_item_type.dart';
import 'package:zivo/features/university/presentation/relative_due.dart';

void main() {
  group('UniversityItemType', () {
    test('label round-trips for each value', () {
      expect(UniversityItemType.assignment.label, 'Assignment');
      expect(UniversityItemType.exam.label, 'Exam');
    });
  });

  group('UniversityItem', () {
    test('copyWith flips done and preserves everything else', () {
      final item = UniversityItem(
        id: 'u1',
        title: 'Assignment 2 — Algorithms',
        type: UniversityItemType.assignment,
        createdAt: DateTime(2026, 1, 1),
        due: DateTime(2026, 1, 5),
        courseName: 'Algorithms',
      );

      final done = item.copyWith(done: true);

      expect(done.done, isTrue);
      expect(done.id, item.id);
      expect(done.title, item.title);
      expect(done.type, item.type);
      expect(done.createdAt, item.createdAt);
      expect(done.due, item.due);
      expect(done.courseName, item.courseName);
    });

    test('defaults done to false', () {
      final item = UniversityItem(
        id: 'u1',
        title: 'Undated reading',
        type: UniversityItemType.assignment,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(item.done, isFalse);
      expect(item.due, isNull);
      expect(item.courseName, isNull);
    });
  });

  group('relativeDue', () {
    final now = DateTime(2026, 1, 10);

    test('returns null when there is no due date', () {
      expect(relativeDue(null, now), isNull);
    });

    test('overdue for a past date', () {
      expect(relativeDue(DateTime(2026, 1, 9), now), 'Overdue');
    });

    test('due today', () {
      expect(relativeDue(DateTime(2026, 1, 10), now), 'Due today');
    });

    test('due tomorrow', () {
      expect(relativeDue(DateTime(2026, 1, 11), now), 'Due tomorrow');
    });

    test('a later date formats as "Due D Mon"', () {
      expect(relativeDue(DateTime(2026, 1, 20), now), 'Due 20 Jan');
    });
  });
}
