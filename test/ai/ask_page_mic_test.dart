import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/audio_recorder.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/domain/stt_error.dart';
import 'package:zivo/features/ai/domain/stt_outcome.dart';
import 'package:zivo/features/ai/presentation/pages/ask_page.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A scriptable [AudioRecorderService] fake: no plugin, no real microphone.
/// Exposes a manual [levels] sink so tests can drive the live waveform the
/// way the real amplitude stream does.
class _FakeRecorder implements AudioRecorderService {
  bool permissionGranted = true;
  RecordedAudio? nextStopResult;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

  final StreamController<double> _levelController =
      StreamController<double>.broadcast();
  StreamSink<double> get levels => _levelController;

  @override
  bool isRecording = false;

  @override
  Future<bool> ensurePermission() async => permissionGranted;

  @override
  Future<void> start() async {
    startCalls++;
    isRecording = true;
  }

  @override
  Future<RecordedAudio?> stop() async {
    stopCalls++;
    isRecording = false;
    return nextStopResult;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    isRecording = false;
  }

  @override
  Stream<double> inputLevels() => _levelController.stream;

  void dispose() => _levelController.close();
}

Widget _host(
  _FakeRecorder recorder,
  FakeAiRepository ai, {
  Duration transcribeTimeout = const Duration(seconds: 35),
}) => AppScope(
  auth: FakeAuthRepository(),
  profiles: FakeProfileRepository(),
  expenses: InMemoryExpenseRepository(),
  moments: InMemoryMomentRepository(),
  workouts: InMemoryWorkoutRepository(),
  workoutPlans: InMemoryWorkoutPlanRepository(),
  workoutSessions: InMemoryWorkoutSessionRepository(),
  diet: InMemoryDietRepository(),
  ai: ai,
  recorder: recorder,
  child: MaterialApp(home: AskPage(transcribeTimeout: transcribeTimeout)),
);

/// The recording state loops its pulse/waveform animations, so tests must
/// never `pumpAndSettle` while it is up — these helpers pump fixed time.
///
/// [_flush] pumps several small frames so an [AnimatedSwitcher]'s outgoing
/// bar fully finishes its exit transition before absence assertions run.

Future<void> _flush(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
Future<void> _startRecording(WidgetTester tester, _FakeRecorder recorder) async {
  await tester.tap(find.byKey(const Key('composer-mic')));
  await tester.pump(const Duration(milliseconds: 300));
  expect(recorder.startCalls, 1);
  expect(find.byKey(const Key('composer-stop')), findsOneWidget);
}

void main() {
  testWidgets(
    'tapping the mic starts recording, tapping stop drops the transcript '
    'into the composer without sending it',
    (tester) async {
      final recorder = _FakeRecorder()
        ..nextStopResult = RecordedAudio(
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'audio/m4a',
        );
      final ai = FakeAiRepository(
        transcribeImpl: (audioBytes, mimeType, languageHint) async =>
            const SttTranscribed(text: 'What is due this week?'),
      );
      addTearDown(ai.dispose);
      addTearDown(recorder.dispose);

      await tester.pumpWidget(_host(recorder, ai));
      await tester.pumpAndSettle();

      await _startRecording(tester, recorder);

      await tester.tap(find.byKey(const Key('composer-stop')));
      await tester.pumpAndSettle();

      expect(recorder.stopCalls, 1);
      expect(find.byKey(const Key('composer-mic')), findsOneWidget);
      expect(find.text('What is due this week?'), findsOneWidget);
      // The transcript is in the composer for editing — not sent yet.
      expect(find.text("Hey, I'm ZIVO."), findsOneWidget);
    },
  );

  testWidgets(
    'the waveform reacts to live microphone levels and the silence hint '
    "appears when the input stays quiet",
    (tester) async {
      final recorder = _FakeRecorder();
      final ai = FakeAiRepository();
      addTearDown(ai.dispose);
      addTearDown(recorder.dispose);

      await tester.pumpWidget(_host(recorder, ai));
      await tester.pumpAndSettle();

      await _startRecording(tester, recorder);

      // Silence from the start: after the hint threshold passes, the user is
      // told their voice isn't being picked up instead of being left guessing.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining("Can't hear you yet"), findsOneWidget);

      // Speech arrives: the hint retires and the wave lifts off baseline.
      recorder.levels.add(0.9);
      await _flush(tester);
      expect(find.textContaining("Can't hear you yet"), findsNothing);

      final barFinder = find.descendant(
        of: find.byKey(const Key('composer-waveform')),
        matching: find.byType(AnimatedContainer),
      );
      final barCount = tester.widgetList(barFinder).length;
      expect(barCount, greaterThan(10));
      // At least one column visibly lifted toward full scale (level ≈ 0.9).
      var tallest = 0.0;
      for (var i = 0; i < barCount; i++) {
        final h = tester.getSize(barFinder.at(i)).height;
        if (h > tallest) tallest = h;
      }
      expect(tallest, greaterThan(15));

      await tester.tap(find.byKey(const Key('composer-cancel-recording')));
      await tester.pumpAndSettle();
      expect(recorder.cancelCalls, 1);
    },
  );

  testWidgets(
    'a denied microphone permission shows a toast and never starts recording',
    (tester) async {
      final recorder = _FakeRecorder()..permissionGranted = false;
      final ai = FakeAiRepository();
      addTearDown(ai.dispose);
      addTearDown(recorder.dispose);

      await tester.pumpWidget(_host(recorder, ai));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('composer-mic')));
      await tester.pumpAndSettle();

      expect(recorder.startCalls, 0);
      expect(recorder.isRecording, isFalse);
      expect(
        find.text('Turn on microphone access to use voice input.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('the cancel button discards the recording without transcribing', (
    tester,
  ) async {
    final recorder = _FakeRecorder();
    var transcribeCalls = 0;
    final ai = FakeAiRepository(
      transcribeImpl: (audioBytes, mimeType, languageHint) async {
        transcribeCalls++;
        return const SttTranscribed(text: 'should not appear');
      },
    );
    addTearDown(ai.dispose);
    addTearDown(recorder.dispose);

    await tester.pumpWidget(_host(recorder, ai));
    await tester.pumpAndSettle();

    await _startRecording(tester, recorder);
    expect(recorder.isRecording, isTrue);

    await tester.tap(find.byKey(const Key('composer-cancel-recording')));
    await tester.pumpAndSettle();

    expect(recorder.cancelCalls, 1);
    expect(transcribeCalls, 0);
    expect(find.byKey(const Key('composer-mic')), findsOneWidget);
    expect(find.text('should not appear'), findsNothing);
  });

  testWidgets(
    'a failed transcription shows a friendly toast, not the raw error',
    (tester) async {
      final recorder = _FakeRecorder()
        ..nextStopResult = RecordedAudio(
          bytes: Uint8List.fromList([1]),
          mimeType: 'audio/m4a',
        );
      final ai = FakeAiRepository(
        transcribeImpl: (audioBytes, mimeType, languageHint) async =>
            const SttFailed(
              SttError.audioTooLarge,
              'That recording is too long — try a shorter clip.',
            ),
      );
      addTearDown(ai.dispose);
      addTearDown(recorder.dispose);

      await tester.pumpWidget(_host(recorder, ai));
      await tester.pumpAndSettle();

      await _startRecording(tester, recorder);
      await tester.tap(find.byKey(const Key('composer-stop')));
      await tester.pumpAndSettle();

      expect(
        find.text('That recording is too long — try a shorter clip.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a hung transcription times out into a friendly failure and unlocks '
    'the composer',
    (tester) async {
      final recorder = _FakeRecorder()
        ..nextStopResult = RecordedAudio(
          bytes: Uint8List.fromList([1]),
          mimeType: 'audio/m4a',
        );
      final ai = FakeAiRepository(
        transcribeImpl: (audioBytes, mimeType, languageHint) =>
            Completer<SttOutcome>().future, // never completes
      );
      addTearDown(ai.dispose);
      addTearDown(recorder.dispose);

      await tester.pumpWidget(
        _host(recorder, ai, transcribeTimeout: const Duration(seconds: 2)),
      );
      await tester.pumpAndSettle();

      await _startRecording(tester, recorder);
      await tester.tap(find.byKey(const Key('composer-stop')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Transcribing…'), findsOneWidget);

      // Past the timeout: honest failure toast, composer back and usable
      // (extra pump lets the outgoing bar finish its exit transition).
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.text('That took too long — check your connection and try again.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('composer-mic')), findsOneWidget);
      expect(find.text('Transcribing…'), findsNothing);
    },
  );

  testWidgets(
    'cancelling mid-transcription discards the clip: a late transcript is '
    'ignored and nothing lands in the composer',
    (tester) async {
      final recorder = _FakeRecorder()
        ..nextStopResult = RecordedAudio(
          bytes: Uint8List.fromList([1]),
          mimeType: 'audio/m4a',
        );
      final completer = Completer<SttOutcome>();
      final ai = FakeAiRepository(
        transcribeImpl: (audioBytes, mimeType, languageHint) => completer.future,
      );
      addTearDown(ai.dispose);
      addTearDown(recorder.dispose);

      await tester.pumpWidget(_host(recorder, ai));
      await tester.pumpAndSettle();

      await _startRecording(tester, recorder);
      await tester.tap(find.byKey(const Key('composer-stop')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Transcribing…'), findsOneWidget);

      await tester.tap(find.byKey(const Key('composer-cancel-transcribing')));
      await _flush(tester);
      expect(find.text('Transcribing…'), findsNothing);
      expect(find.byKey(const Key('composer-mic')), findsOneWidget);

      // The server answers late — the user already moved on; it must be
      // dropped, not injected into the composer.
      completer.complete(const SttTranscribed(text: 'late transcript'));
      await tester.pumpAndSettle();
      expect(find.text('late transcript'), findsNothing);
    },
  );

  testWidgets(
    'a transcript typed into the composer sends unchanged via the existing ai.send path',
    (tester) async {
      final recorder = _FakeRecorder()
        ..nextStopResult = RecordedAudio(
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'audio/m4a',
        );
      final sentTexts = <String>[];
      final ai = FakeAiRepository(
        transcribeImpl: (audioBytes, mimeType, languageHint) async =>
            const SttTranscribed(text: 'log 12 EGP for coffee'),
      );
      addTearDown(ai.dispose);
      addTearDown(recorder.dispose);

      await tester.pumpWidget(_host(recorder, ai));
      await tester.pumpAndSettle();

      await _startRecording(tester, recorder);
      await tester.tap(find.byKey(const Key('composer-stop')));
      await tester.pumpAndSettle();

      final composerText = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text;
      expect(composerText, 'log 12 EGP for coffee');

      await tester.tap(find.byKey(const Key('composer-send')));
      await tester.pumpAndSettle();

      // The send lazily created the conversation (Phase A: nothing persists
      // until the first real message goes out) — there's exactly one.
      final conversations = await ai.watchConversations().first;
      final messages = await ai.watchMessages(conversations.single.id).first;
      sentTexts.addAll(messages.map((m) => m.content));
      expect(sentTexts, contains('log 12 EGP for coffee'));
    },
  );
}
