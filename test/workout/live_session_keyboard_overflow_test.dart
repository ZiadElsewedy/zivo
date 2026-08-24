import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/pages/live_session_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// R3: does the running-set screen (Reps/Weight steppers) overflow when the
/// on-screen keyboard opens on a short device? Simulated here — rather than
/// on a simulator — via `tester.view.viewInsets` (what `MediaQuery.viewInsets`
/// actually reflects when a real keyboard is showing) combined with a short
/// physical size, then asserting `tester.takeException()` is null: a
/// `RenderFlex` overflow throws a `FlutterError` that surfaces exactly there.
WorkoutDay _day() => const WorkoutDay(
  id: 'a',
  slot: 'A',
  label: 'Push',
  order: 0,
  exercises: [
    PlannedExercise(
      id: 'ex1',
      name: 'Bench Press',
      order: 0,
      muscleGroup: 'Chest',
      defaultRestSeconds: 90,
      sets: [PlannedSet(order: 0, repTarget: RepTarget.fixed(5), restSeconds: 90, type: SetType.working)],
    ),
  ],
);

WorkoutPlan _plan() => WorkoutPlan(
  id: 'p1',
  name: 'Test Split',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  cycleCursor: 0,
  days: [_day()],
);

Future<void> _runAt(WidgetTester tester, {required Size size, required double keyboardHeight}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);

  final plans = InMemoryWorkoutPlanRepository();
  addTearDown(plans.dispose);
  await plans.savePlan(_plan());

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
      ai: FakeAiRepository(),
      child: MaterialApp(
        home: LiveSessionPage(day: _day(), plan: _plan()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  // A fresh session opens on the pre-workout warm-up phase; skip it to
  // reach the running-set screen with the Reps/Weight steppers. On an
  // extreme viewport the button can be scrolled below the fold (by design
  // — see the class doc), so scroll it into view first rather than tapping
  // blind.
  if (find.text('Skip warm-up').evaluate().isNotEmpty) {
    await tester.ensureVisible(find.text('Skip warm-up'));
    await tester.pump();
    await tester.tap(find.text('Skip warm-up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  expect(find.byType(TextField), findsNWidgets(2)); // Reps + Weight steppers

  // Tap the weight stepper's TextField to bring focus (the keyboard inset
  // is already simulated above; this exercises the actual input path, not
  // just a static layout). Scroll it into view first — on the extreme
  // viewport it can be below the fold, by design.
  await tester.ensureVisible(find.byType(TextField).last);
  await tester.pump();
  await tester.tap(find.byType(TextField).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350)); // let the punch-scale animation settle
}

void main() {
  testWidgets(
    'the running-set screen does not overflow on an iPhone-SE-class device with the keyboard open',
    (tester) async {
      await _runAt(tester, size: const Size(750, 1334), keyboardHeight: 600);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the running-set screen does not overflow on an EXTREME short viewport with a large keyboard '
    '(stress case beyond any real device, to rule out edge-case IntrinsicHeight/Spacer failures)',
    (tester) async {
      await _runAt(tester, size: const Size(640, 480), keyboardHeight: 340);
      expect(tester.takeException(), isNull);
    },
  );
}
