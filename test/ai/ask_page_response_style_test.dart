import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/core/theme/app_icons.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_conversation.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_response_style.dart';
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

/// Wraps [FakeAiRepository] to record the `responseStyle` AskPage forwards
/// on every [send] call, so the test can assert on it directly.
class _RecordingAi implements AiRepository {
  _RecordingAi(this._inner);

  final FakeAiRepository _inner;
  final List<String> sentStyles = [];

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
    String? clientTurnId,
  }) {
    sentStyles.add(responseStyle);
    return _inner.send(
      conversationId: conversationId,
      text: text,
      onEvent: onEvent,
      responseStyle: responseStyle,
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
  Future<WorkoutImportOutcome> importWorkoutPlan({
    required Uint8List fileBytes,
    required String mimeType,
  void Function(ImportProgress progress)? onProgress,
  }) => _inner.importWorkoutPlan(fileBytes: fileBytes, mimeType: mimeType);

  @override
  Future<DietImportOutcome> importDietPlan(
    DietImportInput input, {
    void Function(ImportProgress progress)? onProgress,
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
  testWidgets('defaults to Balanced, and a picked style persists and is '
      "forwarded on the next send", (tester) async {
    final inner = FakeAiRepository();
    addTearDown(inner.dispose);
    final ai = _RecordingAi(inner);

    await tester.pumpWidget(_host(ai));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('header-style')));
    await tester.pumpAndSettle();

    expect(find.text('Concise'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    expect(find.text('Detailed'), findsOneWidget);
    // 'Balanced' is checked by default.
    expect(
      find.descendant(
        of: find.widgetWithText(Row, 'Balanced'),
        matching: find.byIcon(AppIcons.check),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Concise'));
    await tester.pumpAndSettle();

    expect(await inner.getResponseStyle(), 'concise');

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pumpAndSettle();

    expect(ai.sentStyles, ['concise']);

    // Reopening the menu now shows Concise checked instead.
    await tester.tap(find.byKey(const Key('header-style')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.widgetWithText(Row, 'Concise'),
        matching: find.byIcon(AppIcons.check),
      ),
      findsOneWidget,
    );
  });
}
