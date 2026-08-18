import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/presentation/pages/ask_page.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

Widget _host(FakeAiRepository ai) => AppScope(
  auth: FakeAuthRepository(),
  profiles: FakeProfileRepository(),
  expenses: InMemoryExpenseRepository(),
  tasks: InMemoryTaskRepository(),
  schedule: InMemoryScheduleRepository(),
  notes: InMemoryNoteRepository(),
  moments: InMemoryMomentRepository(),
  workouts: InMemoryWorkoutRepository(),
  workoutPlans: InMemoryWorkoutPlanRepository(),
  workoutSessions: InMemoryWorkoutSessionRepository(),
  university: InMemoryUniversityRepository(),
  diet: InMemoryDietRepository(),
  ai: ai,
  child: MaterialApp(home: const AskPage()),
);

void main() {
  testWidgets('"add task ..." renders a confirmation card, not a plain reply', (
    tester,
  ) async {
    final ai = FakeAiRepository();
    addTearDown(ai.dispose);
    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'add task Submit report');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    // The card shows, with its Confirm/Cancel affordances — and no canned reply.
    expect(find.text('New task'), findsOneWidget);
    expect(find.text('Submit report'), findsOneWidget);
    expect(find.byKey(const Key('proposal-confirm')), findsOneWidget);
    expect(find.byKey(const Key('proposal-cancel')), findsOneWidget);
    expect(find.text(kFakeAiReply), findsNothing);
  });

  testWidgets('Confirm collapses the card and appends the result line', (
    tester,
  ) async {
    final ai = FakeAiRepository();
    addTearDown(ai.dispose);
    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'add task Submit report');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('proposal-confirm')));
    await tester.pumpAndSettle();

    // Card collapsed (buttons gone), and the durable result line appended.
    expect(find.byKey(const Key('proposal-confirm')), findsNothing);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Added to Tasks · Submit report'), findsOneWidget);
  });

  testWidgets('Cancel collapses the card and writes nothing', (tester) async {
    final ai = FakeAiRepository();
    addTearDown(ai.dispose);
    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'add task Temp');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('proposal-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('proposal-cancel')), findsNothing);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text("Okay — I won't add that."), findsOneWidget);
  });

  testWidgets('an expense proposal renders the money card', (tester) async {
    final ai = FakeAiRepository();
    addTearDown(ai.dispose);
    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    ai.proposeAction(
      kind: 'create_expense',
      summary: 'Log 12.00 EGP on coffee',
      fields: {'amount': '12.00', 'currency': 'EGP', 'category': 'coffee'},
    );
    await tester.pumpAndSettle();

    expect(find.text('New expense'), findsOneWidget);
    expect(find.text('12.00 EGP'), findsOneWidget);
    expect(find.text('coffee'), findsOneWidget);
  });
}
