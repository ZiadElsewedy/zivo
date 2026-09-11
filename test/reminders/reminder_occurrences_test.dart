import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/reminders/data/local_notification_scheduler.dart';
import 'package:zivo/features/reminders/domain/notification_scheduler.dart';
import 'package:zivo/features/reminders/domain/reminder.dart';
import 'package:zivo/features/reminders/domain/reminder_sync.dart';

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
        kind: ReminderKind.general,
        hour: 9,
        minute: 0,
        enabled: false,
      );
      expect(reminderOccurrences(const [r], fallbackTitle: 'Reminder'), isEmpty);
    });

    test('an unlabelled reminder uses the fallback title and no body', () {
      const r = Reminder(
        id: 'a',
        label: '',
        kind: ReminderKind.general,
        hour: 9,
        minute: 0,
      );
      final occ = reminderOccurrences(const [r], fallbackTitle: 'Reminder');
      expect(occ.single.title, 'Reminder');
      expect(occ.single.body, isNull);
    });

    test('a meal sync lists its items in the body', () {
      const r = Reminder(
        id: 'a',
        label: '',
        kind: ReminderKind.meal,
        hour: 13,
        minute: 0,
        sync: MealSync(mealLabel: 'Lunch', items: ['Chicken 200 g', 'Rice']),
      );
      final occ = reminderOccurrences(const [r], fallbackTitle: 'Reminder');
      expect(occ.single.title, 'Lunch');
      expect(occ.single.body, 'Chicken 200 g · Rice');
    });

    test('a workout sync takes its text from the context', () {
      const r = Reminder(
        id: 'a',
        label: '',
        kind: ReminderKind.workout,
        hour: 18,
        minute: 0,
        sync: WorkoutSync(),
      );
      final occ = reminderOccurrences(
        const [r],
        fallbackTitle: 'Reminder',
        context: const ReminderContext(
          workoutTitle: 'Push Day',
          workoutBody: 'Bench · OHP +2',
        ),
      );
      expect(occ.single.title, 'Push Day');
      expect(occ.single.body, 'Bench · OHP +2');
    });

    test('a labelled workout sync keeps its label and shows the day in the body', () {
      const r = Reminder(
        id: 'a',
        label: 'Time to lift',
        kind: ReminderKind.workout,
        hour: 18,
        minute: 0,
        sync: WorkoutSync(),
      );
      final occ = reminderOccurrences(
        const [r],
        fallbackTitle: 'Reminder',
        context: const ReminderContext(
          workoutTitle: 'Push Day',
          workoutBody: 'Bench · OHP',
        ),
      );
      expect(occ.single.title, 'Time to lift');
      expect(occ.single.body, 'Push Day — Bench · OHP');
    });

    test('a workout sync with no resolved plan falls back to its label', () {
      const r = Reminder(
        id: 'a',
        label: 'Workout',
        kind: ReminderKind.workout,
        hour: 18,
        minute: 0,
        sync: WorkoutSync(),
      );
      final occ = reminderOccurrences(const [r], fallbackTitle: 'Reminder');
      expect(occ.single.title, 'Workout');
      expect(occ.single.body, isNull);
    });

    test('a motivational sync shows the day and the motivation, not the '
        'exercise list', () {
      const r = Reminder(
        id: 'a',
        label: '',
        kind: ReminderKind.workout,
        hour: 18,
        minute: 0,
        sync: WorkoutSync(motivational: true),
      );
      final occ = reminderOccurrences(
        const [r],
        fallbackTitle: 'Reminder',
        context: const ReminderContext(
          workoutTitle: 'Arm Day',
          workoutBody: 'Curl · Press · Dips +2',
          workoutMotivation: "Keep going — you've got this.",
        ),
      );
      // The day is the title; the body is the motivation, never the exercises.
      expect(occ.single.title, 'Arm Day');
      expect(occ.single.body, "Keep going — you've got this.");
    });

    test('a labelled motivational sync keeps its label and folds the day into '
        'the motivation line', () {
      const r = Reminder(
        id: 'a',
        label: 'Tamreen time',
        kind: ReminderKind.workout,
        hour: 18,
        minute: 0,
        sync: WorkoutSync(motivational: true),
      );
      final occ = reminderOccurrences(
        const [r],
        fallbackTitle: 'Reminder',
        context: const ReminderContext(
          workoutTitle: 'Arm Day',
          workoutBody: 'Curl · Press',
          workoutMotivation: "Don't skip it.",
        ),
      );
      expect(occ.single.title, 'Tamreen time');
      expect(occ.single.body, "Arm Day · Don't skip it.");
    });

    test('a motivational sync still encourages when no plan day is resolved', () {
      const r = Reminder(
        id: 'a',
        label: '',
        kind: ReminderKind.workout,
        hour: 18,
        minute: 0,
        sync: WorkoutSync(motivational: true),
      );
      final occ = reminderOccurrences(
        const [r],
        fallbackTitle: 'Reminder',
        context: const ReminderContext(
          workoutMotivation: 'Show up for yourself today.',
        ),
      );
      // No day resolved: the fallback titles it, the motivation is the body.
      expect(occ.single.title, 'Reminder');
      expect(occ.single.body, 'Show up for yourself today.');
    });
  });
}
