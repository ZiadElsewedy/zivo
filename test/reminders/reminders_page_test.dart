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
import 'package:zivo/features/reminders/presentation/pages/reminders_page.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

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
}
