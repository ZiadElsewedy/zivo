import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/home/domain/today_snapshot.dart';
import 'package:zivo/features/home/presentation/header_builder.dart';
import 'package:zivo/features/home/presentation/widgets/hue.dart';

void main() {
  group('formatTodayDate', () {
    test('formats as "Weekday · D Month"', () {
      expect(formatTodayDate(DateTime(2026, 8, 15)), 'Saturday · 15 August');
    });

    test('formats a different weekday and month', () {
      expect(formatTodayDate(DateTime(2026, 1, 1)), 'Thursday · 1 January');
    });
  });

  group('greetingFor', () {
    test('morning bucket (before noon) with a name', () {
      expect(greetingFor(DateTime(2026, 1, 1, 8), 'Ziad'), 'Morning, Ziad');
    });

    test('afternoon bucket (noon–5pm) with a name', () {
      expect(greetingFor(DateTime(2026, 1, 1, 14), 'Ziad'), 'Afternoon, Ziad');
    });

    test('evening bucket (6pm and later) with a name', () {
      expect(greetingFor(DateTime(2026, 1, 1, 20), 'Ziad'), 'Evening, Ziad');
    });

    test('boundary hours land in the right bucket', () {
      expect(greetingFor(DateTime(2026, 1, 1, 11, 59), 'Ziad'), 'Morning, Ziad');
      expect(greetingFor(DateTime(2026, 1, 1, 12), 'Ziad'), 'Afternoon, Ziad');
      expect(greetingFor(DateTime(2026, 1, 1, 17, 59), 'Ziad'), 'Afternoon, Ziad');
      expect(greetingFor(DateTime(2026, 1, 1, 18), 'Ziad'), 'Evening, Ziad');
    });

    test('falls back to a nameless greeting when name is null or blank', () {
      expect(greetingFor(DateTime(2026, 1, 1, 8), null), 'Good Morning');
      expect(greetingFor(DateTime(2026, 1, 1, 8), '   '), 'Good Morning');
    });

    test('uses only the first word of a multi-word name', () {
      expect(
        greetingFor(DateTime(2026, 1, 1, 8), 'Ziad Elsewedy'),
        'Morning, Ziad',
      );
    });

    test('uses the whole name when it is a single word', () {
      expect(greetingFor(DateTime(2026, 1, 1, 8), 'Ziad'), 'Morning, Ziad');
    });
  });

  group('buildAside', () {
    test('a clear day with no focus items and no next event', () {
      expect(
        buildAside(focus: const [], next: null),
        'A clear day — nothing pressing.',
      );
    });

    test('only pending focus items, singular', () {
      final focus = [
        const FocusItem(title: 'Finish essay', hue: ZHue.iris),
      ];
      expect(
        buildAside(focus: focus, next: null),
        'One thing on your list today.',
      );
    });

    test('only pending focus items, plural', () {
      final focus = [
        const FocusItem(title: 'A', hue: ZHue.neutral),
        const FocusItem(title: 'B', hue: ZHue.neutral),
      ];
      expect(
        buildAside(focus: focus, next: null),
        '2 things on your list today.',
      );
    });

    test('done focus items are excluded from the pending count', () {
      final focus = [
        const FocusItem(title: 'Done', hue: ZHue.neutral, done: true),
      ];
      expect(
        buildAside(focus: focus, next: null),
        'A clear day — nothing pressing.',
      );
    });

    test('only a next event', () {
      const next = NowNext(
        kind: 'Lecture',
        time: 'in 2h',
        title: 'Data Structures',
        detail: '',
      );
      expect(
        buildAside(focus: const [], next: next),
        'Next up: Data Structures.',
      );
    });

    test('busy day: both pending focus items and a next event', () {
      final focus = [
        const FocusItem(title: 'Finish essay', hue: ZHue.iris),
      ];
      const next = NowNext(
        kind: 'Lecture',
        time: 'in 2h',
        title: 'Data Structures',
        detail: '',
      );
      expect(
        buildAside(focus: focus, next: next),
        'One thing on your list today, and next up: Data Structures.',
      );
    });
  });
}
