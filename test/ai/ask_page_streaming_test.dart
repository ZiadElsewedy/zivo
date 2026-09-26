import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/domain/ai_conversation.dart';
import 'package:zivo/features/ai/domain/ai_choice_request.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_turn_usage.dart';
import 'package:zivo/features/ai/domain/ai_usage_summary.dart';
import 'package:zivo/features/workout/domain/workout_import_input.dart';
import 'package:zivo/features/ai/domain/ai_response_style.dart';
import 'package:zivo/features/ai/domain/ai_model_selection.dart';
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
import 'package:zivo/features/ai/domain/import_cancellation.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A repository whose turn is driven by gates, so the test can hold the UI in
/// each streaming stage: emit the `working` phase → stream deltas → land the
/// durable reply. Proves the rail is authoritative (server-labelled) and that
/// live text renders before the durable message arrives.
class _StreamingAi implements AiRepository {
  _StreamingAi({
    this.deltas = const ['Hello ', 'world'],
    this.beforeDeltas = const [],
    AiMessage Function(String? turnId)? reply,
  }) : reply =
           reply ??
           ((turnId) => AiMessage(
             id: 'a',
             role: AiRole.assistant,
             content: 'Hello world',
             createdAt: DateTime.now(),
           ));

  /// The reply text as it streams, chunk by chunk.
  final List<String> deltas;

  /// Events emitted while the turn works, before any text streams.
  final List<AiTurnEvent> beforeDeltas;

  /// The saved reply that lands when the turn is done.
  final AiMessage Function(String? turnId) reply;

  final List<AiMessage> _messages = [];
  final StreamController<List<AiMessage>> _controller =
      StreamController<List<AiMessage>>.broadcast();

  final Completer<void> releaseDeltas = Completer<void>();
  final Completer<void> releaseDone = Completer<void>();

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
  Future<String> getModelSelection() async => kDefaultAiModelSelection;

  @override
  Future<List<AiProviderUsage>> usageByProvider() async => const [];

  @override
  Future<List<AiUsageRecord>> usageRecords({int limit = 1000}) async =>
      const [];
  @override
  Future<AiTurnUsage?> usageForTurn(String clientTurnId) async => null;

  @override
  Future<void> setModelSelection(String selection) async {}

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
    String modelSelection = kDefaultAiModelSelection,
    String? clientTurnId,
    AiChoiceSelection? choice,
    String? entryPoint,
  }) async {
    _messages.add(
      AiMessage(
        id: 'u',
        role: AiRole.user,
        content: text,
        createdAt: DateTime.now(),
        clientTurnId: clientTurnId,
      ),
    );
    _controller.add(List.unmodifiable(_messages));

    onEvent?.call(const AiPhaseEvent(AiPhase.understanding));
    onEvent?.call(const AiPhaseEvent(AiPhase.working));
    beforeDeltas.forEach(onEvent ?? (_) {});
    await releaseDeltas.future;

    for (final d in deltas) {
      onEvent?.call(AiDeltaEvent(d));
    }
    await releaseDone.future;

    _messages.add(reply(clientTurnId));
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
  Future<WorkoutImportOutcome> importWorkoutPlan(
    WorkoutImportInput input, {
    ImportCancellation? cancellation,
  }) => throw UnimplementedError('not exercised by this test');

  @override
  Future<DietImportOutcome> importDietPlan(
    DietImportInput input, {
    ImportCancellation? cancellation,
  }) => throw UnimplementedError('not exercised by this test');

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
  testWidgets('the rail shows the authoritative phase, then live text streams, '
      'then the durable reply lands once', (tester) async {
    final ai = _StreamingAi();
    addTearDown(ai.dispose);

    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pump();
    await tester.pump();

    // Authoritative phase from the gateway drives the rail (not a guess).
    expect(find.text('Thinking…'), findsOneWidget);
    expect(find.text('Hello world'), findsNothing);

    // Deltas stream into a provisional bubble before the durable doc exists.
    // Deltas stream into a provisional bubble before the durable doc exists
    // — the text rides a paced, per-frame reveal (never an instant dump), so
    // run a handful of frames and match the growing rich text.
    ai.releaseDeltas.complete();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Thinking…'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().startsWith('Hello world'),
      ),
      findsOneWidget,
    );

    // Durable message lands; the provisional is dropped — exactly one bubble,
    // and it did not re-type (it already streamed live).
    ai.releaseDone.complete();
    await tester.pumpAndSettle();
    expect(find.text('Hello world'), findsOneWidget);
    expect(find.text('Thinking…'), findsNothing);
  });

  testWidgets('while ZIVO works the trail names a human state — never a tool '
      '— then settles into a quiet summary that unfolds on tap', (
    tester,
  ) async {
    final ai = _StreamingAi(
      beforeDeltas: const [AiStepEvent('get_diet', AiStepStatus.running)],
      reply: (turnId) => AiMessage(
        id: 'a',
        role: AiRole.assistant,
        content: 'Hello world',
        createdAt: DateTime.now(),
        clientTurnId: turnId,
        activity: const [AiActivityStep('get_diet', AiStepStatus.ok)],
      ),
    );
    addTearDown(ai.dispose);
    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'what is for breakfast?');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Reading your meal plan…'), findsOneWidget);
    expect(find.textContaining('get_diet'), findsNothing);
    expect(find.textContaining('Grab'), findsNothing);

    ai.releaseDeltas.complete();
    ai.releaseDone.complete();
    await tester.pumpAndSettle();

    // Settled: one quiet line of what it did, the words below it.
    expect(find.text('Reading your meal plan…'), findsNothing);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Hello world'), findsOneWidget);
    await tester.tap(find.text('Read'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Read your meal plan'), findsOneWidget);
  });

  testWidgets('a question\'s saved copy types ON from the streamed lead-in — '
      'the words on screen never shrink or snap', (tester) async {
    const lead = 'Your breakfast has 3 eggs, about 234 kcal.';
    const question = 'Which one would you prefer?';
    final ai = _StreamingAi(
      deltas: const ['Your breakfast has 3 eggs, ', 'about 234 kcal.'],
      reply: (turnId) => AiMessage(
        id: 'q',
        role: AiRole.assistant,
        content: question,
        preface: lead,
        createdAt: DateTime.now(),
        clientTurnId: turnId,
        choiceRequest: const AiChoiceRequest(
          requestId: 'req-1',
          prompt: question,
          options: [
            AiChoiceOption(value: 'a', label: 'Greek yogurt'),
            AiChoiceOption(value: 'b', label: 'Cottage cheese'),
          ],
        ),
      ),
    );
    addTearDown(ai.dispose);
    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), "I don't want eggs");
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pump();
    ai.releaseDeltas.complete();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    String shown() => tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .firstWhere((t) => t.startsWith('Your breakfast'), orElse: () => '');
    expect(shown(), startsWith(lead));

    ai.releaseDone.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    // Mid-handoff: still at least the lead-in, not yet the whole question.
    expect(shown(), startsWith(lead));
    expect(shown().length, lessThan('$lead\n\n$question'.length));

    await tester.pumpAndSettle();
    expect(shown(), '$lead\n\n$question');
    // The answers wait by the composer.
    expect(find.byKey(const ValueKey('choice-option-a')), findsOneWidget);
  });
}
