import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_outcome.dart';
import 'package:zivo/features/workout/presentation/pages/exercise_analysis_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

Widget _wrap(InMemoryWorkoutSessionRepository sessions) => AppScope(
      auth: FakeAuthRepository(),
      profiles: FakeProfileRepository(),
      expenses: InMemoryExpenseRepository(),
      moments: InMemoryMomentRepository(),
      workouts: InMemoryWorkoutRepository(),
      workoutPlans: InMemoryWorkoutPlanRepository(),
      workoutSessions: sessions,
      bodyWeight: InMemoryBodyWeightRepository(),
      diet: InMemoryDietRepository(),
      ai: FakeAiRepository(),
      child: const MaterialApp(
        home: ExerciseAnalysisPage(
          exerciseId: 'incline',
          exerciseName: 'Incline DB Press',
        ),
      ),
    );

/// A real phone WIDTH (not a wide test canvas) so a `RenderFlex` overflow in a
/// session card's metric row would actually fail the test — with a tall height
/// so every lazily-built section still renders.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 5200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

LiveSession _session(String id, int daysAgo, List<LoggedSet> sets) {
  final at = DateTime.now().subtract(Duration(days: daysAgo));
  return LiveSession(
    id: id,
    planId: 'p1',
    dayId: 'day-a',
    dayLabel: 'Push',
    startedAt: at.subtract(const Duration(minutes: 45)),
    completedAt: at,
    status: SessionStatus.completed,
    exercises: [
      SessionExercise(
        id: 'incline',
        exerciseId: 'incline',
        name: 'Incline DB Press',
        muscleGroup: 'Chest',
        restSeconds: 90,
        sets: sets,
      ),
    ],
  );
}

LoggedSet _s(String id, {required int reps, required double weight}) => LoggedSet(
      id: id,
      target: const RepTarget.range(6, 8),
      actualReps: reps,
      actualWeightKg: weight,
      outcome: SetOutcome.completed,
    );

void main() {
  testWidgets('renders the coaching read, timeline, and session deltas',
      (tester) async {
    _useTallViewport(tester);
    final sessions = InMemoryWorkoutSessionRepository(seed: [
      _session('s1', 14, [_s('a', reps: 8, weight: 30)]),
      _session('s2', 7, [_s('a', reps: 8, weight: 35), _s('b', reps: 10, weight: 35)]),
      _session('s3', 1, [
        _s('a', reps: 7, weight: 40),
        _s('b', reps: 7, weight: 40),
        _s('c', reps: 6, weight: 37),
      ]),
    ]);
    await tester.pumpWidget(_wrap(sessions));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    // Header + the three-part coaching insight.
    expect(find.text('Incline DB Press'), findsWidgets);
    expect(find.text('WHAT HAPPENED'), findsOneWidget);
    expect(find.text('WHY IT MATTERS'), findsOneWidget);
    expect(find.text('DO THIS'), findsOneWidget);

    // The session timeline, newest first, with ordinals.
    expect(find.text('SESSION HISTORY'), findsOneWidget);
    expect(find.text('SESSION 3'), findsOneWidget);
    expect(find.text('SESSION 1'), findsOneWidget);

    // "Exactly what changed" — a delta strip per adjacent pair (2 here).
    expect(find.text('VS PREVIOUS SESSION'), findsNWidgets(2));

    // The intensity-first verdict surfaces as an "Improved" tone chip, and the
    // heavier session is flagged as a personal best.
    expect(find.text('Improved'), findsWidgets);
    expect(find.text('New PB'), findsWidgets);
  });

  testWidgets('an untrained exercise shows the empty state, not a crash',
      (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(_wrap(InMemoryWorkoutSessionRepository()));
    await tester.pump();
    expect(
      find.text('No completed sessions with this exercise yet.'),
      findsOneWidget,
    );
  });
}
