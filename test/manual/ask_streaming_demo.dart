// Manual demo entrypoint (not a test): runs the Ask page against a paced,
// Firebase-free fake so the Slice C streaming UX — authoritative phase rail
// and token-by-token reveal — is visible on a simulator.
//
//   flutter run -t test/manual/ask_streaming_demo.dart -d <simulator-udid>
//
// Every other repository is an in-memory / fake stand-in; nothing touches
// Firebase, so no config or sign-in is required.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_pending_action.dart';
import 'package:zivo/features/ai/domain/ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';
import 'package:zivo/features/ai/domain/ai_turn_event.dart';
import 'package:zivo/features/ai/domain/workout_import_result.dart';
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

/// Paces phases and deltas with real delays so the rail and typewriter are
/// actually observable (the production fake fires them in a single frame).
class DemoAi implements AiRepository {
  final List<AiMessage> _messages = [];
  final StreamController<List<AiMessage>> _controller =
      StreamController<List<AiMessage>>.broadcast();
  int _seq = 0;

  String _id() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  @override
  Future<String> ensureConversation() async => 'demo';

  @override
  Stream<List<AiMessage>> watchMessages(String conversationId) async* {
    yield List.unmodifiable(_messages);
    yield* _controller.stream;
  }

  void _emit() => _controller.add(List.unmodifiable(_messages));

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _messages.add(AiMessage(
      id: _id(),
      role: AiRole.user,
      content: trimmed,
      createdAt: DateTime.now(),
    ));
    _emit();

    onEvent?.call(const AiPhaseEvent(AiPhase.understanding));
    await Future<void>.delayed(const Duration(milliseconds: 650));

    if (trimmed.toLowerCase().startsWith('add task ')) {
      onEvent?.call(const AiPhaseEvent(AiPhase.preparingChange));
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final title = trimmed.substring('add task '.length).trim();
      _messages.add(AiMessage(
        id: _id(),
        role: AiRole.assistant,
        content: 'Add task "$title"',
        createdAt: DateTime.now(),
        pendingAction: AiPendingAction(
          actionId: _id(),
          kind: 'create_task',
          summary: 'Add task "$title"',
          fields: {'title': title, 'due': null, 'priority': 'Normal'},
          status: AiActionStatus.pending,
        ),
      ));
      _emit();
      onEvent?.call(const AiPhaseEvent(AiPhase.done));
      return;
    }

    onEvent?.call(const AiPhaseEvent(AiPhase.working));
    await Future<void>.delayed(const Duration(milliseconds: 800));

    const reply =
        'You have three things due this week: your Physics problem set on '
        'Wednesday, rent on Thursday, and the study group at 6pm Friday. '
        'Want me to nudge you the morning before rent is due?';

    // Stream word-by-word so the reveal reads like real composition.
    final words = reply.split(' ');
    for (var i = 0; i < words.length; i++) {
      final chunk = i == 0 ? words[i] : ' ${words[i]}';
      onEvent?.call(AiDeltaEvent(chunk));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    _messages.add(AiMessage(
      id: _id(),
      role: AiRole.assistant,
      content: reply,
      createdAt: DateTime.now(),
    ));
    _emit();
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
  Future<WorkoutImportResult> importWorkoutPlan({required Uint8List pdfBytes}) =>
      throw UnimplementedError('not exercised by this manual demo');
}

class _AskDemoRoot extends StatefulWidget {
  const _AskDemoRoot();

  @override
  State<_AskDemoRoot> createState() => _AskDemoRootState();
}

class _AskDemoRootState extends State<_AskDemoRoot> {
  final DemoAi _ai = DemoAi();

  @override
  Widget build(BuildContext context) {
    return AppScope(
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
      ai: _ai,
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: AskPage(),
      ),
    );
  }
}

void main() {
  runApp(const _AskDemoRoot());
}
