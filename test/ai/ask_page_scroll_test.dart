import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/domain/ai_conversation.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_repository.dart';
import 'package:zivo/features/workout/domain/workout_import_input.dart';
import 'package:zivo/features/ai/domain/ai_response_style.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';
import 'package:zivo/features/ai/domain/ai_turn_event.dart';
import 'package:zivo/features/ai/presentation/pages/ask_page.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_import_input.dart';
import 'package:zivo/features/diet/domain/diet_import_outcome.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/domain/plan_preferences.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/domain/workout_import_outcome.dart';
import 'package:zivo/features/ai/domain/stt_outcome.dart';
import 'package:zivo/features/ai/domain/import_progress.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A hand-driven repository with a long seeded thread — enough messages that
/// the list genuinely overflows and must scroll.
class _LongThreadAi implements AiRepository {
  final StreamController<List<AiMessage>> _controller =
      StreamController<List<AiMessage>>.broadcast();

  void emit(List<AiMessage> messages) {
    _controller.add(List.unmodifiable(messages));
  }

  @override
  Stream<List<AiMessage>> watchMessages(String conversationId) async* {
    yield const [];
    yield* _controller.stream;
  }

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
    String responseStyle = kDefaultResponseStyle,
    String? clientTurnId,
  }) async {
    onEvent?.call(const AiPhaseEvent(AiPhase.done));
  }

  @override
  Future<String> createConversation({String? title}) async => 'conv-1';

  // -- Unused ----------------------------------------------------------------
  @override
  Future<AiConversation?> latestConversation() async => AiConversation(
    id: 'conv-1',
    title: 'Ask',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  @override
  Future<String> getResponseStyle() async => kDefaultResponseStyle;

  @override
  Stream<List<AiConversation>> watchConversations() =>
      const Stream<List<AiConversation>>.empty();

  @override
  Future<void> renameConversation(String id, String title) async {}

  @override
  Future<void> setResponseStyle(String style) async {}

  @override
  Future<void> deleteConversation(String id) async {}

  @override
  Future<String> ensureConversation() async => 'conv-1';

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
  Future<WorkoutImportOutcome> importWorkoutPlan(
    WorkoutImportInput input, {
    void Function(ImportProgress progress)? onProgress,
  }) async => const WorkoutImportRejected('unused');

  @override
  Future<DietImportOutcome> importDietPlan(
    DietImportInput input, {
    void Function(ImportProgress progress)? onProgress,
  }) async =>
      DietImportRejected('unused');

  @override
  Future<DietImportOutcome> generateDietPlan({
    required PlanPreferences preferences,
    NutritionTargets? targets,
  }) => throw UnimplementedError();

  @override
  Future<SttOutcome> transcribe({
    required Uint8List audioBytes,
    required String mimeType,
    String? languageHint,
  }) async => const SttTranscribed(text: '');
}

AiMessage _msg(int i) => AiMessage(
  id: 'm$i',
  role: i.isEven ? AiRole.user : AiRole.assistant,
  content: 'message $i — a line of chat content to fill the thread',
  createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
);

Widget _host(AiRepository ai) => AppScope(
  auth: FakeAuthRepository(),
  profiles: FakeProfileRepository(),
  expenses: InMemoryExpenseRepository(),
  moments: InMemoryMomentRepository(),
  workouts: InMemoryWorkoutRepository(),
  workoutPlans: InMemoryWorkoutPlanRepository(),
  workoutSessions: InMemoryWorkoutSessionRepository(),
  diet: InMemoryDietRepository(),
  ai: ai,
  child: const MaterialApp(home: AskPage()),
);

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

void main() {
  testWidgets('the user can scroll up freely — incoming turns never yank '
      'the list back down once they scrolled away', (tester) async {
    final ai = _LongThreadAi();
    await tester.pumpWidget(_host(ai));
    await tester.pump();
    ai.emit([for (var i = 0; i < 40; i++) _msg(i)]);
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, greaterThan(0));

    // Drag DOWN (away from the newest message): the thumb owns the list now.
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    final awayFromBottom = _position(tester).pixels;
    expect(awayFromBottom, lessThan(_position(tester).maxScrollExtent - 200));

    // A new turn lands while the user is up here reading history.
    ai.emit([for (var i = 0; i < 40; i++) _msg(i), _msg(40), _msg(41)]);
    await tester.pumpAndSettle();

    expect(
      _position(tester).pixels,
      awayFromBottom,
      reason:
          'Auto-follow must stand down once the user scrolls away; new '
          'content may never drag them back down mid-read.',
    );
  });

  testWidgets('following resumes when the user returns near the bottom', (
    tester,
  ) async {
    final ai = _LongThreadAi();
    await tester.pumpWidget(_host(ai));
    await tester.pump();
    ai.emit([for (var i = 0; i < 40; i++) _msg(i)]);
    await tester.pumpAndSettle();

    // Leave the bottom…
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    // …and come back.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, _position(tester).maxScrollExtent);

    // New content while following again: pinned instantly.
    ai.emit([for (var i = 0; i < 42; i++) _msg(i), _msg(42)]);
    await tester.pumpAndSettle();
    expect(
      _position(tester).pixels,
      _position(tester).maxScrollExtent,
      reason:
          'While the user is at the bottom, fresh messages keep the '
          'newest bubble glued to the composer.',
    );
  });
}
