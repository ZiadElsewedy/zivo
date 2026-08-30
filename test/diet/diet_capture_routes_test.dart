import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/audio_recorder.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/domain/stt_error.dart';
import 'package:zivo/features/ai/domain/stt_outcome.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_import_input.dart';
import 'package:zivo/features/diet/domain/diet_import_outcome.dart';
import 'package:zivo/features/diet/domain/diet_import_result.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/presentation/pages/diet_dictate_page.dart';
import 'package:zivo/features/diet/presentation/pages/diet_import_page.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plan_edit_page.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plan_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

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
  int cancelCalls = 0;

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
  Future<void> cancel() async {
    cancelCalls++;
    isRecording = false;
  }

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

Widget _wrap({
  required Widget child,
  required InMemoryDietRepository diet,
  FakeAiRepository? ai,
  _FakeRecorder? recorder,
}) => AppScope(
  auth: FakeAuthRepository(),
  profiles: FakeProfileRepository(),
  expenses: InMemoryExpenseRepository(),
  moments: InMemoryMomentRepository(),
  workouts: InMemoryWorkoutRepository(),
  workoutPlans: InMemoryWorkoutPlanRepository(),
  workoutSessions: InMemoryWorkoutSessionRepository(),
  diet: diet,
  ai: ai ?? FakeAiRepository(),
  recorder: recorder,
  child: MaterialApp(home: child),
);

const _oneDayResult = DietImportResult(
  planName: 'What I eat',
  days: [
    ImportedDietDay(
      weekday: null,
      label: 'Every day',
      meals: [
        ImportedMeal(
          label: 'Breakfast',
          items: [
            ImportedFoodItem(
              name: 'Eggs',
              quantity: 3,
              unit: 'pcs',
              calories: 210,
              proteinG: 18,
              carbsG: 1,
              fatG: 15,
              estimated: true,
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  group('the add-a-diet sheet', () {
    testWidgets('offers every capture route in one place', (tester) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final recorder = _FakeRecorder();
      addTearDown(recorder.dispose);
      // The Diet screen shows the sheet's entry point only when nothing is
      // being followed.
      await diet.archivePlan(diet.activePlan!.id);

      await tester.pumpWidget(
        _wrap(child: const DietPlanPage(), diet: diet, recorder: recorder),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('diet-empty-add')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add-diet-document')), findsOneWidget);
      expect(find.byKey(const Key('add-diet-dictate')), findsOneWidget);
      expect(find.byKey(const Key('add-diet-type')), findsOneWidget);
      expect(find.byKey(const Key('add-diet-manual')), findsOneWidget);
    });

    testWidgets('hides dictation on a host with no recorder', (tester) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      await diet.archivePlan(diet.activePlan!.id);

      await tester.pumpWidget(_wrap(child: const DietPlanPage(), diet: diet));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('diet-empty-add')));
      await tester.pumpAndSettle();

      // Typing still works without a microphone — the route that can't work
      // is the only one that goes.
      expect(find.byKey(const Key('add-diet-dictate')), findsNothing);
      expect(find.byKey(const Key('add-diet-type')), findsOneWidget);
    });

    testWidgets('typing opens the description screen without the mic', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final recorder = _FakeRecorder();
      addTearDown(recorder.dispose);
      await diet.archivePlan(diet.activePlan!.id);

      await tester.pumpWidget(
        _wrap(child: const DietPlanPage(), diet: diet, recorder: recorder),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('diet-empty-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-diet-type')));
      await tester.pumpAndSettle();

      expect(find.byType(DietDictatePage), findsOneWidget);
      expect(recorder.startCalls, 0);
    });

    testWidgets('building by hand opens the editor', (tester) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      await diet.archivePlan(diet.activePlan!.id);

      await tester.pumpWidget(_wrap(child: const DietPlanPage(), diet: diet));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('diet-empty-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-diet-manual')));
      await tester.pumpAndSettle();

      expect(find.byType(DietPlanEditPage), findsOneWidget);
    });
  });

  group('dictation', () {
    testWidgets('records, transcribes, and shows the words for editing '
        'before anything is extracted', (tester) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final recorder = _FakeRecorder();
      addTearDown(recorder.dispose);
      var extractions = 0;
      final ai = FakeAiRepository(
        importDietPlanImpl: (_) async {
          extractions++;
          return const DietImportAccepted(_oneDayResult);
        },
      );

      await tester.pumpWidget(
        _wrap(child: const DietDictatePage(), diet: diet, ai: ai, recorder: recorder),
      );
      await tester.pumpAndSettle();

      expect(recorder.startCalls, 1);
      expect(find.byKey(const Key('dictate-phase')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dictate-stop')));
      // Bounded pumps, not pumpAndSettle: the transcribing state carries an
      // indeterminate progress bar, which never settles by design.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The transcript lands in an editable field — not straight into the
      // extractor. Nothing has been sent yet.
      final field = tester.widget<TextField>(
        find.byKey(const Key('dictate-text')),
      );
      expect(field.controller!.text, 'This is a placeholder transcript.');
      expect(extractions, 0);
    });

    testWidgets('a mis-heard transcript can be corrected before extraction', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final recorder = _FakeRecorder();
      addTearDown(recorder.dispose);
      DietImportInput? sent;
      final ai = FakeAiRepository(
        importDietPlanImpl: (input) async {
          sent = input;
          return const DietImportAccepted(_oneDayResult);
        },
      );

      await tester.pumpWidget(
        _wrap(child: const DietDictatePage(), diet: diet, ai: ai, recorder: recorder),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dictate-stop')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(
        find.byKey(const Key('dictate-text')),
        'Breakfast is three eggs and 60 grams of oats.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('dictate-extract')));
      await tester.pumpAndSettle();

      // The extractor gets the corrected words, as a description — not a file.
      expect(sent, isA<DietImportDescription>());
      final description = sent! as DietImportDescription;
      expect(description.text, 'Breakfast is three eggs and 60 grams of oats.');
      expect(description.dictated, isTrue);
    });

    testWidgets('extraction stays disabled until there is something to read', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);

      await tester.pumpWidget(
        _wrap(
          child: const DietDictatePage(startRecording: false),
          diet: diet,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('dictate-text')), 'eggs');
      await tester.pump();
      await tester.tap(find.byKey(const Key('dictate-extract')));
      await tester.pumpAndSettle();
      // Still here — a four-character description has nothing in it for the
      // extractor, and a rejection round-trip is a worse answer.
      expect(find.byType(DietDictatePage), findsOneWidget);
      expect(find.byType(DietImportPage), findsNothing);
    });

    testWidgets('a refused microphone falls back to typing, and says so', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final recorder = _FakeRecorder()..permissionGranted = false;
      addTearDown(recorder.dispose);

      await tester.pumpWidget(
        _wrap(child: const DietDictatePage(), diet: diet, recorder: recorder),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dictate-error')), findsOneWidget);
      expect(find.byKey(const Key('dictate-text')), findsOneWidget);
    });

    testWidgets('a failed transcription surfaces its reason', (tester) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final recorder = _FakeRecorder();
      addTearDown(recorder.dispose);
      final ai = FakeAiRepository(
        transcribeImpl: (_, _, _) async => const SttFailed(
          SttError.providerUnavailable,
          'Transcription is unavailable right now.',
        ),
      );

      await tester.pumpWidget(
        _wrap(child: const DietDictatePage(), diet: diet, ai: ai, recorder: recorder),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dictate-stop')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester.widget<Text>(find.byKey(const Key('dictate-error'))).data,
        'Transcription is unavailable right now.',
      );
    });
  });

  group('the import page', () {
    testWidgets('a supplied description skips the file picker entirely', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      var picked = false;
      final ai = FakeAiRepository(
        importDietPlanImpl: (_) async =>
            const DietImportAccepted(_oneDayResult),
      );

      await tester.pumpWidget(
        _wrap(
          child: DietImportPage(
            input: const DietImportDescription(
              text: 'Breakfast is three eggs.',
              dictated: true,
            ),
            pickFile: () async {
              picked = true;
              return null;
            },
          ),
          diet: diet,
          ai: ai,
        ),
      );
      await tester.pumpAndSettle();

      expect(picked, isFalse);
      // Straight to the review gate.
      expect(find.byType(DietPlanEditPage), findsOneWidget);
    });

    testWidgets('a dictated plan remembers that it was dictated', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final ai = FakeAiRepository(
        importDietPlanImpl: (_) async =>
            const DietImportAccepted(_oneDayResult),
      );

      await tester.pumpWidget(
        _wrap(
          child: DietImportPage(
            input: const DietImportDescription(
              text: 'Breakfast is three eggs.',
              dictated: true,
            ),
          ),
          diet: diet,
          ai: ai,
        ),
      );
      await tester.pumpAndSettle();

      final editor = tester.widget<DietPlanEditPage>(
        find.byType(DietPlanEditPage),
      );
      expect(editor.initialPlan!.source, DietSource.dictated);
      expect(dietSourceLabel(editor.initialPlan!.source), 'Dictated');
    });

    testWidgets('a typed plan is not passed off as dictated', (tester) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final ai = FakeAiRepository(
        importDietPlanImpl: (_) async =>
            const DietImportAccepted(_oneDayResult),
      );

      await tester.pumpWidget(
        _wrap(
          child: DietImportPage(
            input: const DietImportDescription(
              text: 'Breakfast is three eggs.',
              dictated: false,
            ),
          ),
          diet: diet,
          ai: ai,
        ),
      );
      await tester.pumpAndSettle();

      final editor = tester.widget<DietPlanEditPage>(
        find.byType(DietPlanEditPage),
      );
      expect(editor.initialPlan!.source, DietSource.manual);
    });

    testWidgets('a photo is recorded as a photo, not as a document', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final ai = FakeAiRepository(
        importDietPlanImpl: (_) async =>
            const DietImportAccepted(_oneDayResult),
      );

      await tester.pumpWidget(
        _wrap(
          child: DietImportPage(
            pickFile: () async => (
              bytes: Uint8List.fromList(const [1, 2, 3]),
              mimeType: 'image/jpeg',
            ),
          ),
          diet: diet,
          ai: ai,
        ),
      );
      await tester.pumpAndSettle();

      final editor = tester.widget<DietPlanEditPage>(
        find.byType(DietPlanEditPage),
      );
      expect(editor.initialPlan!.source, DietSource.photo);
    });
  });
}
