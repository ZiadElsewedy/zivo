import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/ai/domain/ai_conversation.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_pending_action.dart';
import 'package:zivo/features/ai/domain/ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_response_style.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';
import 'package:zivo/features/ai/domain/ai_turn_event.dart';
import 'package:zivo/features/ai/domain/stt_outcome.dart';
import 'package:zivo/features/ai/presentation/controllers/ask_controller.dart';
import 'package:zivo/features/diet/domain/diet_import_input.dart';
import 'package:zivo/features/diet/domain/diet_import_outcome.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/domain/plan_preferences.dart';
import 'package:zivo/features/workout/domain/workout_import_outcome.dart';

/// The Ask turn machinery, asserted directly.
///
/// These were only expressible as widget tests before — "a second send is
/// blocked while the first turn's message hasn't landed" needed a pumped page
/// and a key-based finder. They are statements about a turn, so they live
/// here now; `ask_page_*_test.dart` still covers what the screen renders.
void main() {
  setUp(TestWidgetsFlutterBinding.ensureInitialized);

  test('load() resumes the most recent conversation and its style', () async {
    final ai = _FakeAi(
      latest: AiConversation(
        id: 'c1',
        title: 'Leg day',
        createdAt: DateTime(2026, 3, 1),
        updatedAt: DateTime(2026, 3, 1),
      ),
      responseStyle: 'concise',
    );
    final c = _controller(ai);
    addTearDown(c.dispose);

    await c.load();

    expect(c.activeConversationId, 'c1');
    expect(c.activeResolved, isTrue);
    expect(c.activeIsUntitled, isFalse);
    expect(c.responseStyle, 'concise');
  });

  test('with no conversations it resolves to an unsaved New chat', () async {
    final c = _controller(_FakeAi());
    addTearDown(c.dispose);

    await c.load();

    expect(c.activeConversationId, isNull);
    expect(
      c.activeResolved,
      isTrue,
      reason: '"resolved to nothing" must be distinguishable from "loading"',
    );
  });

  test('the first send lazily creates the conversation', () async {
    final ai = _FakeAi();
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    c.input.text = 'hello';
    await c.send();

    expect(ai.created, 1, reason: 'nothing is persisted before the first send');
    expect(c.activeConversationId, isNotNull);
    expect(ai.sent.single.text, 'hello');
    expect(c.pendingText, 'hello');
  });

  test('a first message in an untitled chat auto-titles it', () async {
    final ai = _FakeAi();
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    c.input.text = 'How is my bench trending?';
    await c.send();

    expect(ai.renamed.single.$2, 'How is my bench trending?');
  });

  test('a chat named at creation keeps its name instead of auto-titling', () async {
    final ai = _FakeAi();
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();
    c.setDraftTitle('Workout Changes');

    c.input.text = 'anything';
    await c.send();

    expect(ai.created, 1);
    expect(ai.createdTitles.single, 'Workout Changes');
    expect(ai.renamed, isEmpty);
  });

  test('a second send is blocked while the first has not landed', () async {
    final ai = _FakeAi();
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    c.input.text = 'first';
    await c.send();
    c.input.text = 'second';
    await c.send();

    expect(
      ai.sent.map((s) => s.text),
      ['first'],
      reason: 'a fast second send would overwrite the unlanded optimistic bubble',
    );
  });

  test('a retry reuses the turn id, so the server can dedupe it', () async {
    final ai = _FakeAi(failSend: true);
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    c.input.text = 'hello';
    await c.send();
    expect(c.sendFailed, isTrue);
    final firstTurnId = ai.sent.single.turnId;

    await c.retry(c.activeConversationId!);

    expect(ai.sent, hasLength(2));
    expect(
      ai.sent.last.turnId,
      firstTurnId,
      reason: 'a retry must never be able to double-post the same message',
    );
  });

  test('a failed send surfaces the retry state and clears the live text', () async {
    final c = _controller(_FakeAi(failSend: true));
    addTearDown(c.dispose);
    await c.load();

    c.input.text = 'hello';
    await c.send();

    expect(c.sendFailed, isTrue);
    expect(c.sending, isFalse);
    expect(c.liveText, isEmpty);
    expect(c.pendingText, 'hello', reason: 'the bubble stays for the retry');
  });

  test('turnLanded pairs by client turn id, not by text or count', () async {
    final ai = _FakeAi();
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();
    c.input.text = 'hello';
    await c.send();

    expect(c.turnLanded(AiRole.user), isFalse);

    c.setPersisted([
      _message('m1', AiRole.user, 'hello', ai.sent.single.turnId),
    ]);

    expect(c.turnLanded(AiRole.user), isTrue);
    expect(c.turnLanded(AiRole.assistant), isFalse);
  });

  test('switching conversations drops every trace of the old turn', () async {
    final c = _controller(_FakeAi());
    addTearDown(c.dispose);
    await c.load();
    c.input.text = 'hello';
    await c.send();
    c.resolved['a1'] = AiActionStatus.applied;

    c.switchTo('other', isUntitled: false);

    expect(c.activeConversationId, 'other');
    expect(c.pendingText, isNull);
    expect(c.sendFailed, isFalse);
    expect(c.liveText, isEmpty);
    expect(c.resolved, isEmpty);
    expect(c.activeTurnId, isNull);
    expect(c.lastPersisted, isEmpty);
  });

  test('a failed response-style save rolls back and reports', () async {
    final ai = _FakeAi(failStyleSave: true);
    String? reported;
    final c = _controller(ai, onError: (m) => reported = m);
    addTearDown(c.dispose);
    await c.load();
    final original = c.responseStyle;

    await c.setResponseStyle('detailed');

    expect(c.responseStyle, original);
    expect(reported, isNotNull);
  });

  test('a failed confirm un-resolves the card and reports', () async {
    final ai = _FakeAi(failConfirm: true);
    String? reported;
    final c = _controller(ai, onError: (m) => reported = m);
    addTearDown(c.dispose);

    await c.confirm('c1', 'a1');

    expect(c.resolved.containsKey('a1'), isFalse);
    expect(reported, isNotNull);
  });

  test('the rail label follows the gateway phase', () async {
    final ai = _FakeAi(phases: [AiPhase.understanding, AiPhase.working]);
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    expect(c.railLabel, 'Thinking…', reason: 'calm before any phase arrives');

    c.input.text = 'hello';
    await c.send();

    // The turn finished, so the phase resets to the calm default.
    expect(c.railLabel, 'Thinking…');
    expect(ai.observedPhases, [AiPhase.understanding, AiPhase.working]);
  });
}

// ---- Fixtures ---------------------------------------------------------------

class _NoopTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

AskController _controller(AiRepository ai, {void Function(String)? onError}) =>
    AskController(
      ai: ai,
      recorder: null,
      vsync: _NoopTickerProvider(),
      transcribeTimeout: const Duration(seconds: 5),
      onError: onError,
    );

AiMessage _message(String id, AiRole role, String text, String? turnId) =>
    AiMessage(
      id: id,
      role: role,
      content: text,
      createdAt: DateTime(2026, 3, 1),
      clientTurnId: turnId,
    );

typedef _Sent = ({String conversationId, String text, String? turnId});

/// A scripted [AiRepository] — only the members Ask actually drives are
/// implemented; the import/generate surface throws if ever reached.
class _FakeAi implements AiRepository {
  _FakeAi({
    this.latest,
    this.responseStyle = kDefaultResponseStyle,
    this.failSend = false,
    this.failStyleSave = false,
    this.failConfirm = false,
    this.phases = const [],
  });

  final AiConversation? latest;
  String responseStyle;
  final bool failSend;
  final bool failStyleSave;
  final bool failConfirm;
  final List<AiPhase> phases;

  int created = 0;
  final List<String?> createdTitles = [];
  final List<(String, String)> renamed = [];
  final List<_Sent> sent = [];
  final List<AiPhase> observedPhases = [];

  @override
  Future<AiConversation?> latestConversation() async => latest;

  @override
  Future<String> getResponseStyle() async => responseStyle;

  @override
  Future<void> setResponseStyle(String style) async {
    if (failStyleSave) throw StateError('offline');
    responseStyle = style;
  }

  @override
  Future<String> createConversation({String? title}) async {
    created++;
    createdTitles.add(title);
    return 'c$created';
  }

  @override
  Future<void> renameConversation(String id, String title) async =>
      renamed.add((id, title));

  @override
  Stream<List<AiMessage>> watchMessages(String conversationId) =>
      const Stream<List<AiMessage>>.empty();

  @override
  Future<void> send({
    required String conversationId,
    required String text,
    void Function(AiTurnEvent event)? onEvent,
    String responseStyle = kDefaultResponseStyle,
    String? clientTurnId,
  }) async {
    sent.add((conversationId: conversationId, text: text, turnId: clientTurnId));
    for (final phase in phases) {
      observedPhases.add(phase);
      onEvent?.call(AiPhaseEvent(phase));
    }
    if (failSend) throw StateError('offline');
  }

  @override
  Future<void> confirmAction({
    required String conversationId,
    required String actionId,
  }) async {
    if (failConfirm) throw StateError('offline');
  }

  @override
  Future<void> cancelAction({
    required String conversationId,
    required String actionId,
  }) async {}

  @override
  Future<String> ensureConversation() async => 'c1';

  @override
  Stream<List<AiConversation>> watchConversations() =>
      const Stream<List<AiConversation>>.empty();

  @override
  Future<void> deleteConversation(String id) async {}

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
