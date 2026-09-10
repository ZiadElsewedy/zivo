import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/reminders/domain/reminder.dart';

void main() {
  group('Reminder', () {
    test('round-trips through its map codec', () {
      const reminder = Reminder(
        id: 'r1',
        label: 'Breakfast',
        kind: ReminderKind.meal,
        hour: 7,
        minute: 30,
        weekdays: {1, 3, 5},
      );
      final decoded = Reminder.fromMap(reminder.toMap());
      expect(decoded, reminder);
    });

    test('clamps an out-of-range time and drops bad weekdays', () {
      final r = Reminder.clamped(
        id: 'r1',
        label: '  Lunch  ',
        kind: ReminderKind.meal,
        hour: 42,
        minute: -5,
        weekdays: {0, 3, 9},
      );
      expect(r.hour, 23);
      expect(r.minute, 0);
      expect(r.weekdays, {3});
      expect(r.label, 'Lunch', reason: 'label is trimmed');
    });

    test('empty weekdays and a full set both mean every day', () {
      const empty = Reminder(
        id: 'a',
        label: '',
        kind: ReminderKind.other,
        hour: 8,
        minute: 0,
      );
      const full = Reminder(
        id: 'b',
        label: '',
        kind: ReminderKind.other,
        hour: 8,
        minute: 0,
        weekdays: {1, 2, 3, 4, 5, 6, 7},
      );
      expect(empty.isEveryDay, isTrue);
      expect(full.isEveryDay, isTrue);
      expect(empty.effectiveWeekdays, {1, 2, 3, 4, 5, 6, 7});
    });

    test('fromMap rejects a reminder with no usable id', () {
      expect(Reminder.fromMap({'label': 'x'}), isNull);
      expect(Reminder.fromMap({'id': '', 'label': 'x'}), isNull);
      expect(Reminder.fromMap('not a map'), isNull);
    });

    test('unknown kind decodes as other', () {
      expect(ReminderKind.fromName('nope'), ReminderKind.other);
      expect(ReminderKind.fromName(null), ReminderKind.other);
      expect(ReminderKind.fromName('workout'), ReminderKind.workout);
    });

    test('remindersFromStored drops unreadable entries', () {
      final list = remindersFromStored([
        {'id': 'ok', 'label': 'A', 'kind': 'meal', 'hour': 8, 'minute': 0},
        {'label': 'no id'},
        'garbage',
      ]);
      expect(list, hasLength(1));
      expect(list.single.id, 'ok');
    });

    test('remindersFromStored tolerates a non-list', () {
      expect(remindersFromStored(null), isEmpty);
      expect(remindersFromStored('x'), isEmpty);
    });
  });
}
