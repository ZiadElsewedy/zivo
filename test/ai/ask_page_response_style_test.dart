import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/core/theme/app_icons.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_conversation.dart';
import 'package:zivo/features/ai/domain/ai_choice_request.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_turn_usage.dart';
import 'package:zivo/features/ai/domain/ai_usage_summary.dart';
import 'package:zivo/features/workout/domain/workout_import_input.dart';
import 'package:zivo/features/ai/domain/ai_response_style.dart';
import 'package:zivo/features/ai/domain/ai_model_selection.dart';
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

/// Wraps [FakeAiRepository] to record the `responseStyle` AskPage forwards
/// on every [send] call, so the test can assert on it directly.
class _RecordingAi implements AiRepository {
  _RecordingAi(this._inner);

  final FakeAiRepository _inner;
  final List<String> sentStyles = [];
  final List<String> sentModels = [];

  @override
  Future<String> ensureConversation() => _inner.ensureConversation();

  @override
  Future<String> createConversation({String? title}) =>
      _inner.createConversation();

  @override
  Future<void> renameConversation(String id, String title) =>
      _inner.renameConversation(id, title);

  @override
  Future<void> deleteConversation(String id) => _inner.deleteConversation(id);

  @override
  Stream<List<AiConversation>> watchConversations() =>
      _inner.watchConversations();

  @override
  Future<AiConversation?> latestConversation() => _inner.latestConversation();

  @override
  Stream<List<AiMessage>> watchMessages(String conversationId) =>
      _inner.watchMessages(conversationId);

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
    String responseStyle = kDefaultResponseStyle,
    String modelSelection = kDefaultAiModelSelection,
    String? clientTurnId,
    AiChoiceSelection? choice,
  }) {
    sentStyles.add(responseStyle);
    sentModels.add(modelSelection);
    return _inner.send(
      conversationId: conversationId,
      text: text,
      onEvent: onEvent,
      responseStyle: responseStyle,
      modelSelection: modelSelection,
    );
  }

  @override
  Future<void> confirmAction({
    required String conversationId,
    required String actionId,
  }) =>
      _inner.confirmAction(conversationId: conversationId, actionId: actionId);

  @override
  Future<void> cancelAction({
    required String conversationId,
    required String actionId,
  }) => _inner.cancelAction(conversationId: conversationId, actionId: actionId);

  @override
  Future<WorkoutImportOutcome> importWorkoutPlan(
    WorkoutImportInput input, {
    ImportCancellation? cancellation,
  }) => _inner.importWorkoutPlan(input, cancellation: cancellation);

  @override
  Future<DietImportOutcome> importDietPlan(
    DietImportInput input, {
    ImportCancellation? cancellation,
  }) =>
      _inner.importDietPlan(input);

  @override
  Future<DietImportOutcome> generateDietPlan({
    required PlanPreferences preferences,
    NutritionTargets? targets,
  }) => _inner.generateDietPlan(preferences: preferences, targets: targets);

  @override
  Future<SttOutcome> transcribe({
    required Uint8List audioBytes,
    required String mimeType,
    String? languageHint,
  }) => _inner.transcribe(
    audioBytes: audioBytes,
    mimeType: mimeType,
    languageHint: languageHint,
  );

  @override
  Future<String> getResponseStyle() => _inner.getResponseStyle();

  @override
  Future<void> setResponseStyle(String style) => _inner.setResponseStyle(style);
  @override
  Future<String> getModelSelection() => _inner.getModelSelection();

  @override
  Future<List<AiProviderUsage>> usageByProvider() async => const [];

  @override
  Future<List<AiUsageRecord>> usageRecords({int limit = 1000}) async =>
      const [];
  @override
  Future<AiTurnUsage?> usageForTurn(String clientTurnId) async => null;

  @override
  Future<void> setModelSelection(String selection) =>
      _inner.setModelSelection(selection);
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
  child: MaterialApp(home: const AskPage()),
);

void main() {
  testWidgets('there is no Ask settings page: the header opens the model '
      'sheet, and a model picked there is forwarded on the next send', (
    tester,
  ) async {
    final inner = FakeAiRepository();
    addTearDown(inner.dispose);
    final ai = _RecordingAi(inner);

    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('header-model')));
    await tester.pumpAndSettle();

    // A sheet over Ask with exactly the two models; Claude Sonnet is the
    // default and the only one checked AND badged.
    expect(find.byType(AskPage), findsOneWidget);
    expect(find.byKey(const Key('sheet-model-claude-sonnet')), findsOneWidget);
    expect(find.byKey(const Key('sheet-model-gemini-flash')), findsOneWidget);
    expect(find.text('Ask settings'), findsNothing);
    expect(find.byKey(const Key('model-active-badge')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('sheet-model-claude-sonnet')),
        matching: find.byKey(const Key('model-active-badge')),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('sheet-model-gemini-flash')));
    await tester.pumpAndSettle();
    expect(await inner.getModelSelection(), 'gemini-flash');
    // The sheet closed itself.
    expect(find.byKey(const Key('sheet-model-gemini-flash')), findsNothing);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pumpAndSettle();

    expect(ai.sentModels, ['gemini-flash']);

    // Reopening shows Gemini as the one active model now.
    await tester.tap(find.byKey(const Key('header-model')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('model-active-badge')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('sheet-model-gemini-flash')),
        matching: find.byIcon(AppIcons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a reply style changed in Settings (outside Ask) is the one '
      'the next send forwards', (tester) async {
    final inner = FakeAiRepository();
    addTearDown(inner.dispose);
    final ai = _RecordingAi(inner);

    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    // Settings → AI → Reply style writes the shared setting while Ask is
    // already open.
    await inner.setResponseStyle('concise');

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pumpAndSettle();

    expect(ai.sentStyles, ['concise']);
    expect(ai.sentModels, ['claude-sonnet'],
        reason: 'model untouched, still the default');
  });
}
