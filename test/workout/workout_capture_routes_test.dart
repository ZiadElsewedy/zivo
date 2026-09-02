import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/audio_recorder.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/workout_import_input.dart';
import 'package:zivo/features/workout/domain/workout_import_outcome.dart';
import 'package:zivo/features/workout/presentation/pages/workout_describe_page.dart';
import 'package:zivo/features/workout/presentation/pages/workout_import_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A scriptable [AudioRecorderService]: no plugin, no real microphone.
class _FakeRecorder implements AudioRecorderService {
  bool permissionGranted = true;
  RecordedAudio? nextStopResult = RecordedAudio(
    bytes: Uint8List.fromList(const [1, 2, 3]),
    mimeType: 'audio/m4a',
  );
  int startCalls = 0;

  final StreamController<double> _levels = StreamController<double>.broadcast();

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
    isRecording = false;
    return nextStopResult;
  }

  @override
  Future<void> cancel() async => isRecording = false;

  @override
  Stream<double> inputLevels() => _levels.stream;

  void dispose() => _levels.close();
}

void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap({required Widget child, FakeAiRepository? ai, _FakeRecorder? recorder}) =>
    AppScope(
      auth: FakeAuthRepository(),
      profiles: FakeProfileRepository(),
      expenses: InMemoryExpenseRepository(),
      moments: InMemoryMomentRepository(),
      workouts: InMemoryWorkoutRepository(),
      workoutPlans: InMemoryWorkoutPlanRepository(),
      workoutSessions: InMemoryWorkoutSessionRepository(),
      diet: InMemoryDietRepository(),
      ai: ai ?? FakeAiRepository(),
      recorder: recorder,
      child: MaterialApp(home: child),
    );

void main() {
  group('typing a split', () {
    testWidgets(
      'the typed words reach the extractor as a description, not a file',
      (tester) async {
        _tallViewport(tester);
        WorkoutImportInput? sent;
        final ai = FakeAiRepository(
          importWorkoutPlanImpl: (input) async {
            sent = input;
            return const WorkoutImportRejected('done');
          },
        );

        await tester.pumpWidget(
          _wrap(
            child: const WorkoutDescribePage(startRecording: false),
            ai: ai,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('workout-describe-text')),
          'Day A is push — bench press 4 by 8, incline press 3 by 10.',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('workout-describe-extract')));
        await tester.pumpAndSettle();

        // The extractor got the typed words as a description — not a file, and
        // marked as typed (not dictated) so provenance stays honest.
        expect(sent, isA<WorkoutImportDescription>());
        final description = sent! as WorkoutImportDescription;
        expect(
          description.text,
          'Day A is push — bench press 4 by 8, incline press 3 by 10.',
        );
        expect(description.dictated, isFalse);
      },
    );

    testWidgets('extraction stays disabled until there is enough to read', (
      tester,
    ) async {
      _tallViewport(tester);

      await tester.pumpWidget(
        _wrap(child: const WorkoutDescribePage(startRecording: false)),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('workout-describe-text')),
        'legs',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('workout-describe-extract')));
      await tester.pumpAndSettle();

      // Still here — a four-character description has nothing in it for the
      // extractor, so the import page was never pushed.
      expect(find.byType(WorkoutDescribePage), findsOneWidget);
      expect(find.byType(WorkoutImportPage), findsNothing);
    });
  });

  group('dictation', () {
    testWidgets(
      'records, transcribes into an editable field, and extracts as dictated',
      (tester) async {
        _tallViewport(tester);
        final recorder = _FakeRecorder();
        addTearDown(recorder.dispose);
        WorkoutImportInput? sent;
        final ai = FakeAiRepository(
          importWorkoutPlanImpl: (input) async {
            sent = input;
            return const WorkoutImportRejected('done');
          },
        );

        await tester.pumpWidget(
          _wrap(
            child: const WorkoutDescribePage(),
            ai: ai,
            recorder: recorder,
          ),
        );
        await tester.pumpAndSettle();

        // The mic opened on its own.
        expect(recorder.startCalls, 1);
        expect(find.byKey(const Key('workout-describe-phase')), findsOneWidget);

        await tester.tap(find.byKey(const Key('workout-describe-stop')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // The transcript lands in an editable field — not straight into the
        // extractor.
        final field = tester.widget<TextField>(
          find.byKey(const Key('workout-describe-text')),
        );
        expect(field.controller!.text, isNotEmpty);
        expect(sent, isNull);

        await tester.tap(find.byKey(const Key('workout-describe-extract')));
        await tester.pumpAndSettle();

        expect(sent, isA<WorkoutImportDescription>());
        expect((sent! as WorkoutImportDescription).dictated, isTrue);
      },
    );
  });
}
