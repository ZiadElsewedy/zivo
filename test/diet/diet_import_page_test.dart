import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_import_outcome.dart';
import 'package:zivo/features/diet/domain/diet_import_result.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/domain/diet_import_input.dart';
import 'package:zivo/features/diet/presentation/pages/diet_import_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/ai/domain/import_progress.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// An [AiRepository] whose `importDietPlan` always throws — proves the
/// page's own error state (as opposed to the file-picker's). [error]
/// defaults to a generic failure; pass a specific one to exercise message
/// classification (e.g. an App Check rejection).
class _FailingImportAi extends FakeAiRepository {
  _FailingImportAi([this.error = 'extraction failed']);

  final Object error;

  @override
  Future<DietImportOutcome> importDietPlan(
    DietImportInput input, {
    void Function(ImportProgress progress)? onProgress,
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

/// Pumps a Home page under [ai]/[diet] and pushes [DietImportPage] (with
/// [pickPdfBytes] as its file-picker override) via a real `Navigator`, so
/// `Navigator.pop()` inside the page is observable as Home reappearing.
Future<InMemoryDietRepository> _pumpImportPage(
  WidgetTester tester, {
  required Future<Uint8List?> Function() pickPdfBytes,
  AiRepository? ai,
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  final diet = InMemoryDietRepository();
  addTearDown(diet.dispose);
  await tester.pumpWidget(
    AppScope(
      auth: FakeAuthRepository(),
      profiles: FakeProfileRepository(),
      expenses: InMemoryExpenseRepository(),
      moments: InMemoryMomentRepository(),
      workouts: InMemoryWorkoutRepository(),
      workoutPlans: InMemoryWorkoutPlanRepository(),
      workoutSessions: InMemoryWorkoutSessionRepository(),
      diet: diet,
      ai: ai ?? FakeAiRepository(),
      child: MaterialApp(navigatorKey: navigatorKey, home: const _Home()),
    ),
  );
  navigatorKey.currentState!.push(
    MaterialPageRoute(
      builder: (_) => DietImportPage(
        // Adapt the old bytes-only stub to the page's current pickFile seam.
        pickFile: () async {
          final bytes = await pickPdfBytes();
          if (bytes == null) return null;
          return (bytes: bytes, mimeType: 'application/pdf');
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return diet;
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

  group('1. a valid diet PDF', () {
    testWidgets(
      'lands directly in the plan editor, pre-filled with exactly what the AI extracted — nothing saved yet',
      (tester) async {
        final diet = await _pumpImportPage(
          tester,
          pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
          ai: FakeAiRepository(), // canned sample, see fake_ai_repository.dart
        );

        // The shared plan editor IS the review-and-save gate — no separate
        // preview screen.
        final nameField = tester.widget<TextField>(
          find.byType(TextField).first,
        );
        expect(nameField.controller!.text, 'Imported Plan');
        expect(find.text('Breakfast'), findsOneWidget);
        expect(find.textContaining('Oats'), findsOneWidget);
        expect(find.textContaining('Banana'), findsOneWidget);
        expect(find.text('Save plan'), findsOneWidget);

        // Nothing has been saved yet — reaching the editor isn't itself an
        // import. The repository's original seeded plan is still active.
        expect(diet.activePlan!.name, isNot('Imported Plan'));
      },
    );

    testWidgets(
      'saving inside the editor persists the plan (source preserved as pdf) and returns to Home',
      (tester) async {
        final diet = await _pumpImportPage(
          tester,
          pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
          ai: FakeAiRepository(),
        );

        await tester.tap(find.text('Save plan'));
        await tester.pumpAndSettle();

        // The editor's own Save pops it; the import page (awaiting that
        // push) then pops itself too, landing straight back on Home.
        expect(find.text('open'), findsOneWidget);
        expect(diet.activePlan!.name, 'Imported Plan');
        // Regression coverage for the fix this chunk needed: the editor used
        // to hardcode `source: DietSource.manual` on every save, silently
        // discarding the import draft's `DietSource.pdf` marker.
        expect(diet.activePlan!.source, DietSource.pdf);
      },
    );

    testWidgets(
      'an AI-estimated item shows the "~" marker on its calorie figure in the editor',
      (tester) async {
        await _pumpImportPage(
          tester,
          pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
          ai: FakeAiRepository(), // the canned sample marks Banana as estimated
        );

        expect(find.textContaining('~90 kcal'), findsOneWidget);
        // The stated (non-estimated) item shows a plain figure, no tilde.
        expect(find.textContaining('220 kcal'), findsOneWidget);
        expect(find.textContaining('~220 kcal'), findsNothing);
      },
    );
  });

  group('2. a completely unrelated PDF', () {
    testWidgets("is rejected with the AI's own specific reason, not imported", (
      tester,
    ) async {
      final diet = await _pumpImportPage(
        tester,
        pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
        ai: FakeAiRepository(
          importDietPlanImpl: (_) async => const DietImportRejected(
            'This looks like a workout plan, not a diet plan.',
          ),
        ),
      );

      expect(find.text("This doesn't look like a diet plan"), findsOneWidget);
      expect(
        find.text('This looks like a workout plan, not a diet plan.'),
        findsOneWidget,
      );
      expect(find.text('Choose a different file'), findsOneWidget);
      expect(find.text('Build manually instead'), findsOneWidget);
      // No plan was ever saved for a rejected file — still just the
      // repository's pre-existing seeded plan.
      expect(diet.activePlan!.name, isNot('Imported Plan'));
    });

    testWidgets('Build manually instead opens a blank manual editor', (
      tester,
    ) async {
      await _pumpImportPage(
        tester,
        pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
        ai: FakeAiRepository(
          importDietPlanImpl: (_) async =>
              const DietImportRejected('Not a diet plan.'),
        ),
      );

      await tester.tap(find.text('Build manually instead'));
      await tester.pumpAndSettle();

      final nameField = tester.widget<TextField>(find.byType(TextField).first);
      expect(nameField.controller!.text, isEmpty);
      expect(find.text('Save plan'), findsOneWidget);
    });

    testWidgets(
      'Choose a different file from the rejected state re-invokes the picker',
      (tester) async {
        var pickCount = 0;
        await _pumpImportPage(
          tester,
          pickPdfBytes: () async {
            pickCount++;
            return Uint8List.fromList([1, 2, 3]);
          },
          ai: FakeAiRepository(
            importDietPlanImpl: (_) async =>
                const DietImportRejected('Not a diet plan.'),
          ),
        );
        expect(pickCount, 1);

        await tester.tap(find.text('Choose a different file'));
        await tester.pumpAndSettle();

        expect(pickCount, 2);
      },
    );
  });

  group('3. an incomplete diet PDF (partially extracted)', () {
    testWidgets(
      'a meal with no items found is shown honestly, not hidden or invented',
      (tester) async {
        await _pumpImportPage(
          tester,
          pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
          ai: FakeAiRepository(
            importDietPlanImpl: (_) async => const DietImportAccepted(
              DietImportResult(
                planName: 'Partial Plan',
                days: [
                  ImportedDietDay(
                    weekday: null,
                    label: 'Every day',
                    meals: [
                      ImportedMeal(
                        label: 'Breakfast',
                        items: [
                          ImportedFoodItem(
                            name: 'Oats',
                            quantity: 60,
                            unit: 'g',
                            calories: 220,
                            proteinG: 8,
                            carbsG: 38,
                            fatG: 4,
                            estimated: false,
                          ),
                        ],
                      ),
                      ImportedMeal(label: 'Lunch', items: []),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

        expect(find.text('Lunch'), findsOneWidget);
        // No fabricated item under the empty meal.
        expect(find.textContaining('Oats'), findsOneWidget);
      },
    );
  });

  group('4. an empty/corrupted/unreadable PDF', () {
    testWidgets('is rejected rather than producing an empty imported plan', (
      tester,
    ) async {
      final diet = await _pumpImportPage(
        tester,
        pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
        ai: FakeAiRepository(
          importDietPlanImpl: (_) async => const DietImportRejected(
            "This file doesn't contain enough valid diet data to create a plan.",
          ),
        ),
      );

      expect(
        find.text(
          "This file doesn't contain enough valid diet data to create a plan.",
        ),
        findsOneWidget,
      );
      expect(diet.activePlan!.name, isNot('Imported Plan'));
    });
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
          "Couldn't read that plan — try a clearer photo or PDF, or build the plan manually.",
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
    "(this callable never requires auth — see aiImportDietPlan's own doc comment)",
    (tester) async {
      await _pumpImportPage(
        tester,
        pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
        ai: _FailingImportAi(
          StateError('[firebase_functions/unauthenticated] Unauthenticated'),
        ),
      );

      expect(find.textContaining('verify itself'), findsOneWidget);
      expect(find.textContaining('signed in'), findsNothing);
    },
  );
}
