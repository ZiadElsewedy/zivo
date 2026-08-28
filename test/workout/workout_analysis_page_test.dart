import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/theme/train_tokens.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/core/theme/app_colors.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/body_weight_entry.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_outcome.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_repository.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/pages/workout_analysis_page.dart';
import 'package:zivo/features/workout/presentation/widgets/trend_chart.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A fixed active plan, no async round-trip needed — the analysis page only
/// ever reads it.
class _FixedWorkoutPlanRepository implements WorkoutPlanRepository {
  _FixedWorkoutPlanRepository(this._plan);

  WorkoutPlan? _plan;
  final StreamController<WorkoutPlan?> _controller = StreamController<WorkoutPlan?>.broadcast();

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

Widget _wrap({
  required WorkoutPlan plan,
  required InMemoryWorkoutSessionRepository sessions,
  InMemoryBodyWeightRepository? bodyWeight,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: _FixedWorkoutPlanRepository(plan),
    workoutSessions: sessions,
    bodyWeight: bodyWeight,
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: const MaterialApp(home: WorkoutAnalysisPage()),
  );
}

/// Two days: A (Push, cursor's next) with one exercise, B (Pull) with one
/// exercise — small enough to fit the test viewport, enough to exercise the
/// day picker.
WorkoutPlan _plan() => WorkoutPlan(
  id: 'p1',
  name: 'Test Split',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  cycleCursor: 0,
  days: const [
    WorkoutDay(
      id: 'day-a',
      slot: 'A',
      label: 'Push',
      order: 0,
      exercises: [
        PlannedExercise(
          id: 'e1',
          name: 'Bench Press',
          order: 0,
          defaultRestSeconds: 90,
          sets: [PlannedSet(order: 0, repTarget: RepTarget.range(8, 10), restSeconds: 90, type: SetType.working)],
        ),
      ],
    ),
    WorkoutDay(
      id: 'day-b',
      slot: 'B',
      label: 'Pull',
      order: 1,
      exercises: [
        PlannedExercise(
          id: 'e2',
          name: 'Lat Pulldown',
          order: 0,
          defaultRestSeconds: 90,
          sets: [PlannedSet(order: 0, repTarget: RepTarget.range(8, 10), restSeconds: 90, type: SetType.working)],
        ),
      ],
    ),
  ],
);

/// The analysis page is a tall multi-section ListView (day chips, hero, basis
/// note, consistency row, weight snapshot, exercise list) — same trick
/// `workout_dashboard_page_test.dart` uses: a tall viewport so every section
/// actually gets built and is findable instead of staying off-screen.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

LiveSession _completedDayASession({required String id, required DateTime completedAt, required double weight}) =>
    LiveSession(
      id: id,
      planId: 'p1',
      dayId: 'day-a',
      dayLabel: 'Push',
      startedAt: completedAt.subtract(const Duration(minutes: 40)),
      completedAt: completedAt,
      status: SessionStatus.completed,
      exercises: [
        SessionExercise(
          id: 'e1',
          exerciseId: 'e1',
          name: 'Bench Press',
          restSeconds: 90,
          sets: [
            LoggedSet(
              id: 'e1-s0',
              target: RepTarget.range(8, 10),
              actualReps: 8,
              actualWeightKg: weight,
              outcome: SetOutcome.completed,
            ),
          ],
        ),
      ],
    );

void main() {
  testWidgets('no completed sessions → the day-empty state', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(
      _wrap(plan: _plan(), sessions: InMemoryWorkoutSessionRepository()),
    );
    await tester.pump();

    expect(find.text("You haven't logged Push yet."), findsOneWidget);
  });

  testWidgets('exactly one completed session → first-time nudge, no verdict yet', (tester) async {
    _useTallViewport(tester);
    final sessions = InMemoryWorkoutSessionRepository(
      seed: [_completedDayASession(id: 's1', completedAt: DateTime(2026, 2, 1), weight: 40)],
    );
    await tester.pumpWidget(_wrap(plan: _plan(), sessions: sessions));
    await tester.pump();

    expect(find.textContaining('Log Push once more'), findsOneWidget);
    expect(find.text('First time'), findsOneWidget);
    expect(find.text('Progressing'), findsNothing);
  });

  testWidgets('two completed sessions with weight increase → Progressing verdict shown', (tester) async {
    _useTallViewport(tester);
    final sessions = InMemoryWorkoutSessionRepository(
      seed: [
        _completedDayASession(id: 's1', completedAt: DateTime(2026, 2, 1), weight: 40),
        _completedDayASession(id: 's2', completedAt: DateTime(2026, 2, 8), weight: 45),
      ],
    );
    await tester.pumpWidget(_wrap(plan: _plan(), sessions: sessions));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700)); // let the trend chart's reveal animation settle

    // Day-level header + the exercise card both read "Progressing".
    expect(find.text('Progressing'), findsNWidgets(2));
    expect(find.textContaining('improved'), findsOneWidget);
  });

  testWidgets('switching the day picker re-scopes the analysis', (tester) async {
    _useTallViewport(tester);
    final sessions = InMemoryWorkoutSessionRepository(
      seed: [
        _completedDayASession(id: 's1', completedAt: DateTime(2026, 2, 1), weight: 40),
        _completedDayASession(id: 's2', completedAt: DateTime(2026, 2, 8), weight: 45),
      ],
    );
    await tester.pumpWidget(_wrap(plan: _plan(), sessions: sessions));
    await tester.pump();

    // Starts on Day A (the cursor's next day) with real progression data.
    expect(find.textContaining('improved'), findsOneWidget);

    await tester.tap(find.text('B · Pull'));
    await tester.pump();

    // Day B has no logged sessions at all.
    expect(find.text("You haven't logged Pull yet."), findsOneWidget);
  });

  testWidgets('a Down verdict tints the trend chart with the verdict-style red, not the default green', (
    tester,
  ) async {
    _useTallViewport(tester);
    final sessions = InMemoryWorkoutSessionRepository(
      seed: [
        _completedDayASession(id: 's1', completedAt: DateTime(2026, 2, 1), weight: 45),
        _completedDayASession(id: 's2', completedAt: DateTime(2026, 2, 8), weight: 40),
      ],
    );
    await tester.pumpWidget(_wrap(plan: _plan(), sessions: sessions));
    await tester.pump();

    // The day header reads "Slipping" (day-level wording); the exercise
    // badge reads "Down" (the shared verdictStyle word).
    expect(find.text('Down'), findsOneWidget);
    expect(find.text('Slipping'), findsOneWidget);
    final chart = tester.widget<TrendChart>(find.byType(TrendChart));
    expect(chart.color, TrainColors.ember);
  });

  testWidgets('the consistency row reflects real training-dashboard stats, not placeholders', (tester) async {
    _useTallViewport(tester);
    final today = DateTime.now();
    final sessions = InMemoryWorkoutSessionRepository(
      seed: [_completedDayASession(id: 's1', completedAt: today.subtract(const Duration(hours: 1)), weight: 40)],
    );
    await tester.pumpWidget(_wrap(plan: _plan(), sessions: sessions));
    await tester.pump();

    // Sessions this week AND the day streak both read 1 — trained today.
    expect(find.text('1'), findsNWidgets(2));
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Day streak'), findsOneWidget);
    expect(find.text('Avg length'), findsOneWidget);
  });

  testWidgets('the bodyweight snapshot shows the latest entry and is omitted with nothing logged', (tester) async {
    _useTallViewport(tester);
    final sessions = InMemoryWorkoutSessionRepository();

    // No bodyWeight repository at all — the snapshot row doesn't render.
    await tester.pumpWidget(_wrap(plan: _plan(), sessions: sessions));
    await tester.pump();
    expect(find.textContaining('kg'), findsNothing);

    // A repository with one entry — the snapshot shows the latest weight.
    final bodyWeight = InMemoryBodyWeightRepository(
      seed: [BodyWeightEntry(id: 'w1', weightKg: 82.5, loggedAt: DateTime.now())],
    );
    await tester.pumpWidget(_wrap(plan: _plan(), sessions: sessions, bodyWeight: bodyWeight));
    await tester.pump();
    expect(find.text('82.5 kg'), findsOneWidget);
  });

  testWidgets('the hero headline states the day verdict in plain language, backed by the counts', (tester) async {
    _useTallViewport(tester);
    final sessions = InMemoryWorkoutSessionRepository(
      seed: [
        _completedDayASession(id: 's1', completedAt: DateTime(2026, 2, 1), weight: 40),
        _completedDayASession(id: 's2', completedAt: DateTime(2026, 2, 8), weight: 45),
      ],
    );
    await tester.pumpWidget(_wrap(plan: _plan(), sessions: sessions));
    await tester.pump();

    expect(find.text('PUSH'), findsOneWidget); // uppercase day label above the headline
    expect(find.textContaining('1 improved · 0 matched · 0 regressed'), findsOneWidget);
  });

  testWidgets('a Progressing verdict keeps the trend chart green', (tester) async {
    _useTallViewport(tester);
    final sessions = InMemoryWorkoutSessionRepository(
      seed: [
        _completedDayASession(id: 's1', completedAt: DateTime(2026, 2, 1), weight: 40),
        _completedDayASession(id: 's2', completedAt: DateTime(2026, 2, 8), weight: 45),
      ],
    );
    await tester.pumpWidget(_wrap(plan: _plan(), sessions: sessions));
    await tester.pump();

    final chart = tester.widget<TrendChart>(find.byType(TrendChart));
    expect(chart.color, TrainColors.green);
  });
}
