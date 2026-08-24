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
    'a brand-new app has no conversations until the first message sends '
    '(lazy new chat)',
    (tester) async {
      final ai = FakeAiRepository();
      addTearDown(ai.dispose);

      await tester.pumpWidget(_host(ai));
      await tester.pumpAndSettle();

      expect(find.text("Hey, I'm ZIVO."), findsOneWidget);
      expect(await ai.watchConversations().first, isEmpty);

      await tester.enterText(find.byType(TextField), 'Hello there');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      final conversations = await ai.watchConversations().first;
      expect(conversations, hasLength(1));
      expect(conversations.single.title, 'Hello there');
    },
  );

  testWidgets(
    'New chat is unsaved until a message is sent in it — tapping it alone '
    "doesn't create a conversation",
    (tester) async {
      final ai = FakeAiRepository();
      addTearDown(ai.dispose);
      final existingId = await ai.createConversation();
      await ai.send(conversationId: existingId, text: 'hi');

      await tester.pumpWidget(_host(ai));
      await tester.pumpAndSettle();

      // Opens into the one existing conversation.
      expect(find.text('hi'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_comment_outlined));
      await tester.pumpAndSettle();

      expect(find.text("Hey, I'm ZIVO."), findsOneWidget);
      expect(await ai.watchConversations().first, hasLength(1));

      await tester.enterText(
        find.byType(TextField),
        'second chat message',
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(await ai.watchConversations().first, hasLength(2));
    },
  );

  testWidgets(
    'deleting the active chat from the sessions sheet switches to the '
    'unsaved new-chat state when none remain',
    (tester) async {
      final ai = FakeAiRepository();
      addTearDown(ai.dispose);
      final id = await ai.createConversation();
      await ai.send(conversationId: id, text: 'only chat');

      await tester.pumpWidget(_host(ai));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.history_rounded));
      await tester.pumpAndSettle();

      await tester.drag(find.byKey(ValueKey(id)), const Offset(-1000, 0));
      await tester.pumpAndSettle();

      expect(find.text('Delete this chat?'), findsOneWidget);
      await tester.tap(find.text('Delete chat'));
      await tester.pumpAndSettle();

      // The sheet stays open, now showing the empty list.
      expect(find.text('No chats yet.'), findsOneWidget);

      // Dismiss the sheet (tap the scrim).
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text("Hey, I'm ZIVO."), findsOneWidget);
      expect(await ai.watchConversations().first, isEmpty);
    },
  );
}
