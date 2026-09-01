import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/domain/ai_conversation.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_response_style.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';
import 'package:zivo/features/ai/domain/ai_turn_event.dart';
import 'package:zivo/features/diet/domain/diet_import_input.dart';
import 'package:zivo/features/diet/domain/diet_import_outcome.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/domain/plan_preferences.dart';
import 'package:zivo/features/ai/domain/stt_outcome.dart';
import 'package:zivo/features/workout/domain/workout_import_outcome.dart';
import 'package:zivo/features/ai/presentation/pages/ask_page.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';
import 'package:zivo/features/ai/presentation/widgets/ask/ask_effects.dart';

/// A scripted repository whose message stream is driven BY HAND, so tests
/// can reproduce the exact snapshot sequences real Firestore produces —
/// including stale/reordered cache emissions — and prove the optimistic
/// bubbles pair to their turn by identity, never doubling up.
class _ScriptedAi implements AiRepository {
  final StreamController<List<AiMessage>> _messages =
      StreamController<List<AiMessage>>.broadcast();
  final List<String> sentTurnIds = [];
  final List<String> sentTexts = [];

  /// Titles the page requested for new conversations, in order.
  final List<String?> createdTitles = [];

  void emit(List<AiMessage> messages) => _messages.add(messages);

  @override
  Stream<List<AiMessage>> watchMessages(String conversationId) =>
      _messages.stream;

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
    String responseStyle = kDefaultResponseStyle,
    String? clientTurnId,
  }) async {
    sentTurnIds.add(clientTurnId ?? '');
    sentTexts.add(text);
    onEvent?.call(const AiPhaseEvent(AiPhase.done));
  }

  @override
  Future<String> createConversation({String? title}) async {
    createdTitles.add(title);
    return title?.trim().isNotEmpty == true ? title!.trim() : 'conv-1';
  }

  // -- Unused by these tests -------------------------------------------------
  @override
  Future<AiConversation?> latestConversation() async => null;

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
  Future<WorkoutImportOutcome> importWorkoutPlan({
    required Uint8List fileBytes,
    required String mimeType,
  }) async => const WorkoutImportRejected('unused');

  @override
  Future<DietImportOutcome> importDietPlan(DietImportInput input) async =>
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

AiMessage _msg(int id, AiRole role, String text, [String? turnId]) => AiMessage(
  id: 'm$id',
  role: role,
  content: text,
  createdAt: DateTime.now(),
  clientTurnId: turnId,
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

void main() {
  testWidgets('a sent message renders as ONE bubble even when a stale '
      'snapshot re-emission arrives after the durable copy', (tester) async {
    final ai = _ScriptedAi();
    await tester.pumpWidget(_host(ai));
    await tester.pump();
    ai.emit(const []);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pump();

    // Optimistic bubble shows exactly once.
    expect(find.text('hello'), findsOneWidget);

    final turnId = ai.sentTurnIds.single;
    expect(turnId, isNotEmpty);

    // The durable user message lands…
    ai.emit([_msg(1, AiRole.user, 'hello', turnId)]);
    await tester.pump();
    await tester.pump();
    expect(find.text('hello'), findsOneWidget);

    // …then Firestore re-emits a STALE cached view without it — a sequence
    // real listeners can produce across reconnects. Whatever the UI shows,
    // it can NEVER show two copies: either the durable copy (1) or, while
    // the stale window is open, nothing — the optimistic slot must not come
    // back on top.
    ai.emit(const []);
    await tester.pump();
    expect(
      find.text('hello').evaluate().length,
      lessThanOrEqualTo(1),
      reason: 'A stale emission must not resurrect the optimistic copy',
    );

    // And the server view returns — still exactly one.
    ai.emit([_msg(1, AiRole.user, 'hello', turnId)]);
    await tester.pump();
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets("the streamed reply retires when ITS OWN turn's durable "
      'message lands — never rendering two replies', (tester) async {
    final ai = _ScriptedAi();
    await tester.pumpWidget(_host(ai));
    await tester.pump();
    ai.emit(const []);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'hi zivo');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pump();

    final turnId = ai.sentTurnIds.single;

    // User message lands; then the assistant's durable reply for the SAME
    // turn arrives while the live bubble would otherwise still render.
    ai.emit([
      _msg(1, AiRole.user, 'hi zivo', turnId),
      _msg(2, AiRole.assistant, 'the one true reply', turnId),
    ]);
    // A buffered (non-streamed) reply types itself in ONCE — settle through
    // the write, then assert on counts.
    await tester.pumpAndSettle();

    expect(find.text('hi zivo'), findsOneWidget);
    expect(
      find.text('the one true reply'),
      findsOneWidget,
      reason: 'The durable reply replaces the live bubble exactly once',
    );
  });

  testWidgets('a buffered reply keeps TYPING through interleaved snapshots '
      '— the reveal is never cut short into a second pop', (tester) async {
    // The recurring "appears twice" glitch, precisely: the durable reply's
    // first frame mounted the typewriter, and the NEXT build (any snapshot
    // emission) recomputed animate=false — swapping the half-typed bubble
    // for static full text mid-animation. The reveal flag now lives until
    // the typewriter finishes, so the write runs undisturbed.
    final ai = _ScriptedAi();
    await tester.pumpWidget(_host(ai));
    await tester.pump();
    ai.emit(const []);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'hi zivo');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pump();

    final turnId = ai.sentTurnIds.single;
    final durable = [
      _msg(1, AiRole.user, 'hi zivo', turnId),
      _msg(2, AiRole.assistant, 'the one true reply', turnId),
    ];
    ai.emit(durable);
    await tester.pump();

    // An identical re-emission one frame later (Firestore cache echo).
    ai.emit(durable);
    await tester.pump(const Duration(milliseconds: 10));

    // Only ~10ms into a ~160ms write: the reply must NOT be fully painted
    // yet. A mid-reveal swap would have dumped the entire text instantly.
    expect(
      find.text('the one true reply'),
      findsNothing,
      reason: 'mid-write, the typewriter must still own this bubble',
    );

    // Let the write finish — now the full text shows exactly once.
    await tester.pumpAndSettle();
    expect(find.text('the one true reply'), findsOneWidget);
  });

  testWidgets("the optimistic bubble's element SURVIVES the durable swap — "
      'one entrance, never two', (tester) async {
    // The "pop twice" bug: the pending bubble mounted its entrance motion,
    // then the durable doc arrived under a DIFFERENT key and re-ran it —
    // shrink, expand, again. The fix pairs both copies under one display
    // key (the turn id), so the same element continues across the swap.
    final ai = _ScriptedAi();
    await tester.pumpWidget(_host(ai));
    await tester.pump();
    ai.emit(const []);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // `RiseOnce` used to be private to the page, so this could only be found
    // by matching its runtime type's *name*. It is a real exported widget
    // now, so the finder can name the type.
    Element riseElement() => tester.element(find.byType(RiseOnce).last);
    final before = riseElement();

    final turnId = ai.sentTurnIds.single;
    ai.emit([_msg(1, AiRole.user, 'hello', turnId)]);
    await tester.pump();
    await tester.pump();

    expect(
      riseElement(),
      same(before),
      reason:
          'The bubble must be the SAME live element before and after '
          'the optimistic→durable swap; a remount would replay its '
          'entrance and read as the message appearing twice.',
    );
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('a new chat named at creation keeps its custom title instead '
      'of auto-titling from the first message', (tester) async {
    final ai = _ScriptedAi();
    await tester.pumpWidget(_host(ai));
    await tester.pump();
    ai.emit(const []);
    await tester.pump();

    // Open the naming sheet through the header action.
    await tester.tap(find.byKey(const Key('header-new-chat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-chat-name-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('new-chat-name-field')),
      'Workout Changes',
    );
    await tester.tap(find.text('Start chatting'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'make my pull day harder');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-send')));
    await tester.pump();

    // The conversation was created WITH the custom name (no auto-title).
    expect(ai.createdTitles.single, 'Workout Changes');
    expect(ai.sentTexts.single, 'make my pull day harder');
  });
}
