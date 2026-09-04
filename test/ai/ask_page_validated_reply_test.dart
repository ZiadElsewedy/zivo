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
import 'package:zivo/features/ai/domain/stt_outcome.dart';
import 'package:zivo/features/ai/presentation/pages/ask_page.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/diet/domain/diet_import_input.dart';
import 'package:zivo/features/diet/domain/diet_import_outcome.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/domain/plan_preferences.dart';
import 'package:zivo/features/workout/domain/workout_import_outcome.dart';
import 'package:zivo/features/ai/domain/import_progress.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A turn whose streamed draft is REJECTED by the gateway's advice validator:
/// the model's text reaches the screen, the server replaces it with the
/// coaching engine's deterministic sentence, and the `done` event says so.
///
/// The draft must not survive that. A rejected reply left on screen is the
/// exact failure the whole validator exists to prevent, arriving one layer
/// later — the app quoting a figure it has already established was invented.
class _ValidatedAwayAi implements AiRepository {
  final List<AiMessage> _messages = [];
  final StreamController<List<AiMessage>> _controller =
      StreamController<List<AiMessage>>.broadcast();

  final Completer<void> releaseDeltas = Completer<void>();
  final Completer<void> releaseDone = Completer<void>();

  /// Held so the test can look at the screen in the window that matters: the
  /// validator's verdict has arrived, the durable message has not.
  final Completer<void> releaseDurable = Completer<void>();

  @override
  Future<String> ensureConversation() async => 'c';

  @override
  Future<String> createConversation({String? title}) async => 'c2';

  @override
  Future<void> renameConversation(String id, String title) async {}

  @override
  Future<void> deleteConversation(String id) async {}

  @override
  Future<String> getResponseStyle() async => kDefaultResponseStyle;

  @override
  Future<void> setResponseStyle(String style) async {}

  @override
  Stream<List<AiConversation>> watchConversations() => Stream.value(const []);

  @override
  Future<AiConversation?> latestConversation() async => null;

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
    String responseStyle = kDefaultResponseStyle,
    String? clientTurnId,
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

    // A figure that traces to nothing in the diet state — the contradiction
    // the Phase 7 validator catches.
    onEvent?.call(const AiDeltaEvent("You've had about "));
    onEvent?.call(const AiDeltaEvent('1,900 kcal today.'));
    await releaseDone.future;
    onEvent?.call(const AiPhaseEvent(AiPhase.done, replaced: true));

    // The durable write lands afterwards — as it does in production, where
    // Firestore's snapshot always trails the turn's own done event.
    await releaseDurable.future;

    // What actually gets persisted: the finding's own deterministic text.
    _messages.add(
      AiMessage(
        id: 'a',
        role: AiRole.assistant,
        content:
            '310 of 2200 kcal so far (from the meals you ticked, not '
            'weighed).',
        createdAt: DateTime.now(),
      ),
    );
    _controller.add(List.unmodifiable(_messages));
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
  Future<WorkoutImportOutcome> importWorkoutPlan(
    WorkoutImportInput input, {
    void Function(ImportProgress progress)? onProgress,
  }) => throw UnimplementedError('not exercised by this test');

  @override
  Future<DietImportOutcome> importDietPlan(
    DietImportInput input, {
    void Function(ImportProgress progress)? onProgress,
  }) =>
      throw UnimplementedError('not exercised by this test');

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
  }) => throw UnimplementedError('not exercised by this test');

  void dispose() => _controller.close();
}

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

void main() {
  testWidgets('a reply the validator threw away leaves the screen — the '
      'deterministic text replaces it, not sits under it', (tester) async {
    final ai = _ValidatedAwayAi();
    addTearDown(ai.dispose);

    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'how am I doing?');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pump();
    await tester.pump();

    // The model's draft streams in, invented figure and all.
    ai.releaseDeltas.complete();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.textContaining('1,900'), findsOneWidget);

    // The gateway rejects it. The durable message hasn't landed yet — and
    // the draft is already gone, rather than lingering on screen until
    // Firestore catches up.
    ai.releaseDone.complete();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('1,900'), findsNothing);

    // Then the validated text arrives, and it is the only reply on screen.
    ai.releaseDurable.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('1,900'), findsNothing);
    expect(find.textContaining('310 of 2200 kcal so far'), findsOneWidget);
  });
}
