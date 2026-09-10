import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/reminders/data/local_notification_scheduler.dart';
import 'package:zivo/features/reminders/domain/reminder.dart';

void main() {
  group('reminderOccurrences', () {
    test('an every-day reminder becomes a single daily occurrence', () {
      const r = Reminder(
        id: 'a',
        label: 'Breakfast',
        kind: ReminderKind.meal,
        hour: 8,
        minute: 0,
      );
      final occ = reminderOccurrences(const [r], fallbackTitle: 'Reminder');
      expect(occ, hasLength(1));
      expect(occ.single.weekday, isNull);
      expect(occ.single.title, 'Breakfast');
      expect(occ.single.hour, 8);
    });

    test('a multi-day reminder becomes one occurrence per chosen weekday', () {
      const r = Reminder(
        id: 'a',
        label: 'Leg day',
        kind: ReminderKind.workout,
        hour: 18,
        minute: 30,
        weekdays: {1, 3, 5},
      );
      final occ = reminderOccurrences(const [r], fallbackTitle: 'Reminder');
      expect(occ, hasLength(3));
      expect(occ.map((o) => o.weekday).toSet(), {1, 3, 5});
    });

    test('disabled reminders produce nothing', () {
      const r = Reminder(
        id: 'a',
        label: 'Off',
        kind: ReminderKind.other,
        hour: 9,
        minute: 0,
        enabled: false,
      );
      expect(reminderOccurrences(const [r], fallbackTitle: 'Reminder'), isEmpty);
    });

    test('an unlabelled reminder uses the fallback title', () {
      const r = Reminder(
        id: 'a',
        label: '',
        kind: ReminderKind.other,
        hour: 9,
        minute: 0,
      );
      final occ = reminderOccurrences(const [r], fallbackTitle: 'Reminder');
      expect(occ.single.title, 'Reminder');
    });
  });
}
