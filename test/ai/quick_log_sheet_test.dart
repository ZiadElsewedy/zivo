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
import 'package:zivo/features/ai/presentation/widgets/quick_log_sheet.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A scriptable [AudioRecorderService] fake — mirrors the one in
/// `ask_page_mic_test.dart`: no plugin, no real microphone.
class _FakeRecorder implements AudioRecorderService {
  bool permissionGranted = true;
  RecordedAudio? nextStopResult;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

  final StreamController<double> _levelController =
      StreamController<double>.broadcast();

  @override
  bool isRecording = false;

  void dispose() => _levelController.close();

  @override
  Future<bool> ensurePermission() async => permissionGranted;

  @override
  Future<void> start() async {
    startCalls++;
    // ignore: avoid_print
    print('FAKE START on $hashCode count=$startCalls');
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
}

Widget _host(
  _FakeRecorder recorder,
  FakeAiRepository ai,
  ValueChanged<String?> onResult,
) =>
    AppScope(
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
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result = await showQuickLogSheet(context);
                  onResult(result);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The recording state loops its pulse animation — never `pumpAndSettle`
/// while it is up; pump fixed time instead.
Future<void> _flush(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}


/// Runs the sheet's await-chains on the REAL event loop for a beat — the
/// modal route's futures don't otherwise resume under fake-async pumps.
Future<void> _drain(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pump();
}

void main() {
  testWidgets('record → stop lands the transcript as the sheet result', (
    tester,
  ) async {
    final recorder = _FakeRecorder()
      ..nextStopResult = RecordedAudio(
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'audio/m4a',
      );
    final ai = FakeAiRepository(
      transcribeImpl: (audioBytes, mimeType, languageHint) async =>
          const SttTranscribed(text: 'add 40 EGP parking'),
    );
    addTearDown(ai.dispose);

    String? result;
    await tester.pumpWidget(_host(recorder, ai, (r) => result = r));
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('quicklog-mic')));
    await _flush(tester);
    expect(find.byKey(const Key('quicklog-stop')), findsOneWidget);

    await tester.tap(find.byKey(const Key('quicklog-stop')));
    await _drain(tester);
    await tester.pumpAndSettle();

    expect(recorder.startCalls, 1);
    expect(recorder.stopCalls, 1);
    expect(result, 'add 40 EGP parking');
  });

  testWidgets('a failed transcription shows an honest error with retry', (
    tester,
  ) async {
    final recorder = _FakeRecorder()
      ..nextStopResult = RecordedAudio(
        bytes: Uint8List.fromList([1]),
        mimeType: 'audio/m4a',
      );
    final ai = FakeAiRepository(
      transcribeImpl: (audioBytes, mimeType, languageHint) async =>
          const SttFailed(SttError.unknown, "Couldn't transcribe that."),
    );
    addTearDown(ai.dispose);

    String? result;
    await tester.pumpWidget(_host(recorder, ai, (r) => result = r));
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('quicklog-mic')));
    await _flush(tester);
    await _drain(tester);
    await tester.tap(find.byKey(const Key('quicklog-stop')));
    await _drain(tester);
    await tester.pumpAndSettle();

    expect(find.text("Couldn't transcribe that."), findsOneWidget);
    expect(result, isNull);

    // Retry returns to the idle mic without a stray write.
    await tester.tap(find.byKey(const Key('quicklog-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quicklog-mic')), findsOneWidget);
  });

  testWidgets('cancelling mid-recording discards the clip and stays open', (
    tester,
  ) async {
    final recorder = _FakeRecorder();
    final ai = FakeAiRepository();
    addTearDown(ai.dispose);

    String? result;
    await tester.pumpWidget(_host(recorder, ai, (r) => result = r));
    await _openSheet(tester);

    await tester.tap(find.byKey(const Key('quicklog-mic')));
    await _flush(tester);
    await _drain(tester);
    await tester.tap(find.byKey(const Key('quicklog-cancel')));
    await _drain(tester);
    await tester.pumpAndSettle();

    expect(recorder.cancelCalls, 1);
    expect(recorder.stopCalls, 0);
    expect(find.byKey(const Key('quicklog-mic')), findsOneWidget);
    expect(result, isNull);
  });

  testWidgets('AskPage consumes an incoming draft into the composer', (
    tester,
  ) async {
    final ai = FakeAiRepository();
    addTearDown(ai.dispose);
    final draft = ValueNotifier<String?>(null);
    addTearDown(draft.dispose);

    await tester.pumpWidget(
      AppScope(
        auth: FakeAuthRepository(),
        profiles: FakeProfileRepository(),
        expenses: InMemoryExpenseRepository(),
        moments: InMemoryMomentRepository(),
        workouts: InMemoryWorkoutRepository(),
        workoutPlans: InMemoryWorkoutPlanRepository(),
        workoutSessions: InMemoryWorkoutSessionRepository(),
        diet: InMemoryDietRepository(),
        ai: ai,
        child: MaterialApp(home: AskPage(incomingDraft: draft)),
      ),
    );
    await tester.pumpAndSettle();

    draft.value = 'add 40 EGP parking';
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'add 40 EGP parking');
    // One-shot consumption: the notifier resets so the next log re-triggers.
    expect(draft.value, isNull);
  });
}
