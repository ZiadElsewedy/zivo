import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/core/widgets/reactive_state_views.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
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
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_repository.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/pages/workout_plan_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A repository whose `watchActivePlan()` stream only emits when [emit]/[emitError]
/// is called, so tests can assert on the "waiting"/error states deterministically.
class _PendingWorkoutPlanRepository implements WorkoutPlanRepository {
  final StreamController<WorkoutPlan?> _controller = StreamController<WorkoutPlan?>.broadcast();
  final List<WorkoutPlan> saved = [];

  @override
  WorkoutPlan? get activePlan => null;

  @override
  Stream<WorkoutPlan?> watchActivePlan() => _controller.stream;

  @override
  Future<void> savePlan(WorkoutPlan plan) async {
    saved.add(plan);
    _controller.add(plan);
  }

  @override
  Future<void> deletePlan(String id) async {}

  void emit(WorkoutPlan? plan) => _controller.add(plan);

  void emitError(Object error) => _controller.addError(error);

  void dispose() => _controller.close();
}

Widget _wrap({required Widget child, required WorkoutPlanRepository plansOverride}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: plansOverride,
    workoutSessions: InMemoryWorkoutSessionRepository(),
    university: InMemoryUniversityRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

/// A compact 3-day cycle (cursor on Day A) — small enough that every browse card
/// fits the test viewport, and exercising a range target with a weight so the
/// P0 set formatter has something to render.
WorkoutPlan _compactPlan() => WorkoutPlan(
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
          id: 'e1',
          name: 'Bench Press',
          order: 0,
          muscleGroup: 'Chest',
          defaultRestSeconds: 120,
          sets: [
            PlannedSet(
              order: 0,
              repTarget: RepTarget.range(6, 8),
              restSeconds: 120,
              targetWeightKg: 60,
              type: SetType.working,
            ),
          ],
        ),
      ],
    ),
    WorkoutDay(
      id: 'b',
      slot: 'B',
      label: 'Pull',
      order: 1,
      exercises: [
        PlannedExercise(
          id: 'e2',
          name: 'Deadlift',
          order: 0,
          defaultRestSeconds: 180,
          sets: [
            PlannedSet(order: 0, repTarget: RepTarget.fixed(5), restSeconds: 180, type: SetType.working),
          ],
        ),
      ],
    ),
    WorkoutDay(
      id: 'c',
      slot: 'C',
      label: 'Legs',
      order: 2,
      exercises: [
        PlannedExercise(
          id: 'e3',
          name: 'Back Squat',
          order: 0,
          defaultRestSeconds: 150,
          sets: [
            PlannedSet(order: 0, repTarget: RepTarget.fixed(6), restSeconds: 150, type: SetType.working),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets('renders the up-next day with its exercises and set summaries', (tester) async {
    final plans = _PendingWorkoutPlanRepository();
    addTearDown(plans.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutPlanPage(), plansOverride: plans));
    plans.emit(_compactPlan());
    await tester.pump();

    // The cursor points at Day A (order 0) → Push is up next.
    expect(find.text('UP NEXT'), findsOneWidget);
    expect(find.text('Day A · Push'), findsWidgets); // today header + browse card
    expect(find.text('Bench Press'), findsOneWidget); // only the today section is expanded
    expect(find.text('Test Split'), findsOneWidget); // plan name

    // Sets are rendered through the P0 formatter (range reps + weight + rest).
    expect(find.textContaining('reps · 60kg · rest 2:00'), findsOneWidget);
  });

  testWidgets('browse section lists every day in the cycle and expands on tap', (tester) async {
    final plans = _PendingWorkoutPlanRepository();
    addTearDown(plans.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutPlanPage(), plansOverride: plans));
    plans.emit(_compactPlan());
    await tester.pump();

    // All three cycle days appear in the browse list.
    expect(find.text('Day B · Pull'), findsOneWidget);
    expect(find.text('Day C · Legs'), findsOneWidget);
    // The up-next day is marked in the browse list.
    expect(find.text('Next up'), findsOneWidget);

    // A collapsed browse day hides its exercises until tapped.
    expect(find.text('Deadlift'), findsNothing);
    await tester.tap(find.text('Day B · Pull'));
    await tester.pump();
    expect(find.text('Deadlift'), findsOneWidget);
  });

  testWidgets('shows a spinner while the plan stream is waiting', (tester) async {
    final plans = _PendingWorkoutPlanRepository();
    addTearDown(plans.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutPlanPage(), plansOverride: plans));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No workout plan yet.'), findsNothing);
  });

  testWidgets('shows the empty state once the plan stream settles with no data', (tester) async {
    final plans = _PendingWorkoutPlanRepository();
    addTearDown(plans.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutPlanPage(), plansOverride: plans));

    plans.emit(null);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No workout plan yet.'), findsOneWidget);
  });

  testWidgets('empty state offers a one-tap import of the ingested split', (tester) async {
    final plans = _PendingWorkoutPlanRepository();
    addTearDown(plans.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutPlanPage(), plansOverride: plans));
    plans.emit(null);
    await tester.pump();

    expect(find.text('Import my split'), findsOneWidget);
    await tester.tap(find.text('Import my split'));
    await tester.pump();

    // The ingested plan was written to storage, and the page reflects it.
    expect(plans.saved, hasLength(1));
    expect(plans.saved.single.id, 'ziad-arnold-split');
    expect(plans.saved.single.source, WorkoutPlanSource.pdf);
    expect(find.text('Import my split'), findsNothing); // now showing the plan
  });

  testWidgets('shows the error view when the plan stream errors', (tester) async {
    final plans = _PendingWorkoutPlanRepository();
    addTearDown(plans.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutPlanPage(), plansOverride: plans));

    plans.emitError(Exception('read denied'));
    await tester.pump();

    expect(find.byType(ErrorStateView), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No workout plan yet.'), findsNothing);
  });

  testWidgets('history is reachable from the AppBar action', (tester) async {
    final plans = InMemoryWorkoutPlanRepository();
    addTearDown(plans.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutPlanPage(), plansOverride: plans));
    await tester.pump();

    expect(find.byTooltip('History'), findsOneWidget);
    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();

    // The history page ("what I did") opens — its "Log workout" FAB is unique to
    // it and absent from the read-only plan view.
    expect(find.byTooltip('Log workout'), findsOneWidget);
  });
}
