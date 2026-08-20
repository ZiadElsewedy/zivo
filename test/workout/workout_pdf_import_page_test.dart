import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/domain/ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/workout_import_result.dart';
import 'package:zivo/features/workout/presentation/pages/workout_pdf_import_page.dart';

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
  Future<WorkoutImportResult> importWorkoutPlan({required Uint8List pdfBytes}) {
    throw error is String ? StateError(error as String) : error;
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('open')));
}

/// Pumps a Home page under [ai] and pushes [WorkoutPdfImportPage] (with
/// [pickPdfBytes] as its file-picker override) via a real `Navigator`, so
/// `Navigator.pop()` inside the page is observable as Home reappearing.
Future<void> _pumpImportPage(
  WidgetTester tester, {
  required Future<Uint8List?> Function() pickPdfBytes,
  AiRepository? ai,
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    AppScope(
      auth: FakeAuthRepository(),
      profiles: FakeProfileRepository(),
      expenses: InMemoryExpenseRepository(),
      tasks: InMemoryTaskRepository(),
      schedule: InMemoryScheduleRepository(),
      notes: InMemoryNoteRepository(),
      moments: InMemoryMomentRepository(),
      workouts: InMemoryWorkoutRepository(),
      workoutPlans: InMemoryWorkoutPlanRepository(),
      workoutSessions: InMemoryWorkoutSessionRepository(),
      university: InMemoryUniversityRepository(),
      diet: InMemoryDietRepository(),
      ai: ai ?? FakeAiRepository(),
      child: MaterialApp(navigatorKey: navigatorKey, home: const _Home()),
    ),
  );
  navigatorKey.currentState!.push(
    MaterialPageRoute(builder: (_) => WorkoutPdfImportPage(pickPdfBytes: pickPdfBytes)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cancelling the picker pops back without an error', (tester) async {
    await _pumpImportPage(tester, pickPdfBytes: () async => null);

    // Back on Home — the import page popped itself, no error shown.
    expect(find.text('open'), findsOneWidget);
    expect(find.text('Import PDF'), findsNothing);
  });

  testWidgets('a picker failure shows the error state with a retry button', (tester) async {
    await _pumpImportPage(tester, pickPdfBytes: () async => throw StateError('boom'));

    expect(find.text("Couldn't read that file."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a successful pick + import navigates to the split editor pre-filled', (tester) async {
    await _pumpImportPage(
      tester,
      pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
      ai: FakeAiRepository(), // canned two-day sample, see fake_ai_repository.dart
    );

    // Landed on the plan editor, pre-filled from the fake's canned import.
    expect(find.text('Edit split'), findsOneWidget); // non-null initialPlan → "editing"
    final nameField = tester.widget<TextField>(find.byKey(const Key('plan-name-field')));
    expect(nameField.controller!.text, 'Imported Split');
    expect(find.text('Day A · Push'), findsOneWidget);
  });

  testWidgets('an import failure shows the error state, and retry re-invokes the picker', (tester) async {
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
      find.text("Couldn't read that plan — try a clearer PDF, or build the split manually."),
      findsOneWidget,
    );
    expect(pickCount, 1);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(pickCount, 2);
  });

  testWidgets('an App Check rejection surfaces the App Check message, not "clearer PDF"', (tester) async {
    await _pumpImportPage(
      tester,
      pickPdfBytes: () async => Uint8List.fromList([1, 2, 3]),
      // Mirrors how a cloud_functions callable rejection stringifies.
      ai: _FailingImportAi(
        StateError('[firebase_functions/unauthenticated] App Check token was rejected'),
      ),
    );

    // The friendly line explains the real cause ("verify itself (App Check)")
    // instead of blaming the PDF.
    expect(find.textContaining("verify itself"), findsOneWidget);
    expect(
      find.text("Couldn't read that plan — try a clearer PDF, or build the split manually."),
      findsNothing,
    );
  });
}
