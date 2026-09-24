import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
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

/// Deletes the way production does: `aiDeleteConversation` is a Cloud
/// Function round-trip, and the conversations stream keeps listing the chat
/// until the server has actually removed it.
class _SlowDeleteAi extends FakeAiRepository {
  Completer<void>? pending;

  @override
  Future<void> deleteConversation(String id) async {
    final gate = pending = Completer<void>();
    await gate.future;
    await super.deleteConversation(id);
  }
}

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

Future<(String, String)> _twoChats(_SlowDeleteAi ai) async {
  final keep = await ai.createConversation();
  await ai.send(conversationId: keep, text: 'keep me');
  final doomed = await ai.createConversation();
  await ai.send(conversationId: doomed, text: 'delete me');
  return (keep, doomed);
}

Future<void> _swipeAndConfirm(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(const Key('header-history')));
  await tester.pumpAndSettle();
  await tester.drag(find.byKey(ValueKey(id)), const Offset(-1000, 0));
  await tester.pumpAndSettle();
  expect(find.text('Delete this chat?'), findsOneWidget);
  await tester.tap(find.text('Delete chat'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a dismissed chat stops being built at once, even while the backend '
    'delete is in flight and the stream still lists it',
    (tester) async {
      final ai = _SlowDeleteAi();
      addTearDown(ai.dispose);
      final (keep, doomed) = await _twoChats(ai);

      await tester.pumpWidget(_host(ai));
      await tester.pumpAndSettle();
      await _swipeAndConfirm(tester, doomed);

      // The delete hasn't landed — the stream still has the chat.
      expect(ai.pending, isNotNull);
      expect(ai.pending!.isCompleted, isFalse);
      expect(
        (await ai.watchConversations().first).map((c) => c.id),
        contains(doomed),
      );

      // Force the stream to re-emit (a new chat ticks the list) — the
      // rebuild that used to rebuild the dismissed Dismissible.
      await ai.createConversation();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(ValueKey(doomed)), findsNothing);
      expect(find.byKey(ValueKey(keep)), findsOneWidget);

      ai.pending!.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(ValueKey(doomed)), findsNothing);
      expect(
        (await ai.watchConversations().first).map((c) => c.id),
        isNot(contains(doomed)),
      );
    },
  );

  testWidgets(
    'a failed delete puts the chat back in the list and says so',
    (tester) async {
      final ai = _SlowDeleteAi();
      addTearDown(ai.dispose);
      final (_, doomed) = await _twoChats(ai);

      await tester.pumpWidget(_host(ai));
      await tester.pumpAndSettle();
      await _swipeAndConfirm(tester, doomed);
      expect(find.byKey(ValueKey(doomed)), findsNothing);

      ai.pending!.completeError(Exception('network'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Back, as a fresh row that can be swiped again.
      expect(find.byKey(ValueKey(doomed)), findsOneWidget);
      expect(
        find.text("Couldn't delete that chat. It's back in your list."),
        findsOneWidget,
      );
      expect(
        (await ai.watchConversations().first).map((c) => c.id),
        contains(doomed),
      );
      // Let the toast finish its timer.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );
}
