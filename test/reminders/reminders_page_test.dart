import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/core/theme/zivo_palette.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/reminders/data/in_memory_reminders_repository.dart';
import 'package:zivo/features/reminders/domain/notification_scheduler.dart';
import 'package:zivo/features/reminders/domain/reminder.dart';
import 'package:zivo/features/reminders/domain/reminder_sync.dart';
import 'package:zivo/features/reminders/presentation/pages/reminders_page.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

import '../support/bidi_finders.dart';
import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

void main() {
  setUp(() => ZivoTheme.use(Brightness.dark));
  tearDown(ZivoTheme.resetForTesting);

  Widget host(InMemoryRemindersRepository reminders) {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    return AppScope(
      auth: FakeAuthRepository(),
      profiles: FakeProfileRepository(),
      expenses: InMemoryExpenseRepository(),
      moments: InMemoryMomentRepository(),
      workouts: InMemoryWorkoutRepository(),
      workoutPlans: InMemoryWorkoutPlanRepository(),
      workoutSessions: InMemoryWorkoutSessionRepository(),
      diet: diet,
      ai: FakeAiRepository(),
      reminders: reminders,
      notifications: const NoOpNotificationScheduler(),
      child: const MaterialApp(home: RemindersPage()),
    );
  }

  testWidgets('shows an empty state when there are no reminders', (
    tester,
  ) async {
    await tester.pumpWidget(host(InMemoryRemindersRepository()));
    await tester.pump();
    expect(find.text('No reminders yet'), findsOneWidget);
  });

  testWidgets('renders a reminder row with its name', (tester) async {
    final repo = InMemoryRemindersRepository(
      initial: const [
        Reminder(
          id: 'r1',
          label: 'Breakfast',
          kind: ReminderKind.meal,
          hour: 8,
          minute: 0,
        ),
      ],
    );
    addTearDown(repo.dispose);
    await tester.pumpWidget(host(repo));
    await tester.pump();
    expect(find.text('Breakfast'), findsOneWidget);
  });

  testWidgets('toggling the switch persists the disabled state', (
    tester,
  ) async {
    final repo = InMemoryRemindersRepository(
      initial: const [
        Reminder(
          id: 'r1',
          label: 'Breakfast',
          kind: ReminderKind.meal,
          hour: 8,
          minute: 0,
        ),
      ],
    );
    addTearDown(repo.dispose);
    await tester.pumpWidget(host(repo));
    await tester.pump();

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump();

    expect(repo.current.single.enabled, isFalse);
  });

  testWidgets('the add action opens the new-reminder sheet', (tester) async {
    await tester.pumpWidget(host(InMemoryRemindersRepository()));
    await tester.pump();

    // The empty state's "Add reminder" button.
    await tester.tap(find.text('Add reminder'));
    await tester.pumpAndSettle();

    expect(find.text('New reminder'), findsOneWidget);
  });

  testWidgets('the time field opens a Cupertino wheel picker', (tester) async {
    await tester.pumpWidget(host(InMemoryRemindersRepository()));
    await tester.pump();
    await tester.tap(find.text('Add reminder'));
    await tester.pumpAndSettle();

    // Default new-reminder time is 8:00 AM. The notification preview also shows
    // that time, so target the time *field* (last in build order — the preview
    // sits above it) to open the wheel.
    await tester.tap(find.text('8:00 AM').last);
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoDatePicker), findsOneWidget);
  });

  testWidgets('the header close button dismisses the sheet', (tester) async {
    await tester.pumpWidget(host(InMemoryRemindersRepository()));
    await tester.pump();
    await tester.tap(find.text('Add reminder'));
    await tester.pumpAndSettle();
    expect(find.text('New reminder'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.text('New reminder'), findsNothing);
  });

  testWidgets('the notification preview reflects the typed name', (tester) async {
    await tester.pumpWidget(host(InMemoryRemindersRepository()));
    await tester.pump();
    await tester.tap(find.text('Add reminder'));
    await tester.pumpAndSettle();

    // The preview card names the app; before typing it uses the kind fallback.
    expect(find.text('ZIVO'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Leg day');
    await tester.pump();

    // The name field shows the raw text; the preview shows the same title
    // wrapped in directional isolates (user data), so it needs the bidi finder.
    expect(find.text('Leg day'), findsOneWidget);
    expect(findTextIgnoringBidi('Leg day'), findsOneWidget);
  });

  testWidgets('a synced workout reminder shows its linked day', (tester) async {
    final repo = InMemoryRemindersRepository(
      initial: const [
        Reminder(
          id: 'r1',
          label: 'Train',
          kind: ReminderKind.workout,
          hour: 18,
          minute: 0,
          sync: WorkoutSync(cachedDayLabel: 'Push Day'),
        ),
      ],
    );
    addTearDown(repo.dispose);
    await tester.pumpWidget(host(repo));
    await tester.pump();

    expect(findTextIgnoringBidi('Push Day'), findsOneWidget);
  });
}
