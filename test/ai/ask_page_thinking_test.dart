import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_turn_event.dart';
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

/// Wraps [FakeAiRepository] but holds `send` open on [gate], so a test can
/// observe the in-flight "thinking" state before the reply lands.
class _GatedAi implements AiRepository {
  _GatedAi(this._inner);

  final FakeAiRepository _inner;
  final Completer<void> gate = Completer<void>();

  @override
  Future<String> ensureConversation() => _inner.ensureConversation();

  @override
  Stream<List<AiMessage>> watchMessages(String conversationId) =>
      _inner.watchMessages(conversationId);

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
  }) async {
    await gate.future;
    await _inner.send(
      conversationId: conversationId,
      text: text,
      onEvent: onEvent,
    );
  }

  @override
  Future<void> confirmAction({
    required String conversationId,
    required String actionId,
  }) => _inner.confirmAction(conversationId: conversationId, actionId: actionId);

  @override
  Future<void> cancelAction({
    required String conversationId,
    required String actionId,
  }) => _inner.cancelAction(conversationId: conversationId, actionId: actionId);
}

Widget _host(AiRepository ai) => AppScope(
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
  child: const MaterialApp(home: AskPage()),
);

void main() {
  testWidgets('the thinking rail shows while a turn is in flight and clears '
      'when the reply arrives', (tester) async {
    final inner = FakeAiRepository();
    addTearDown(inner.dispose);
    final ai = _GatedAi(inner);

    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'what is due this week?');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    // Let the send lifecycle mark the turn in flight (send is gated open).
    await tester.pump();
    await tester.pump();

    expect(find.text('Thinking…'), findsOneWidget);
    expect(find.text(kFakeAiReply), findsNothing);

    // Release the gated reply; the rail clears and the answer types in.
    ai.gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Thinking…'), findsNothing);
    expect(find.text(kFakeAiReply), findsOneWidget);
  });
}
