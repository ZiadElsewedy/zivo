import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_conversation.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_turn_event.dart';
import 'package:zivo/features/ai/domain/ai_response_style.dart';
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

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

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

/// A repository whose first [send] throws (a network drop) and later ones
/// succeed — for proving the retry path recovers.
class _FlakyAi implements AiRepository {
  _FlakyAi(this._inner);

  final FakeAiRepository _inner;
  bool failNext = true;

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
    String responseStyle = kDefaultResponseStyle,
    String? clientTurnId,
  }) async {
    if (failNext) {
      failNext = false;
      throw Exception('network unreachable');
    }
    return _inner.send(
      conversationId: conversationId,
      text: text,
      onEvent: onEvent,
      responseStyle: responseStyle,
    );
  }

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
  Future<String> getResponseStyle() => _inner.getResponseStyle();

  @override
  Future<void> setResponseStyle(String style) => _inner.setResponseStyle(style);

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
  }) => _inner.importWorkoutPlan(fileBytes: fileBytes, mimeType: mimeType);

  @override
  Future<DietImportOutcome> importDietPlan(DietImportInput input) =>
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
}

/// A repository whose sends "succeed" but never persist anything — the
/// silent server drop that used to leave the chat looking eternally hung.
class _SilentDropAi implements AiRepository {
  @override
  Future<String> ensureConversation() async => 'c1';

  @override
  Future<String> createConversation({String? title}) async => 'c1';

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
  Stream<List<AiMessage>> watchMessages(String conversationId) =>
      Stream.value(const []);

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
    String responseStyle = kDefaultResponseStyle,
    String? clientTurnId,
  }) async {}

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
    required Uint8List fileBytes,
    required String mimeType,
  }) => throw UnimplementedError();

  @override
  Future<DietImportOutcome> importDietPlan(DietImportInput input) =>
      throw UnimplementedError();

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
  }) => throw UnimplementedError();
}

Future<void> _typeAndSend(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('composer-send')));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'a failed send shows the modern inline error card, and Retry recovers',
    (tester) async {
      final inner = FakeAiRepository();
      addTearDown(inner.dispose);
      final ai = _FlakyAi(inner);
      // Seed one real conversation so the flaky first send has a thread.
      final id = await inner.createConversation();
      await inner.send(conversationId: id, text: 'earlier');

      await tester.pumpWidget(_host(ai));
      await tester.pumpAndSettle();

      await _typeAndSend(tester, 'what is due this week?');

      // The turn failed: quiet inline card, message kept in its bubble.
      expect(find.byKey(const Key('error-retry')), findsOneWidget);
      expect(find.text("Couldn't reach ZIVO"), findsOneWidget);
      expect(find.text('Your message wasn\u2019t sent.'), findsOneWidget);
      expect(find.text('what is due this week?'), findsOneWidget);

      // Retry goes through: card retires, canned reply types in.
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('error-retry')), findsNothing);
      // Two canned replies exist: the seeded thread's and the retried turn's.
      expect(find.text(kFakeAiReply), findsNWidgets(2));
      // The optimistic user bubble reconciled into exactly one durable copy.
      expect(find.text('what is due this week?'), findsOneWidget);
    },
  );

  testWidgets(
    'a silent gateway admits the wait in the rail instead of spinning '
    'quietly forever',
    (tester) async {
      final inner = FakeAiRepository();
      addTearDown(inner.dispose);
      final ai = _HeldAi(inner);
      await inner.createConversation(); // the page opens into this thread

      await tester.pumpWidget(_host(ai));
      await tester.pumpAndSettle();

      await _typeAndSend(tester, 'hello there');

      expect(find.text('Thinking…'), findsOneWidget);
      expect(find.textContaining('Still working'), findsNothing);

      // Past the slow threshold with zero gateway activity: honest line.
      await tester.pump(const Duration(seconds: 19));
      expect(find.textContaining('Still working'), findsOneWidget);

      // The turn finishes: reassurance retires with the rail.
      ai.gate.complete();
      await tester.pumpAndSettle();

      expect(find.textContaining('Still working'), findsNothing);
      expect(find.text(kFakeAiReply), findsOneWidget);
    },
  );

  testWidgets(
    'when a turn ends but nothing ever persists, the optimistic bubble '
    'flips to the retry card instead of hanging forever',
    (tester) async {
      final ai = _SilentDropAi();

      await tester.pumpWidget(_host(ai));
      await tester.pumpAndSettle();

      await _typeAndSend(tester, 'is anyone there?');
      // Stream ended cleanly; nothing landed yet. Optimistic bubble holds.
      expect(find.text('is anyone there?'), findsOneWidget);
      expect(find.byKey(const Key('error-retry')), findsNothing);

      // Past the landing grace period with no persisted user message.
      await tester.pump(const Duration(seconds: 13));
      expect(find.byKey(const Key('error-retry')), findsOneWidget);
      // The user's words are never lost.
      expect(find.text('is anyone there?'), findsOneWidget);
      // Let the card's entrance motion finish so no timer stays pending.
      await tester.pump(const Duration(milliseconds: 600));
    },
  );
}

/// Wraps [FakeAiRepository] but blocks inside [send] on [gate] WITHOUT ever
/// emitting an event — simulates a gateway that accepted the request and
/// went completely quiet.
class _HeldAi implements AiRepository {
  _HeldAi(this._inner);

  final FakeAiRepository _inner;

  /// Release this to let the held send finish normally.
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
    String responseStyle = kDefaultResponseStyle,
    String? clientTurnId,
  }) async {
    await gate.future;
    return _inner.send(
      conversationId: conversationId,
      text: text,
      onEvent: onEvent,
      responseStyle: responseStyle,
    );
  }

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
  Future<String> getResponseStyle() => _inner.getResponseStyle();

  @override
  Future<void> setResponseStyle(String style) => _inner.setResponseStyle(style);

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
  }) => _inner.importWorkoutPlan(fileBytes: fileBytes, mimeType: mimeType);

  @override
  Future<DietImportOutcome> importDietPlan(DietImportInput input) =>
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
}
