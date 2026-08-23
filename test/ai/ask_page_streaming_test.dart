import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/domain/ai_conversation.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';
import 'package:zivo/features/ai/domain/ai_turn_event.dart';
import 'package:zivo/features/ai/domain/stt_outcome.dart';
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
import 'package:zivo/features/workout/domain/workout_import_outcome.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A repository whose turn is driven by gates, so the test can hold the UI in
/// each streaming stage: emit the `working` phase → stream deltas → land the
/// durable reply. Proves the rail is authoritative (server-labelled) and that
/// live text renders before the durable message arrives.
class _StreamingAi implements AiRepository {
  final List<AiMessage> _messages = [];
  final StreamController<List<AiMessage>> _controller =
      StreamController<List<AiMessage>>.broadcast();

  final Completer<void> releaseDeltas = Completer<void>();
  final Completer<void> releaseDone = Completer<void>();

  @override
  Future<String> ensureConversation() async => 'c';

  @override
  Future<String> createConversation() async => 'c2';

  @override
  Future<void> renameConversation(String id, String title) async {}

  @override
  Stream<List<AiConversation>> watchConversations() => Stream.value(const []);

  @override
  Stream<List<AiMessage>> watchMessages(String conversationId) async* {
    yield List.unmodifiable(_messages);
    yield* _controller.stream;
  }

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
  }) async {
    _messages.add(
      AiMessage(
        id: 'u',
        role: AiRole.user,
        content: text,
        createdAt: DateTime.now(),
      ),
    );
    _controller.add(List.unmodifiable(_messages));

    onEvent?.call(const AiPhaseEvent(AiPhase.understanding));
    onEvent?.call(const AiPhaseEvent(AiPhase.working));
    await releaseDeltas.future;

    onEvent?.call(const AiDeltaEvent('Hello '));
    onEvent?.call(const AiDeltaEvent('world'));
    await releaseDone.future;

    _messages.add(
      AiMessage(
        id: 'a',
        role: AiRole.assistant,
        content: 'Hello world',
        createdAt: DateTime.now(),
      ),
    );
    _controller.add(List.unmodifiable(_messages));
    onEvent?.call(const AiPhaseEvent(AiPhase.done));
  }

  @override
  Future<void> confirmAction({
    required String conversationId,
    required String actionId,
  }) async {}

  @override
  Future<void> cancelAction({
    required String conversationId,
    required String actionId,
  }) async {}

  @override
  Future<WorkoutImportOutcome> importWorkoutPlan({
    required Uint8List pdfBytes,
  }) => throw UnimplementedError('not exercised by this test');

  @override
  Future<SttOutcome> transcribe({
    required Uint8List audioBytes,
    required String mimeType,
    String? languageHint,
  }) => throw UnimplementedError('not exercised by this test');

  void dispose() => _controller.close();
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
  testWidgets('the rail shows the authoritative phase, then live text streams, '
      'then the durable reply lands once', (tester) async {
    final ai = _StreamingAi();
    addTearDown(ai.dispose);

    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await tester.pump();

    // Authoritative phase from the gateway drives the rail (not a guess).
    expect(find.text('Working…'), findsOneWidget);
    expect(find.text('Hello world'), findsNothing);

    // Deltas stream into a provisional bubble before the durable doc exists.
    ai.releaseDeltas.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Working…'), findsNothing);
    expect(find.text('Hello world'), findsOneWidget);

    // Durable message lands; the provisional is dropped — exactly one bubble,
    // and it did not re-type (it already streamed live).
    ai.releaseDone.complete();
    await tester.pumpAndSettle();
    expect(find.text('Hello world'), findsOneWidget);
    expect(find.text('Working…'), findsNothing);
  });
}
