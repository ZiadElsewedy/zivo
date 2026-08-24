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
class _FakeRecorder implements AudioRecorderService {
  bool permissionGranted = true;
  RecordedAudio? nextStopResult;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

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
}

Widget _host(_FakeRecorder recorder, FakeAiRepository ai) => AppScope(
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
  child: const MaterialApp(home: AskPage()),
);

void main() {
  testWidgets(
    'tapping the mic starts recording, tapping again stops it and drops the '
    'transcript into the composer without sending it',
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

      await tester.pumpWidget(_host(recorder, ai));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pumpAndSettle();

      expect(recorder.startCalls, 1);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(find.text('Recording…'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pumpAndSettle();

      expect(recorder.stopCalls, 1);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
      expect(find.text('What is due this week?'), findsOneWidget);
      // The transcript is in the composer for editing — not sent yet.
      expect(find.text("Hey, I'm ZIVO."), findsOneWidget);
    },
  );

  testWidgets(
    'a denied microphone permission shows a toast and never starts recording',
    (tester) async {
      final recorder = _FakeRecorder()..permissionGranted = false;
      final ai = FakeAiRepository();
      addTearDown(ai.dispose);

      await tester.pumpWidget(_host(recorder, ai));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_none_rounded));
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

    await tester.pumpWidget(_host(recorder, ai));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pumpAndSettle();
    expect(recorder.isRecording, isTrue);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(recorder.cancelCalls, 1);
    expect(transcribeCalls, 0);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
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

      await tester.pumpWidget(_host(recorder, ai));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pumpAndSettle();

      expect(
        find.text('That recording is too long — try a shorter clip.'),
        findsOneWidget,
      );
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

      await tester.pumpWidget(_host(recorder, ai));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pumpAndSettle();

      final composerText = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text;
      expect(composerText, 'log 12 EGP for coffee');

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      // The send lazily created the conversation (Phase A: nothing persists
      // until the first real message goes out) — there's exactly one.
      final conversations = await ai.watchConversations().first;
      final messages = await ai
          .watchMessages(conversations.single.id)
          .first;
      sentTexts.addAll(messages.map((m) => m.content));
      expect(sentTexts, contains('log 12 EGP for coffee'));
    },
  );
}
