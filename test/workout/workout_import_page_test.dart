import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_repository.dart';
import 'package:zivo/features/ai/domain/import_cancellation.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/workout_import_input.dart';
import 'package:zivo/features/workout/domain/workout_import_outcome.dart';
import 'package:zivo/features/workout/domain/workout_import_result.dart';
import 'package:zivo/features/workout/presentation/pages/workout_import_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// An [AiRepository] whose `importWorkoutPlan` always throws — proves the
/// page's own error state (as opposed to the file-picker's). [error] defaults
/// to a generic failure; pass a specific one to exercise message classification
/// (e.g. an App Check rejection).
class _FailingImportAi extends FakeAiRepository {
  _FailingImportAi([this.error = 'extraction failed']);

  final Object error;

  @override
  Future<WorkoutImportOutcome> importWorkoutPlan(
    WorkoutImportInput input, {
    ImportCancellation? cancellation,
  }) {
    throw error is String ? StateError(error as String) : error;
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('open')));
}

/// Pumps a Home page under [ai]/[plans] and pushes [WorkoutImportPage]
/// (with [pickPdfBytes] as its file-picker override) via a real `Navigator`,
/// so `Navigator.pop()` inside the page is observable as Home reappearing.
Future<InMemoryWorkoutPlanRepository> _pumpImportPage(
  WidgetTester tester, {
  required Future<Uint8List?> Function() pickPdfBytes,
  AiRepository? ai,
  // The analysing screen runs a looping Lottie, so it never settles while an
  // import is still in flight. Tests that hold the import open pump frames
  // instead.
  bool settle = true,
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  final plans = InMemoryWorkoutPlanRepository();
  addTearDown(plans.dispose);
  await tester.pumpWidget(
    AppScope(
      auth: FakeAuthRepository(),
      profiles: FakeProfileRepository(),
      expenses: InMemoryExpenseRepository(),
      moments: InMemoryMomentRepository(),
      workouts: InMemoryWorkoutRepository(),
      workoutPlans: plans,
      workoutSessions: InMemoryWorkoutSessionRepository(),
      diet: InMemoryDietRepository(),
      ai: ai ?? FakeAiRepository(),
      child: MaterialApp(navigatorKey: navigatorKey, home: const _Home()),
    ),
  );
  navigatorKey.currentState!.push(
    MaterialPageRoute(
      builder: (_) => WorkoutImportPage(
        // Adapt the old bytes-only stub to the page's current pickFile seam.
        pickFile: () async {
          final bytes = await pickPdfBytes();
          if (bytes == null) return null;
          return (bytes: bytes, mimeType: 'application/pdf');
        },
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return plans;
}

/// An import that only resolves when [finish] is called, so a test can hold
/// the analysing screen up and inspect it — or press Cancel — while the
/// extraction is still in flight. Without the gate the call returns before a
/// single frame renders and there is nothing to look at.
class _StreamingImportAi extends FakeAiRepository {
  final _gate = Completer<void>();
  final _started = Completer<void>();

  ImportCancellation? _cancellation;
  int callCount = 0;
  final List<String> modelAtCall = [];

  Future<void> get started => _started.future;
  void finish() => _gate.complete();

  /// Whether the page propagated a cancel to the backend seam — the real
  /// signal that X/Cancel stops the work rather than only leaving the screen.
  bool get cancelled => _cancellation?.isCancelled ?? false;

  @override
  Future<WorkoutImportOutcome> importWorkoutPlan(
    WorkoutImportInput input, {
    ImportCancellation? cancellation,
  }) async {
    callCount++;
    modelAtCall.add(await getModelSelection());
    // Only the FIRST call gates — proves a mid-flight model switch cancels
    // it and dispatches a genuinely new one, rather than the badge tap being
    // a no-op. The second call (the switch's retry) resolves through the
    // ordinary canned sample so the flow can be observed reaching preview.
    if (callCount > 1) return super.importWorkoutPlan(input);

    _cancellation = cancellation;
    _started.complete();
    // Resolve on finish, OR abort the moment the page cancels — mirroring the
    // real repository, which throws [ImportCancelledException] once the stream
    // closes.
    await Future.any(<Future<void>>[
      _gate.future,
      if (cancellation != null) cancellation.whenCancelled,
    ]);
    if (cancellation != null && cancellation.isCancelled) {
      throw const ImportCancelledException();
    }
    return const WorkoutImportRejected('done');
  }
}

void main() {
  testWidgets('cancelling the picker pops back without an error', (
    tester,
  ) async {
    await _pumpImportPage(tester, pickPdfBytes: () async => null);

    // Back on Home — the import page popped itself, no error shown.
    expect(find.text('open'), findsOneWidget);
    expect(find.text('Import PDF'), findsNothing);
  });

  testWidgets('a picker failure shows the error state with a retry button', (
    tester,
  ) async {
    await _pumpImportPage(
      tester,
      pickPdfBytes: () async => throw StateError('boom'),
    );

    expect(find.text("Couldn't read that file."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  group('1. a valid workout PDF', () {
    testWidgets('lands on a review/preview of exactly what the AI extracted', (
      tester,
    ) async {
      await _pumpImportPage(
        tester,
        pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
        ai: FakeAiRepository(), // canned two-day sample, see fake_ai_repository.dart
      );

      expect(find.text('Review import'), findsOneWidget);
      expect(find.text('Imported Split'), findsOneWidget);
      expect(find.text('2 days · 2 exercises total'), findsOneWidget);
      expect(find.text('Day A · Push'), findsOneWidget);
      expect(find.text('Day B · Pull'), findsOneWidget);
      expect(find.text('Bench Press'), findsOneWidget);
      // Nothing has been saved yet — the preview is a review, not an import.
      expect(find.text('Import this split'), findsOneWidget);
    });

    testWidgets('Import this split saves the reviewed draft and shows Done', (
      tester,
    ) async {
      final plans = await _pumpImportPage(
        tester,
        pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
        ai: FakeAiRepository(),
      );

      await tester.tap(find.text('Import this split'));
      await tester.pumpAndSettle();

      expect(find.text('Import complete'), findsOneWidget);
      expect(find.textContaining('"Imported Split" added'), findsOneWidget);
      // InMemoryWorkoutPlanRepository always seeds one real split — this
      // asserts a NEW one was added alongside it, not a total from zero.
      final imported = plans.splits.where((p) => p.name == 'Imported Split');
      expect(imported, hasLength(1));
      expect(imported.single.days, hasLength(2));

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget); // back on Home
    });

    testWidgets(
      'Edit before importing opens the manual editor pre-filled, without saving first',
      (tester) async {
        final plans = await _pumpImportPage(
          tester,
          pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
          ai: FakeAiRepository(),
        );

        await tester.tap(find.text('Edit before importing'));
        await tester.pumpAndSettle();

        expect(
          find.text('Edit split'),
          findsOneWidget,
        ); // non-null initialPlan → "editing"
        final nameField = tester.widget<TextField>(
          find.byKey(const Key('plan-name-field')),
        );
        expect(nameField.controller!.text, 'Imported Split');
        // Reaching the editor is not itself an import — nothing NEW saved yet
        // (only the repository's pre-existing seed split is present).
        expect(plans.splits.where((p) => p.name == 'Imported Split'), isEmpty);
      },
    );

    testWidgets(
      "Choose a different file from the preview re-invokes the picker",
      (tester) async {
        var pickCount = 0;
        await _pumpImportPage(
          tester,
          pickPdfBytes: () async {
            pickCount++;
            return Uint8List.fromList([1, 2, 3]);
          },
          ai: FakeAiRepository(),
        );
        expect(pickCount, 1);
        expect(find.text('Review import'), findsOneWidget);

        await tester.tap(find.text('Choose a different file'));
        await tester.pumpAndSettle();

        expect(pickCount, 2);
      },
    );
  });

  group('2. a completely unrelated PDF', () {
    testWidgets(
      'is rejected with the AI\'s own specific reason, not imported',
      (tester) async {
        final plans = await _pumpImportPage(
          tester,
          pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
          ai: FakeAiRepository(
            importWorkoutPlanImpl: (_) async => const WorkoutImportRejected(
              'This looks like a grocery receipt, not a workout plan.',
            ),
          ),
        );

        expect(
          find.text("This doesn't look like a workout plan"),
          findsOneWidget,
        );
        expect(
          find.text('This looks like a grocery receipt, not a workout plan.'),
          findsOneWidget,
        );
        expect(find.text('Choose a different file'), findsOneWidget);
        expect(find.text('Build manually instead'), findsOneWidget);
        // No plan was ever saved for a rejected file — still just the
        // repository's pre-existing seed split, nothing new.
        expect(plans.splits, hasLength(1));
      },
    );

    testWidgets('Build manually instead opens a blank manual editor', (
      tester,
    ) async {
      await _pumpImportPage(
        tester,
        pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
        ai: FakeAiRepository(
          importWorkoutPlanImpl: (_) async =>
              const WorkoutImportRejected('Not a workout plan.'),
        ),
      );

      await tester.tap(find.text('Build manually instead'));
      await tester.pumpAndSettle();

      expect(
        find.text('New split'),
        findsOneWidget,
      ); // null initialPlan → "creating"
    });

    testWidgets(
      "Choose a different file from the rejected state re-invokes the picker",
      (tester) async {
        var pickCount = 0;
        await _pumpImportPage(
          tester,
          pickPdfBytes: () async {
            pickCount++;
            return Uint8List.fromList([1, 2, 3]);
          },
          ai: FakeAiRepository(
            importWorkoutPlanImpl: (_) async =>
                const WorkoutImportRejected('Not a workout plan.'),
          ),
        );
        expect(pickCount, 1);

        await tester.tap(find.text('Choose a different file'));
        await tester.pumpAndSettle();

        expect(pickCount, 2);
      },
    );
  });

  group('3. an incomplete workout PDF (partially extracted)', () {
    testWidgets(
      'a day with no exercises found is shown honestly, not hidden or invented',
      (tester) async {
        await _pumpImportPage(
          tester,
          pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
          ai: FakeAiRepository(
            importWorkoutPlanImpl: (_) async => const WorkoutImportAccepted(
              WorkoutImportResult(
                planName: 'Partial Split',
                days: [
                  ImportedDay(
                    slot: 'A',
                    label: 'Push',
                    exercises: [
                      ImportedExercise(
                        name: 'Bench Press',
                        sets: 3,
                        repsMin: 8,
                        repsMax: 8,
                        toFailure: false,
                      ),
                    ],
                  ),
                  ImportedDay(slot: 'B', label: 'Pull', exercises: []),
                ],
              ),
            ),
          ),
        );

        expect(find.text('Day B · Pull'), findsOneWidget);
        expect(find.text('No exercises found for this day.'), findsOneWidget);
      },
    );
  });

  group('4. an empty/corrupted/unreadable PDF', () {
    testWidgets('is rejected rather than producing an empty imported plan', (
      tester,
    ) async {
      final plans = await _pumpImportPage(
        tester,
        pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
        ai: FakeAiRepository(
          importWorkoutPlanImpl: (_) async => const WorkoutImportRejected(
            "This file doesn't contain enough valid workout data to create a training plan.",
          ),
        ),
      );

      expect(
        find.text(
          "This file doesn't contain enough valid workout data to create a training plan.",
        ),
        findsOneWidget,
      );
      expect(
        plans.splits,
        hasLength(1),
      ); // just the repository's pre-existing seed split
    });
  });

  group('5. a messy/unusually formatted but still valid workout PDF', () {
    testWidgets(
      'an odd but genuine extraction (to-failure, no weight/rest) still previews cleanly',
      (tester) async {
        await _pumpImportPage(
          tester,
          pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
          ai: FakeAiRepository(
            importWorkoutPlanImpl: (_) async => const WorkoutImportAccepted(
              WorkoutImportResult(
                planName: 'Handwritten Plan',
                days: [
                  ImportedDay(
                    slot: '1',
                    label: 'Full Body',
                    exercises: [
                      ImportedExercise(
                        name: 'Push-up',
                        sets: 4,
                        toFailure: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

        expect(find.text('Handwritten Plan'), findsOneWidget);
        expect(find.text('Day 1 · Full Body'), findsOneWidget);
        expect(find.text('Push-up'), findsOneWidget);
        expect(find.text('Import this split'), findsOneWidget);
      },
    );
  });

  testWidgets(
    'a generic import failure shows the error state, and retry re-invokes the picker',
    (tester) async {
      var pickCount = 0;
      await _pumpImportPage(
        tester,
        pickPdfBytes: () async {
          pickCount++;
          return Uint8List.fromList([1, 2, 3]);
        },
        ai: _FailingImportAi(),
      );

      expect(
        find.text(
          "Couldn't read that plan — try a clearer photo or PDF, or build the split manually.",
        ),
        findsOneWidget,
      );
      expect(pickCount, 1);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(pickCount, 2);
    },
  );

  testWidgets(
    'a bare "unauthenticated" rejection surfaces as an App-verification problem, not "sign in" '
    '(this callable never requires auth — see aiImportWorkoutPlan\'s own doc comment)',
    (tester) async {
      await _pumpImportPage(
        tester,
        pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
        // Mirrors Firebase's OWN generic App Check rejection message, which
        // does NOT contain the words "app check" — this is the real shape
        // that used to get misclassified as "you need to sign in".
        ai: _FailingImportAi(
          StateError('[firebase_functions/unauthenticated] Unauthenticated'),
        ),
      );

      expect(find.textContaining("verify itself"), findsOneWidget);
      expect(find.textContaining('signed in'), findsNothing);
    },
  );

  testWidgets(
    'an explicit App Check rejection surfaces the same App-verification message',
    (tester) async {
      await _pumpImportPage(
        tester,
        pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
        ai: _FailingImportAi(
          StateError(
            '[firebase_functions/unauthenticated] App Check token was rejected',
          ),
        ),
      );

      expect(find.textContaining("verify itself"), findsOneWidget);
      expect(
        find.text(
          "Couldn't read that plan — try a clearer photo or PDF, or build the split manually.",
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'the analysing screen shows the wait line and an actual Cancel while the '
    'import is in flight',
    (tester) async {
      final ai = _StreamingImportAi();
      await _pumpImportPage(
        tester,
        ai: ai,
        pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
        settle: false,
      );
      await ai.started;
      await tester.pump();

      // An import is a single opaque model call with no observable sub-steps,
      // so the screen sets the wait expectation rather than animating fake
      // progress. It stays put — a stalled import visibly stalls.
      expect(find.text('Analyzing your plan'), findsOneWidget);
      expect(find.text('This can take up to a minute'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      ai.finish();
      await tester.pump();
    },
  );

  testWidgets(
    'pressing Cancel during analysis propagates to the backend and returns home',
    (tester) async {
      final ai = _StreamingImportAi();
      await _pumpImportPage(
        tester,
        ai: ai,
        pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
        settle: false,
      );
      await ai.started;
      await tester.pump();

      // The analysing screen offers a Cancel that actually cancels.
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // The cancel reached the repository seam (in the real one this closes the
      // stream, firing the callable's signal so the model call aborts)…
      expect(ai.cancelled, isTrue);
      // …and the flow left the screen.
      expect(find.text('open'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping the model badge mid-flight cancels the run and switches model',
    (tester) async {
      final ai = _StreamingImportAi();
      await _pumpImportPage(
        tester,
        ai: ai,
        pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
        settle: false,
      );
      await ai.started;
      await tester.pump();

      // The badge names the model actually in flight, and is a real control
      // (a swap icon), not just a label.
      expect(find.text('Using Claude Sonnet'), findsOneWidget);
      expect(ai.callCount, 1);

      await tester.tap(find.byKey(const Key('import-model-badge')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The sheet's own model read resolving.
      await tester.pump();
      expect(find.byKey(const Key('sheet-model-gemini-flash')), findsOneWidget);

      await tester.tap(find.byKey(const Key('sheet-model-gemini-flash')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Refreshing the badge, cancelling the first attempt, re-picking the
      // file and dispatching a fresh extraction all chain through here.
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The first attempt was cancelled rather than left running for an
      // answer nobody would see…
      expect(ai.cancelled, isTrue);
      // …and a genuinely NEW attempt was dispatched — the tap wasn't a
      // no-op — using the model that was just picked.
      expect(ai.callCount, 2);
      expect(ai.modelAtCall, ['claude-sonnet', 'gemini-flash']);
    },
  );
}
