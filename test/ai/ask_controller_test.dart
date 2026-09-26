import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/l10n/app_localizations_en.dart';
import 'package:zivo/features/ai/domain/ai_conversation.dart';
import 'package:zivo/features/ai/domain/ai_failure.dart';
import 'package:zivo/features/ai/domain/ai_choice_request.dart';
import 'package:zivo/features/ai/domain/ai_message.dart';
import 'package:zivo/features/ai/domain/ai_pending_action.dart';
import 'package:zivo/features/ai/domain/ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_turn_usage.dart';
import 'package:zivo/features/ai/domain/ai_usage_summary.dart';
import 'package:zivo/features/ai/domain/body_data_writer.dart';
import 'package:zivo/features/workout/domain/workout_import_input.dart';
import 'package:zivo/features/ai/domain/ai_response_style.dart';
import 'package:zivo/features/ai/domain/ai_model_selection.dart';
import 'package:zivo/features/ai/domain/ai_role.dart';
import 'package:zivo/features/ai/domain/ai_turn_event.dart';
import 'package:zivo/features/ai/domain/stt_outcome.dart';
import 'package:zivo/features/ai/presentation/ai_thought.dart';
import 'package:zivo/features/ai/presentation/controllers/ask_controller.dart';
import 'package:zivo/features/diet/domain/diet_import_input.dart';
import 'package:zivo/features/diet/domain/diet_import_outcome.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/domain/plan_preferences.dart';
import 'package:zivo/features/workout/domain/workout_import_outcome.dart';
import 'package:zivo/features/ai/domain/import_cancellation.dart';

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

  test('answerChoice sends the picked label and records the pick', () async {
    final ai = _FakeAi();
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    await c.answerChoice('req-1', 'gain', 'Gain weight');

    // The pick goes out as an ordinary next turn, so the coach continues from
    // it exactly as if the user had typed it.
    expect(ai.sent.single.text, 'Gain weight');
    // And the card is marked so its chips settle into the picked state.
    expect(c.answeredChoices['req-1'], 'gain');
  });

  test('answerChoice is a no-op once the card is already answered', () async {
    final ai = _FakeAi();
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    await c.answerChoice('req-1', 'gain', 'Gain weight');
    await c.answerChoice('req-1', 'lose', 'Lose fat');

    expect(ai.sent, hasLength(1));
    expect(c.answeredChoices['req-1'], 'gain');
  });

  test('submitInput sends the summary and marks the form submitted', () async {
    final ai = _FakeAi();
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    await c.submitInput('form-1', 'Height: 180 cm · Weight: 74 kg', const {});

    expect(ai.sent.single.text, 'Height: 180 cm · Weight: 74 kg');
    expect(c.submittedInputs['form-1'], 'Height: 180 cm · Weight: 74 kg');
  });

  test('submitInput is a no-op once the form is already submitted', () async {
    final ai = _FakeAi();
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    await c.submitInput('form-1', 'Height: 180 cm', const {});
    await c.submitInput('form-1', 'Height: 999 cm', const {});

    expect(ai.sent, hasLength(1));
    expect(c.submittedInputs['form-1'], 'Height: 180 cm');
  });

  test('submitInput persists whitelisted height/weight to body data', () async {
    final ai = _FakeAi();
    final writer = _FakeBodyWriter();
    final c = _controller(ai, bodyWriter: writer);
    addTearDown(c.dispose);
    await c.load();

    await c.submitInput('form-1', 'Height: 180 cm · Weight: 74 kg', const {
      'heightCm': '180',
      'weightKg': '74',
    });

    expect(writer.heights, [180.0]);
    expect(writer.weights, [74.0]);
    // The value still reaches the coach as the summary turn.
    expect(ai.sent.single.text, 'Height: 180 cm · Weight: 74 kg');
  });

  test('submitInput ignores non-whitelisted keys and bad numbers', () async {
    final ai = _FakeAi();
    final writer = _FakeBodyWriter();
    final c = _controller(ai, bodyWriter: writer);
    addTearDown(c.dispose);
    await c.load();

    await c.submitInput('form-1', 'summary', const {
      'goal': 'gain',
      'heightCm': 'not a number',
    });

    expect(writer.heights, isEmpty);
    expect(writer.weights, isEmpty);
  });

  test('submitInput still sends when persistence throws', () async {
    final ai = _FakeAi();
    final writer = _FakeBodyWriter(throwOnSave: true);
    final c = _controller(ai, bodyWriter: writer);
    addTearDown(c.dispose);
    await c.load();

    await c.submitInput('form-1', 'Weight: 74 kg', const {'weightKg': '74'});

    expect(ai.sent.single.text, 'Weight: 74 kg');
  });

  test('submitInput does not block the reply on a hanging persist', () async {
    // Audit F1: a Firestore write's future resolves only on server ack, so a
    // persist that never completes (offline) must NOT stop the coach replying.
    final ai = _FakeAi();
    final writer = _FakeBodyWriter(hang: true);
    final c = _controller(ai, bodyWriter: writer);
    addTearDown(c.dispose);
    await c.load();

    // If persistence were awaited this would hang and the test would time out.
    await c.submitInput('form-1', 'Weight: 74 kg', const {'weightKg': '74'});

    expect(ai.sent.single.text, 'Weight: 74 kg');
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

  test(
    'a chat named at creation keeps its name instead of auto-titling',
    () async {
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
    },
  );

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
      reason:
          'a fast second send would overwrite the unlanded optimistic bubble',
    );
  });

  test('Retry works when the message landed before the model failed', () async {
    // The real-world shape: the server saves the user message, THEN the
    // model call fails (Claude out of credit). The page clears the optimistic
    // bubble the moment the saved message lands — which used to leave Retry
    // with nothing to send, so tapping it did nothing.
    final ai = _FakeAi(
      failWith: const AiFailure(
        AiFailureKind.unavailable,
        provider: 'anthropic',
        issue: AiProviderIssue.outOfCredit,
      ),
    );
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    c.input.text = 'is that the Gemini model?';
    await c.send();
    expect(c.sendFailed, isTrue);
    expect(
      c.sendFailure.provider,
      'anthropic',
      reason: 'the card can name the provider that failed',
    );
    expect(c.sendFailure.issue, AiProviderIssue.outOfCredit);

    // The persisted user message landed → the page retires the bubble.
    c.clearPending();
    expect(c.pendingText, isNull);

    // The user switches model and retries: it must actually re-send, with
    // the NEW model and the SAME turn id (so the server doesn't re-append).
    ai.failWith = null;
    await c.setModelSelection('gemini-flash');
    await c.retry(c.activeConversationId!);

    expect(ai.sent, hasLength(2));
    expect(ai.sent.last.text, 'is that the Gemini model?');
    expect(ai.sent.last.turnId, ai.sent.first.turnId);
    expect(ai.sent.last.modelSelection, 'gemini-flash');
    expect(c.sendFailed, isFalse);
  });

  test('a tapped choice sends its structured pick, and a retry re-sends the '
      'same pick — never just its label', () async {
    final ai = _FakeAi(failSend: true);
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    await c.answerChoice('req-1', 'usda:175160', 'Tuna salad');
    expect(ai.sent.single.text, 'Tuna salad');
    expect(ai.sent.single.choice!.requestId, 'req-1');
    expect(ai.sent.single.choice!.value, 'usda:175160');
    expect(c.answeredChoices['req-1'], 'usda:175160');

    await c.retry(c.activeConversationId!);
    expect(ai.sent, hasLength(2));
    expect(ai.sent.last.choice!.value, 'usda:175160');
    expect(ai.sent.last.turnId, ai.sent.first.turnId);

    // A typed message afterwards carries no pick.
    c.input.text = 'thanks';
    await c.send();
    expect(ai.sent.last.choice, isNull);
  });

  test('the screen Ask was opened from rides the next turn only — and its '
      'retry', () async {
    final ai = _FakeAi(failSend: true);
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    c.openedFrom('readiness');
    c.input.text = 'why?';
    await c.send();
    expect(ai.sent.single.entryPoint, 'readiness');

    await c.retry(c.activeConversationId!);
    expect(ai.sent.last.entryPoint, 'readiness');

    // The next message is part of the conversation, not a fresh open.
    c.input.text = 'and tomorrow?';
    await c.send();
    expect(ai.sent.last.entryPoint, isNull);
  });

  test('a second tap on an answered card sends nothing', () async {
    final ai = _FakeAi();
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    await c.answerChoice('req-1', 'a', 'A');
    await c.answerChoice('req-1', 'b', 'B');
    expect(ai.sent, hasLength(1));
    expect(ai.sent.single.choice!.value, 'a');
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

  test(
    'a failed send surfaces the retry state and clears the live text',
    () async {
      final c = _controller(_FakeAi(failSend: true));
      addTearDown(c.dispose);
      await c.load();

      c.input.text = 'hello';
      await c.send();

      expect(c.sendFailed, isTrue);
      expect(c.sending, isFalse);
      expect(c.liveText, isEmpty);
      expect(c.pendingText, 'hello', reason: 'the bubble stays for the retry');
    },
  );

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

  test(
    'setModelSelection persists and is forwarded on the next send',
    () async {
      final ai = _FakeAi();
      final c = _controller(ai);
      addTearDown(c.dispose);
      await c.load();
      expect(
        c.modelSelection,
        'claude-sonnet',
        reason: 'default before any choice',
      );

      await c.setModelSelection('gemini-flash');
      expect(c.modelSelection, 'gemini-flash');
      expect(await ai.getModelSelection(), 'gemini-flash', reason: 'persisted');

      c.input.text = 'hello';
      await c.send();

      expect(
        ai.sent.single.modelSelection,
        'gemini-flash',
        reason: 'the chosen provider rides along on send',
      );
    },
  );

  test('a failed model-selection save rolls back and reports', () async {
    final ai = _FakeAi(failStyleSave: true);
    String? reported;
    final c = _controller(ai, onError: (m) => reported = m);
    addTearDown(c.dispose);
    await c.load();
    final original = c.modelSelection;

    await c.setModelSelection('gemini-flash');

    expect(c.modelSelection, original);
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

  test(
    'a running step names the rail; finishing it falls back to the phase',
    () async {
      final labels = <String>[];
      late final AskController c;
      final ai = _FakeAi(
        events: const [
          AiPhaseEvent(AiPhase.working),
          AiStepEvent('get_diet', AiStepStatus.running),
          AiStepEvent('get_diet', AiStepStatus.ok),
          AiStepEvent('resolve_food', AiStepStatus.running),
        ],
        afterEachEvent: () => labels.add(c.railLabel),
      );
      c = _controller(ai);
      addTearDown(c.dispose);
      await c.load();

      c.input.text = 'how many calories left?';
      await c.send();

      expect(labels, [
        'Thinking…',
        'Reading your meal plan…',
        // Step closed → the phase speaks again, rather than a finished step
        // claiming work that has stopped.
        'Thinking…',
        'Searching the food catalog…',
      ]);
      // Every line is a human state, never an identifier.
      for (final label in labels) {
        expect(label, isNot(contains('_')));
      }
    },
  );

  test(
    'an unknown tool degrades to the generic line, never a raw identifier',
    () async {
      final labels = <String>[];
      late final AskController c;
      final ai = _FakeAi(
        events: const [
          AiPhaseEvent(AiPhase.working),
          AiStepEvent('get_body_composition', AiStepStatus.running),
        ],
        afterEachEvent: () => labels.add(c.railLabel),
      );
      c = _controller(ai);
      addTearDown(c.dispose);
      await c.load();

      c.input.text = 'hi';
      await c.send();

      expect(labels.last, 'Thinking…');
      expect(labels.last, isNot(contains('get_body_composition')));
      expect(c.railThought, AiThoughtKind.thinking);
    },
  );

  test(
    'the activity timeline records every step in order, settling each one',
    () async {
      final timelines = <List<AiActivityStep>>[];
      late final AskController c;
      final ai = _FakeAi(
        events: const [
          AiPhaseEvent(AiPhase.working),
          AiStepEvent('get_diet', AiStepStatus.running),
          AiStepEvent('get_diet', AiStepStatus.ok),
          AiPhaseEvent(AiPhase.thinking),
          AiStepEvent('suggest_meal_replacement', AiStepStatus.running),
          AiStepEvent('suggest_meal_replacement', AiStepStatus.error),
        ],
        afterEachEvent: () => timelines.add(c.activity),
      );
      c = _controller(ai);
      addTearDown(c.dispose);
      await c.load();

      c.input.text = 'مش عايز ملوخية في الدايت';
      await c.send();

      expect(timelines[1], const [
        AiActivityStep('get_diet', AiStepStatus.running),
      ]);
      expect(timelines[2], const [AiActivityStep('get_diet', AiStepStatus.ok)]);
      expect(timelines.last, const [
        AiActivityStep('get_diet', AiStepStatus.ok),
        AiActivityStep('suggest_meal_replacement', AiStepStatus.error),
      ]);
      // Kept after the turn so the live reply holds its timeline until the
      // durable copy (which carries the same list) lands.
      expect(c.activity, timelines.last);
    },
  );

  test('a model fallback is recorded on the timeline and drops text the '
      'failed model streamed', () async {
    late final AskController c;
    String? liveAfterFallback;
    final ai = _FakeAi(
      events: const [
        AiDeltaEvent('Half an ans'),
        AiFallbackEvent('gemini-flash', 'claude-sonnet'),
        AiStepEvent('get_diet', AiStepStatus.ok),
      ],
      afterEachEvent: () {
        if (c.activity.any((s) => s.isFallback)) {
          liveAfterFallback ??= c.liveText;
        }
      },
    );
    c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    c.input.text = 'مش عايز ملوخية';
    await c.send();

    expect(c.activity, const [
      AiActivityStep.fallback('gemini-flash', 'claude-sonnet'),
      AiActivityStep('get_diet', AiStepStatus.ok),
    ]);
    expect(liveAfterFallback, isEmpty);
  });

  test('a fallback drops only what the failed model wrote in THIS step — an '
      'earlier step\'s lead-in stays on screen', () async {
    late final AskController c;
    String? targetAfterFallback;
    final ai = _FakeAi(
      events: const [
        AiDeltaEvent('Let me check your plan.'),
        AiStepEvent('get_diet', AiStepStatus.running),
        AiStepEvent('get_diet', AiStepStatus.ok),
        AiPhaseEvent(AiPhase.thinking),
        AiDeltaEvent('\n\nHalf an ans'),
        AiFallbackEvent('gemini-flash', 'claude-sonnet'),
      ],
      afterEachEvent: () {
        if (c.activity.any((s) => s.isFallback)) {
          targetAfterFallback ??= c.liveTargetText;
        }
      },
    );
    c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();
    c.input.text = 'breakfast?';
    await c.send();
    expect(targetAfterFallback, 'Let me check your plan.');
  });

  test('between tool rounds the rail says Analyzing what I found…', () async {
    final labels = <String>[];
    late final AskController c;
    final ai = _FakeAi(
      events: const [
        AiStepEvent('get_diet', AiStepStatus.running),
        AiStepEvent('get_diet', AiStepStatus.ok),
        AiPhaseEvent(AiPhase.thinking),
      ],
      afterEachEvent: () => labels.add(c.railLabel),
    );
    c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    c.input.text = "what's my lunch?";
    await c.send();

    expect(labels.last, 'Analyzing what I found…');
    expect(labels.first, 'Reading your meal plan…');
  });

  test('a new turn starts with an empty timeline', () async {
    final ai = _FakeAi(
      events: const [AiStepEvent('get_diet', AiStepStatus.ok)],
    );
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();
    c.input.text = 'first';
    await c.send();
    expect(c.activity, hasLength(1));

    c.switchTo(null, isUntitled: true);
    expect(c.activity, isEmpty);
  });

  test('a step never survives its turn — the next turn starts calm', () async {
    final ai = _FakeAi(
      events: const [AiStepEvent('get_diet', AiStepStatus.running)],
    );
    final c = _controller(ai);
    addTearDown(c.dispose);
    await c.load();

    c.input.text = 'first';
    await c.send();

    // The turn ended without ever closing that step (a dropped final event).
    // It must not leak into the idle rail or the next turn.
    expect(c.stepTool, isNull);
    expect(c.railLabel, 'Thinking…');
  });
}

// ---- Fixtures ---------------------------------------------------------------

class _NoopTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

/// English copy, built directly rather than resolved from a widget tree —
/// [AskController] takes an [AppLocalizations] value (it never holds a
/// BuildContext, per ADR-008), so these tests need no `pumpWidget`.
AskController _controller(
  AiRepository ai, {
  void Function(String)? onError,
  BodyDataWriter? bodyWriter,
}) => AskController(
  ai: ai,
  recorder: null,
  vsync: _NoopTickerProvider(),
  transcribeTimeout: const Duration(seconds: 5),
  strings: AppLocalizationsEn(),
  onError: onError,
  bodyWriter: bodyWriter,
);

/// Records what the controller asked to persist. [hang] makes the writes never
/// complete — standing in for an offline Firestore write, whose future resolves
/// only on server ack.
class _FakeBodyWriter implements BodyDataWriter {
  _FakeBodyWriter({this.throwOnSave = false, this.hang = false});
  final bool throwOnSave;
  final bool hang;
  final List<double> heights = [];
  final List<double> weights = [];

  @override
  Future<void> saveWeightKg(double weightKg) async {
    if (hang) return Completer<void>().future;
    if (throwOnSave) throw StateError('save failed');
    weights.add(weightKg);
  }

  @override
  Future<bool> saveHeightCm(double heightCm) async {
    if (hang) return Completer<bool>().future;
    if (throwOnSave) throw StateError('save failed');
    heights.add(heightCm);
    return true;
  }
}

AiMessage _message(String id, AiRole role, String text, String? turnId) =>
    AiMessage(
      id: id,
      role: role,
      content: text,
      createdAt: DateTime(2026, 3, 1),
      clientTurnId: turnId,
    );

typedef _Sent = ({
  String conversationId,
  String text,
  String? turnId,
  String modelSelection,
  AiChoiceSelection? choice,
  String? entryPoint,
});

/// A scripted [AiRepository] — only the members Ask actually drives are
/// implemented; the import/generate surface throws if ever reached.
class _FakeAi implements AiRepository {
  _FakeAi({
    this.failWith,
    this.latest,
    this.responseStyle = kDefaultResponseStyle,
    this.failSend = false,
    this.failStyleSave = false,
    this.failConfirm = false,
    this.phases = const [],
    this.events = const [],
    this.afterEachEvent,
  });

  /// Arbitrary turn events, replayed in order — use instead of [phases] when
  /// the test needs steps or a specific interleaving.
  final List<AiTurnEvent> events;

  /// Runs after each event in [events] is delivered, so a test can observe the
  /// controller *mid-turn*. Without it `send()` returns with the turn already
  /// over and every intermediate label lost.
  final void Function()? afterEachEvent;

  /// When set, [send] throws it (after recording the call) — a typed
  /// [AiFailure] the way the real repository reports one.
  Object? failWith;

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

  String modelSelection = kDefaultAiModelSelection;

  @override
  Future<String> getModelSelection() async => modelSelection;

  @override
  Future<List<AiProviderUsage>> usageByProvider() async => const [];

  @override
  Future<List<AiUsageRecord>> usageRecords({int limit = 1000}) async =>
      const [];
  @override
  Future<AiTurnUsage?> usageForTurn(String clientTurnId) async => null;

  @override
  Future<void> setModelSelection(String selection) async {
    if (failStyleSave) throw StateError('offline');
    modelSelection = selection;
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
    String modelSelection = kDefaultAiModelSelection,
    String? clientTurnId,
    AiChoiceSelection? choice,
    String? entryPoint,
  }) async {
    sent.add((
      conversationId: conversationId,
      text: text,
      turnId: clientTurnId,
      modelSelection: modelSelection,
      choice: choice,
      entryPoint: entryPoint,
    ));
    for (final phase in phases) {
      observedPhases.add(phase);
      onEvent?.call(AiPhaseEvent(phase));
    }
    for (final event in events) {
      onEvent?.call(event);
      afterEachEvent?.call();
    }
    if (failSend) throw StateError('offline');
    if (failWith != null) throw failWith!;
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
  Future<WorkoutImportOutcome> importWorkoutPlan(
    WorkoutImportInput input, {
    ImportCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<DietImportOutcome> importDietPlan(
    DietImportInput input, {
    ImportCancellation? cancellation,
  }) => throw UnimplementedError();

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
