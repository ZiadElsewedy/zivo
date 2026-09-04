import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_outcome.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_repository.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/presentation/pages/workout_analysis_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// The engine-driven Progress page reads ONLY the session stream — the plan is
/// wired purely to satisfy [AppScope].
class _FixedWorkoutPlanRepository implements WorkoutPlanRepository {
  _FixedWorkoutPlanRepository(this._plan);

  WorkoutPlan? _plan;
  final StreamController<WorkoutPlan?> _controller =
      StreamController<WorkoutPlan?>.broadcast();

  @override
  WorkoutPlan? get activePlan => _plan;

  @override
  Stream<WorkoutPlan?> watchActivePlan() async* {
    yield _plan;
    yield* _controller.stream;
  }

  @override
  Future<void> savePlan(WorkoutPlan plan) async {
    _plan = plan;
    _controller.add(_plan);
  }

  @override
  Future<void> deletePlan(String id) async {}

  @override
  List<WorkoutPlan> get splits =>
      activePlan == null ? const <WorkoutPlan>[] : <WorkoutPlan>[activePlan!];

  @override
  Stream<List<WorkoutPlan>> watchSplits() => Stream.value(splits);

  @override
  String? get activeSplitId => activePlan?.id;

  @override
  Future<void> setActiveSplit(String id) async {}

  @override
  Future<void> saveSplit(WorkoutPlan plan) => savePlan(plan);

  @override
  Future<void> deleteSplit(String id) => deletePlan(id);
}

Widget _wrap(InMemoryWorkoutSessionRepository sessions) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: _FixedWorkoutPlanRepository(_plan()),
    workoutSessions: sessions,
    bodyWeight: InMemoryBodyWeightRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: const MaterialApp(home: WorkoutAnalysisPage()),
  );
}

WorkoutPlan _plan() => WorkoutPlan(
      id: 'p1',
      name: 'Test Split',
      status: WorkoutPlanStatus.active,
      source: WorkoutPlanSource.manual,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      cycleCursor: 0,
      days: const [],
    );

/// A tall viewport so every section of the ListView actually builds and is
/// findable (same trick as the dashboard page test).
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A completed Bench Press session [daysAgo] before now, one working set.
LiveSession _bench({
  required String id,
  required int daysAgo,
  required double weight,
  int reps = 8,
}) {
  final at = DateTime.now().subtract(Duration(days: daysAgo));
  return LiveSession(
    id: id,
    planId: 'p1',
    dayId: 'day-a',
    dayLabel: 'Push',
    startedAt: at.subtract(const Duration(minutes: 40)),
    completedAt: at,
    status: SessionStatus.completed,
    exercises: [
      SessionExercise(
        id: 'bench',
        exerciseId: 'bench',
        name: 'Bench Press',
        muscleGroup: 'Chest',
        restSeconds: 90,
        sets: [
          LoggedSet(
            id: '$id-s0',
            target: const RepTarget.range(6, 8),
            actualReps: reps,
            actualWeightKg: weight,
            outcome: SetOutcome.completed,
          ),
        ],
      ),
    ],
  );
}

void main() {
  testWidgets('no completed sessions → the empty hint, no fake verdict',
      (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(_wrap(InMemoryWorkoutSessionRepository()));
    await tester.pump();

    expect(find.text("Let's get started"), findsOneWidget);
    expect(
      find.text('Complete a few sessions to start tracking progress.'),
      findsOneWidget,
    );
    expect(find.text('RECENT PRS'), findsNothing);
  });

  testWidgets('two sessions → Building, never a direction from thin data',
      (tester) async {
    _useTallViewport(tester);
    final sessions = InMemoryWorkoutSessionRepository(seed: [
      _bench(id: 's1', daysAgo: 10, weight: 100),
      _bench(id: 's2', daysAgo: 3, weight: 105),
    ]);
    await tester.pumpWidget(_wrap(sessions));
    await tester.pump();

    // A thin-data lift isn't sorted into a coaching bucket — it's reachable in
    // the full, drill-in-able "All exercises" index, marked Building.
    expect(find.text('ALL EXERCISES'), findsOneWidget);
    expect(find.textContaining('Building'), findsOneWidget);
    expect(find.textContaining('Progressing'), findsNothing);
  });

  testWidgets('four progressing sessions → PRs surface and the lift reads '
      'Progressing', (tester) async {
    _useTallViewport(tester);
    final sessions = InMemoryWorkoutSessionRepository(seed: [
      _bench(id: 's1', daysAgo: 28, weight: 100),
      _bench(id: 's2', daysAgo: 21, weight: 102),
      _bench(id: 's3', daysAgo: 7, weight: 108),
      _bench(id: 's4', daysAgo: 1, weight: 110),
    ]);
    await tester.pumpWidget(_wrap(sessions));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('RECENT PRS'), findsOneWidget);
    expect(find.textContaining('Bench Press'), findsWidgets);
    expect(find.textContaining('Progressing'), findsWidgets);
    // The improving lift is pulled into its own coaching section, too.
    expect(find.text("WHAT'S GOING WELL"), findsOneWidget);
    expect(find.text('FOCUS NEXT'), findsOneWidget);
  });

  testWidgets('a sustained decline reads as Trending down', (tester) async {
    _useTallViewport(tester);
    final sessions = InMemoryWorkoutSessionRepository(seed: [
      _bench(id: 's1', daysAgo: 28, weight: 110),
      _bench(id: 's2', daysAgo: 21, weight: 108),
      _bench(id: 's3', daysAgo: 7, weight: 100),
      _bench(id: 's4', daysAgo: 1, weight: 98),
    ]);
    await tester.pumpWidget(_wrap(sessions));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.textContaining('Trending down'), findsWidgets);
    expect(find.text("WHAT'S GETTING WORSE"), findsOneWidget);
  });
}
