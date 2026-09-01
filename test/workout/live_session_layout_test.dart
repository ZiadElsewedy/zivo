import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/pages/live_session_page.dart';
import 'package:zivo/features/workout/presentation/widgets/live_session/phases/phase_scaffold.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';
import '../support/inert_music_controller.dart';

/// Where the logging screen's parts actually LAND — the complaint that
/// started this file was "the reps and weight are jammed at the bottom", and
/// "the screen lays out differently depending on whether music is playing".
///
/// Both came from the same thing: the hero cluster (goal card + steppers) had
/// a flexible gap only ABOVE it, so it hung off the bottom of whatever space
/// was left over, and the music companion — which takes a bar's height out of
/// that space when a track is playing — visibly moved the whole screen.
void main() {
  testWidgets(
    'the commit row is the compact 52, not the 60 the rest of the app uses — '
    'every point it takes comes out of the steppers above it',
    (tester) async {
      await _open(tester, const Size(402, 874));

      expect(
        tester.getSize(find.byKey(const Key('log-set'))).height,
        kCommitRowHeight,
      );
      expect(
        tester.getSize(find.byKey(const Key('skip-set'))).height,
        kCommitRowHeight,
      );
    },
  );

  testWidgets('the reps/weight cluster keeps real air above the commit row', (
    tester,
  ) async {
    await _open(tester, const Size(402, 874));

    expect(await _gapBelowSteppers(tester), greaterThan(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'spare height is shared ABOVE and BELOW the hero — so docking the music '
    'companion (which costs the phase a bar of height) shifts the screen '
    'gently instead of re-laying it out',
    (tester) async {
      await _open(tester, const Size(402, 874));
      final roomy = await _gapBelowSteppers(tester);

      // Docking the companion takes a bar's height out of the phase, exactly
      // as a shorter viewport does — resized rather than re-opened, so this
      // measures the same live screen the user is standing in front of.
      tester.view.physicalSize = const Size(402, 874 - 64) * 3;
      await tester.pump();
      final withDock = await _gapBelowSteppers(tester);

      expect(
        withDock,
        lessThan(roomy),
        reason: 'the gap absorbs the dock, rather than the content jumping',
      );
      expect(
        withDock,
        greaterThan(0),
        reason: 'and it does not collapse to nothing the moment music starts',
      );
      // The whole 64 is absorbed by the two gaps together, so neither one
      // takes the full hit: this gap moves by the smaller share of it.
      expect(roomy - withDock, lessThan(64));
    },
  );
}

/// The vertical space between the bottom of the weight stepper and the top of
/// the pinned commit row — the "are the inputs jammed against the button"
/// measurement.
Future<double> _gapBelowSteppers(WidgetTester tester) async {
  final steppers = tester.getRect(find.byType(TextField).last);
  final commit = tester.getRect(find.byKey(const Key('log-set')));
  return commit.top - steppers.bottom;
}

Future<void> _open(WidgetTester tester, Size logicalSize) async {
  tester.view.physicalSize = logicalSize * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
      music: InertMusicController(),
      child: MaterialApp(
        home: LiveSessionPage(day: _day(), plan: _plan()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  // A fresh session opens on the warm-up phase; skip it to reach the logging
  // screen the measurements are about.
  await tester.tap(find.text('Skip warm-up'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

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
      sets: [
        PlannedSet(
          order: 0,
          repTarget: RepTarget.fixed(5),
          restSeconds: 90,
          type: SetType.working,
        ),
        PlannedSet(
          order: 1,
          repTarget: RepTarget.fixed(5),
          restSeconds: 90,
          type: SetType.working,
        ),
      ],
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
