import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/reminders/domain/reminder.dart';
import 'package:zivo/features/reminders/domain/reminder_sync.dart';

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
        kind: ReminderKind.general,
        hour: 8,
        minute: 0,
      );
      const full = Reminder(
        id: 'b',
        label: '',
        kind: ReminderKind.general,
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

    test('unknown or legacy kind decodes as general', () {
      expect(ReminderKind.fromName('nope'), ReminderKind.general);
      expect(ReminderKind.fromName(null), ReminderKind.general);
      // The retired "other" kind folds into its replacement, general.
      expect(ReminderKind.fromName('other'), ReminderKind.general);
      expect(ReminderKind.fromName('workout'), ReminderKind.workout);
      expect(ReminderKind.fromName('general'), ReminderKind.general);
    });

    test('a plain reminder has no sync and round-trips without one', () {
      const reminder = Reminder(
        id: 'r1',
        label: 'Stretch',
        kind: ReminderKind.general,
        hour: 9,
        minute: 0,
      );
      final map = reminder.toMap();
      expect(map.containsKey('sync'), isFalse);
      expect(Reminder.fromMap(map)?.sync, isNull);
    });

    test('a meal sync round-trips through the codec', () {
      const reminder = Reminder(
        id: 'r2',
        label: '',
        kind: ReminderKind.meal,
        hour: 13,
        minute: 0,
        sync: MealSync(mealLabel: 'Lunch', items: ['Chicken 200 g', 'Rice 150 g']),
      );
      final decoded = Reminder.fromMap(reminder.toMap());
      expect(decoded, reminder);
      expect((decoded!.sync as MealSync).items, ['Chicken 200 g', 'Rice 150 g']);
    });

    test('a workout sync round-trips through the codec', () {
      const reminder = Reminder(
        id: 'r3',
        label: 'Train',
        kind: ReminderKind.workout,
        hour: 18,
        minute: 30,
        sync: WorkoutSync(cachedDayLabel: 'Push Day'),
      );
      final decoded = Reminder.fromMap(reminder.toMap());
      expect(decoded, reminder);
      expect((decoded!.sync as WorkoutSync).cachedDayLabel, 'Push Day');
      // Absent in the map means not motivational — the original behaviour.
      expect((decoded.sync as WorkoutSync).motivational, isFalse);
    });

    test('a motivational workout sync round-trips through the codec', () {
      const reminder = Reminder(
        id: 'r3m',
        label: 'Train',
        kind: ReminderKind.workout,
        hour: 18,
        minute: 30,
        sync: WorkoutSync(cachedDayLabel: 'Push Day', motivational: true),
      );
      final decoded = Reminder.fromMap(reminder.toMap());
      expect(decoded, reminder);
      expect((decoded!.sync as WorkoutSync).motivational, isTrue);
    });

    test('an unrecognised stored sync degrades to a plain reminder', () {
      final decoded = Reminder.fromMap({
        'id': 'r4',
        'label': 'x',
        'kind': 'meal',
        'hour': 8,
        'minute': 0,
        'sync': {'type': 'mystery'},
      });
      expect(decoded?.sync, isNull);
    });

    test('copyWith preserves sync but can clear it', () {
      const reminder = Reminder(
        id: 'r5',
        label: 'Lunch',
        kind: ReminderKind.meal,
        hour: 12,
        minute: 0,
        sync: MealSync(mealLabel: 'Lunch', items: ['Soup']),
      );
      expect(reminder.copyWith(enabled: false).sync, reminder.sync);
      expect(reminder.copyWith(clearSync: true).sync, isNull);
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
