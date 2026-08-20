import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/capture/presentation/widgets/capture_widgets.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
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
import 'package:zivo/features/workout/presentation/pages/workout_plan_edit_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// §3.2 edit-identity lock: the plan editor drives `PlannedExercise.id`
/// deliberately — editing an exercise KEEPS its id (so logged history and
/// previous-weight stay linked to the same movement), while adding, or a
/// name-identical remove+re-add, MINTS a fresh id (a genuinely new movement
/// whose history starts clean). These tests pin that behavior through the real
/// UI so a future refactor can't silently regenerate ids on edit (which would
/// orphan history) or reuse them on replace (which would splice two movements'
/// history together).

class _RecordingWorkoutPlanRepository implements WorkoutPlanRepository {
  final List<WorkoutPlan> saved = [];
  final List<String> deleted = [];
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
  Future<void> deletePlan(String id) async {
    deleted.add(id);
    _active = null;
  }

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

/// A one-day plan with a single exercise `e1` (Bench Press) — the fixed
/// starting point for every identity check below.
WorkoutPlan _planWithBench() => WorkoutPlan(
  id: 'existing',
  name: 'PPL',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  cycleCursor: 0,
  days: const [
    WorkoutDay(
      id: 'd1',
      slot: 'A',
      label: 'Push',
      order: 0,
      exercises: [
        PlannedExercise(
          id: 'e1',
          name: 'Bench Press',
          order: 0,
          defaultRestSeconds: 120,
          sets: [
            PlannedSet(order: 0, repTarget: RepTarget.range(6, 8), restSeconds: 120, type: SetType.working),
          ],
        ),
      ],
    ),
  ],
);

Widget _wrap({required Widget child, required WorkoutPlanRepository plans}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: plans,
    workoutSessions: InMemoryWorkoutSessionRepository(),
    university: InMemoryUniversityRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

/// Expands a collapsed day tile by tapping its "Day {slot} · {label}" header.
Future<void> _expandDay(WidgetTester tester, String dayHeaderText) async {
  await tester.tap(find.text(dayHeaderText));
  await tester.pumpAndSettle();
}

Future<void> _savePlan(WidgetTester tester) async {
  await tester.ensureVisible(find.widgetWithText(PillButton, 'Save plan'));
  await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'editing an existing exercise KEEPS its PlannedExercise.id (history stays linked)',
    (tester) async {
      final plans = _RecordingWorkoutPlanRepository();
      await tester.pumpWidget(_wrap(child: WorkoutPlanEditPage(initialPlan: _planWithBench()), plans: plans));
      await tester.pump();
      await _expandDay(tester, 'Day A · Push');

      // Tap the exercise to edit it in place, rename it (a machine swap), save.
      await tester.tap(find.text('Bench Press'));
      await tester.pumpAndSettle();
      expect(find.text('Edit exercise'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('exercise-name-field')), 'Incline Bench Press');
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(PillButton, 'Save changes'));
      await tester.tap(find.widgetWithText(PillButton, 'Save changes'));
      await tester.pumpAndSettle();

      await _savePlan(tester);

      final exercises = plans.saved.single.days.single.exercises;
      expect(exercises, hasLength(1));
      final exercise = exercises.single;
      // Renamed, but the SAME id — an edit-in-place, not a new movement.
      expect(exercise.name, 'Incline Bench Press');
      expect(exercise.id, 'e1');
    },
  );

  testWidgets(
    'adding a new exercise MINTS a new id (distinct from every existing one)',
    (tester) async {
      final plans = _RecordingWorkoutPlanRepository();
      await tester.pumpWidget(_wrap(child: WorkoutPlanEditPage(initialPlan: _planWithBench()), plans: plans));
      await tester.pump();
      await _expandDay(tester, 'Day A · Push');

      // Add a second exercise to the day via the day's own "Add exercise".
      await tester.tap(find.text('Add exercise'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('exercise-name-field')), 'Overhead Press');
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(PillButton, 'Add exercise'));
      await tester.tap(find.widgetWithText(PillButton, 'Add exercise'));
      await tester.pumpAndSettle();

      await _savePlan(tester);

      final exercises = plans.saved.single.days.single.exercises;
      expect(exercises.map((e) => e.name), ['Bench Press', 'Overhead Press']);
      final added = exercises.firstWhere((e) => e.name == 'Overhead Press');
      // A freshly minted, non-empty id — not the existing exercise's id.
      expect(added.id, isNotEmpty);
      expect(added.id, isNot('e1'));
      // And every id in the day is still unique.
      final ids = exercises.map((e) => e.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    },
  );

  testWidgets(
    'a name-identical remove + re-add yields a NEW id (a fresh movement, history not spliced)',
    (tester) async {
      final plans = _RecordingWorkoutPlanRepository();
      await tester.pumpWidget(_wrap(child: WorkoutPlanEditPage(initialPlan: _planWithBench()), plans: plans));
      await tester.pump();
      await _expandDay(tester, 'Day A · Push');

      // Remove the existing Bench Press (id e1)...
      await tester.tap(find.byTooltip('Remove exercise'));
      await tester.pumpAndSettle();
      expect(find.text('Bench Press'), findsNothing);

      // ...then add a brand-new exercise with the SAME display name.
      await tester.tap(find.text('Add exercise'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('exercise-name-field')), 'Bench Press');
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(PillButton, 'Add exercise'));
      await tester.tap(find.widgetWithText(PillButton, 'Add exercise'));
      await tester.pumpAndSettle();

      await _savePlan(tester);

      final exercises = plans.saved.single.days.single.exercises;
      expect(exercises, hasLength(1));
      final rebuilt = exercises.single;
      expect(rebuilt.name, 'Bench Press'); // same name...
      expect(rebuilt.id, isNot('e1')); // ...but a genuinely new identity
      expect(rebuilt.id, isNotEmpty);
    },
  );
}
