import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/presentation/pages/ask_page.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

Widget _host(FakeAiRepository ai) => AppScope(
  auth: FakeAuthRepository(),
  profiles: FakeProfileRepository(),
  expenses: InMemoryExpenseRepository(),
  moments: InMemoryMomentRepository(),
  workouts: InMemoryWorkoutRepository(),
  workoutPlans: InMemoryWorkoutPlanRepository(),
  workoutSessions: InMemoryWorkoutSessionRepository(),
  diet: InMemoryDietRepository(),
  ai: ai,
  child: MaterialApp(home: const AskPage()),
);

void main() {
  testWidgets(
    '"add expense ..." renders a confirmation card, not a plain reply',
    (tester) async {
      final ai = FakeAiRepository();
      addTearDown(ai.dispose);
      await tester.pumpWidget(_host(ai));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'add expense 12 coffee');
      await tester.pump();
      await tester.tap(find.byKey(const Key('composer-send')));
      await tester.pumpAndSettle();

      // The card shows, with its Confirm/Cancel affordances — and no canned reply.
      expect(find.text('New expense'), findsOneWidget);
      expect(find.text('12.00 EGP'), findsOneWidget);
      expect(find.byKey(const Key('proposal-confirm')), findsOneWidget);
      expect(find.byKey(const Key('proposal-cancel')), findsOneWidget);
      expect(find.text(kFakeAiReply), findsNothing);
    },
  );

  testWidgets('Confirm collapses the card and appends the result line', (
    tester,
  ) async {
    final ai = FakeAiRepository();
    addTearDown(ai.dispose);
    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'add expense 12 coffee');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('proposal-confirm')));
    await tester.pumpAndSettle();

    // Card collapsed (buttons gone), and the durable result line appended.
    expect(find.byKey(const Key('proposal-confirm')), findsNothing);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Logged expense · 12.00 EGP · coffee'), findsOneWidget);
  });

  testWidgets('Cancel collapses the card and writes nothing', (tester) async {
    final ai = FakeAiRepository();
    addTearDown(ai.dispose);
    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'add expense 5 other');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
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
    // A conversation must already exist for the AskPage to open into — a
    // brand-new app has no conversations at all, and `proposeAction`'s
    // default-conversation shortcut only applies to one created via
    // `ensureConversation`, not the lazy "New chat" state AskPage now starts
    // in (Phase A: conversations aren't persisted until a real message
    // sends).
    final conversationId = await ai.createConversation();
    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    ai.proposeAction(
      conversationId: conversationId,
      kind: 'create_expense',
      summary: 'Log 12.00 EGP on coffee',
      fields: {'amount': '12.00', 'currency': 'EGP', 'category': 'coffee'},
    );
    await tester.pumpAndSettle();

    expect(find.text('New expense'), findsOneWidget);
    expect(find.text('12.00 EGP'), findsOneWidget);
    expect(find.text('coffee'), findsOneWidget);
  });

  testWidgets('a meal proposal renders the diet card', (tester) async {
    final ai = FakeAiRepository();
    addTearDown(ai.dispose);
    final conversationId = await ai.createConversation();
    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    ai.proposeAction(
      conversationId: conversationId,
      kind: 'mark_meal_eaten',
      summary: 'Mark Lunch eaten',
      fields: {'meal': 'Lunch', 'state': 'eaten'},
    );
    await tester.pumpAndSettle();

    expect(find.text('Diet plan'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('eaten'), findsOneWidget);
  });

  testWidgets('a log_food proposal renders the food card with the amount', (
    tester,
  ) async {
    final ai = FakeAiRepository();
    addTearDown(ai.dispose);
    final conversationId = await ai.createConversation();
    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    // The server-computed shape: items carry name/quantity/unit/kcal, plus a
    // total. The card never shows a calorie the model invented — these come
    // from the tool payload.
    ai.proposeAction(
      conversationId: conversationId,
      kind: 'log_food',
      summary: 'Log Chicken breast (200 g) · 330 kcal',
      fields: {
        'items': [
          {'name': 'Chicken breast', 'quantity': 200, 'unit': 'g', 'kcal': 330},
        ],
        'totalKcal': 330,
        'count': 1,
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('Log food'), findsOneWidget);
    expect(find.text('Chicken breast'), findsOneWidget); // the headline
    expect(find.text('Chicken breast · 200 g'), findsOneWidget); // the chip
    expect(find.byKey(const Key('proposal-confirm')), findsOneWidget);
  });

  testWidgets('a multi-item log_food proposal shows each food and a total', (
    tester,
  ) async {
    final ai = FakeAiRepository();
    addTearDown(ai.dispose);
    final conversationId = await ai.createConversation();
    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    ai.proposeAction(
      conversationId: conversationId,
      kind: 'log_food',
      summary: 'Log 2 foods · 500 kcal',
      fields: {
        'items': [
          {'name': 'Egg', 'quantity': 2, 'unit': 'piece', 'kcal': 140},
          {'name': 'Rice', 'quantity': 150, 'unit': 'g', 'kcal': 360},
        ],
        'totalKcal': 500,
        'count': 2,
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('2 foods'), findsOneWidget); // the headline
    expect(find.text('Egg · 2 piece'), findsOneWidget);
    expect(find.text('Rice · 150 g'), findsOneWidget);
    expect(find.text('500 kcal'), findsOneWidget); // the total chip
  });

  testWidgets('Confirming a log_food proposal appends its result line', (
    tester,
  ) async {
    final ai = FakeAiRepository();
    addTearDown(ai.dispose);
    final conversationId = await ai.createConversation();
    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    ai.proposeAction(
      conversationId: conversationId,
      kind: 'log_food',
      summary: 'Log Chicken breast (200 g) · 330 kcal',
      fields: {
        'items': [
          {'name': 'Chicken breast', 'quantity': 200, 'unit': 'g', 'kcal': 330},
        ],
        'totalKcal': 330,
        'count': 1,
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('proposal-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('proposal-confirm')), findsNothing);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Logged 1 food · 330 kcal'), findsOneWidget);
  });
}
