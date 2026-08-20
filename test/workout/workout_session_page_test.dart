import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_repository.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/workout_repository.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/pages/workout_session_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// Records what the player writes, so tests can assert the completion path
/// persists and the discard path writes nothing.
class _RecordingWorkoutRepository implements WorkoutRepository {
  final List<Workout> added = [];

  @override
  List<Workout> get current => added;

  @override
  Stream<List<Workout>> watchAll() => Stream.value(added);

  @override
  Future<void> add(Workout workout) async => added.add(workout);

  @override
  Future<void> update(Workout workout) async {}

  @override
  Future<void> remove(String id) async {}
}

class _RecordingWorkoutPlanRepository implements WorkoutPlanRepository {
  final List<WorkoutPlan> saved = [];
  WorkoutPlan? _active;

  @override
  WorkoutPlan? get activePlan => _active;

  @override
  Stream<WorkoutPlan?> watchActivePlan() => Stream.value(_active);

  @override
  Future<void> savePlan(WorkoutPlan plan) async {
    saved.add(plan);
    _active = plan;
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
      id: 'a',
      slot: 'A',
      label: 'Push',
      order: 0,
      exercises: [
        PlannedExercise(
          id: 'ex1',
          name: 'Bench',
          order: 0,
          muscleGroup: 'Chest',
          defaultRestSeconds: 90,
          sets: [
            PlannedSet(order: 0, repTarget: RepTarget.fixed(5), restSeconds: 90, type: SetType.working),
            PlannedSet(order: 1, repTarget: RepTarget.fixed(5), restSeconds: 60, type: SetType.working),
          ],
        ),
      ],
    ),
    WorkoutDay(id: 'b', slot: 'B', label: 'Pull', order: 1, exercises: []),
  ],
);

Widget _wrap({
  required WorkoutRepository workouts,
  required WorkoutPlanRepository workoutPlans,
  required WorkoutDay day,
  required WorkoutPlan plan,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: workouts,
    workoutPlans: workoutPlans,
    workoutSessions: InMemoryWorkoutSessionRepository(),
    university: InMemoryUniversityRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => WorkoutSessionPage(day: day, plan: plan)),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('happy path: start → done → rest (±15s) → skip → complete → finish persists + advances',
      (tester) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(workouts: workouts, workoutPlans: plans, day: plan.days.first, plan: plan),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Set 1 of the first exercise.
    expect(find.text('Set 1 of 2'), findsOneWidget);
    expect(find.text('Bench'), findsOneWidget);

    // Complete set 1 → rest countdown (90s → "1:30").
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Skip rest'), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);
    expect(find.textContaining('Next:'), findsOneWidget);

    // Adjust the rest window.
    await tester.tap(find.text('+15s'));
    await tester.pump();
    expect(find.text('1:45'), findsOneWidget);
    await tester.tap(find.text('-15s'));
    await tester.pump();
    expect(find.text('1:30'), findsOneWidget);

    // Skip the rest → set 2.
    await tester.tap(find.text('Skip rest'));
    await tester.pump();
    expect(find.text('Set 2 of 2'), findsOneWidget);
    expect(find.text('READY FOR SET 2'), findsOneWidget);

    // Complete the final set → completed summary.
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Finish'), findsOneWidget);
    expect(find.textContaining('2 of 2 sets'), findsOneWidget);

    // Finish → history written + cursor advanced, then popped back to launcher.
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(find.text('go'), findsOneWidget); // popped
    expect(workouts.added, hasLength(1));
    expect(workouts.added.single.title, 'Push');
    expect(plans.saved, hasLength(1));
    expect(plans.saved.single.cycleCursor, 1); // advanced 0 → 1
  });

  testWidgets('discard via the close button writes nothing and pops', (tester) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(workouts: workouts, workoutPlans: plans, day: plan.days.first, plan: plan),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Log nothing; hit close.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this workout?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('go'), findsOneWidget); // popped
    expect(workouts.added, isEmpty);
    expect(plans.saved, isEmpty);
  });

  testWidgets('the rest countdown auto-advances to the next set when it reaches zero',
      (tester) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(workouts: workouts, workoutPlans: plans, day: plan.days.first, plan: plan),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('1:30'), findsOneWidget);

    // Let the countdown run out.
    await tester.pump(const Duration(seconds: 91));
    expect(find.text('Set 2 of 2'), findsOneWidget);
  });
}
