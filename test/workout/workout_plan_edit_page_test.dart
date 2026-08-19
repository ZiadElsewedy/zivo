import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
}

WorkoutPlan _existingPlan() => WorkoutPlan(
  id: 'existing',
  name: 'PPL',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  cycleCursor: 1,
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
    WorkoutDay(id: 'd2', slot: 'B', label: 'Pull', order: 1, exercises: []),
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

void main() {
  testWidgets('create flow: name + day + exercise (compact set spec) → savePlan', (tester) async {
    final plans = _RecordingWorkoutPlanRepository();

    await tester.pumpWidget(_wrap(child: const WorkoutPlanEditPage(), plans: plans));
    await tester.pump();

    // Name the plan.
    await tester.enterText(find.byKey(const Key('plan-name-field')), 'My Split');
    await tester.pump();

    // Add a day: slot pre-filled "A", enter the label.
    await tester.tap(find.text('Add day'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('day-label-field')), 'Push');
    await tester.pump(); // rebuild so the submit button enables
    await tester.ensureVisible(find.widgetWithText(PillButton, 'Add day'));
    await tester.tap(find.widgetWithText(PillButton, 'Add day')); // sheet submit
    await tester.pumpAndSettle();
    expect(find.text('Day A · Push'), findsOneWidget);

    // Add an exercise with the default set spec (3 sets, range 8–12, rest 90).
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('exercise-name-field')), 'Bench Press');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(PillButton, 'Add exercise'));
    await tester.tap(find.widgetWithText(PillButton, 'Add exercise')); // sheet submit
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsOneWidget);

    // Save.
    await tester.ensureVisible(find.widgetWithText(PillButton, 'Save plan'));
    await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
    await tester.pumpAndSettle();

    expect(plans.saved, hasLength(1));
    final plan = plans.saved.single;
    expect(plan.name, 'My Split');
    expect(plan.days, hasLength(1));
    final day = plan.days.single;
    expect(day.slot, 'A');
    expect(day.label, 'Push');
    expect(day.order, 0);
    expect(day.exercises, hasLength(1));
    final exercise = day.exercises.single;
    expect(exercise.name, 'Bench Press');
    // The compact spec expanded into 3 identical working sets.
    expect(exercise.sets, hasLength(3));
    expect(exercise.sets.every((s) => s.repTarget == const RepTarget.range(8, 12)), isTrue);
    expect(exercise.sets.every((s) => s.type == SetType.working), isTrue);
    expect(exercise.sets.map((s) => s.order), [0, 1, 2]);
  });

  testWidgets('to-failure rep mode generates to-failure sets', (tester) async {
    final plans = _RecordingWorkoutPlanRepository();

    await tester.pumpWidget(_wrap(child: const WorkoutPlanEditPage(), plans: plans));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('plan-name-field')), 'S');

    await tester.tap(find.text('Add day'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('day-label-field')), 'Arms');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(PillButton, 'Add day'));
    await tester.tap(find.widgetWithText(PillButton, 'Add day'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('exercise-name-field')), 'Curl');
    await tester.pump();
    await tester.tap(find.text('To failure')); // switch rep mode
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(PillButton, 'Add exercise'));
    await tester.tap(find.widgetWithText(PillButton, 'Add exercise'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
    await tester.pumpAndSettle();

    final exercise = plans.saved.single.days.single.exercises.single;
    expect(exercise.sets.first.repTarget, const RepTarget.toFailure());
  });

  testWidgets('edit flow: existing plan pre-fills and save preserves id + cursor', (tester) async {
    final plans = _RecordingWorkoutPlanRepository();

    await tester.pumpWidget(
      _wrap(child: WorkoutPlanEditPage(initialPlan: _existingPlan()), plans: plans),
    );
    await tester.pump();

    // Existing content is shown.
    expect(find.text('Day A · Push'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);

    await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
    await tester.pumpAndSettle();

    final plan = plans.saved.single;
    expect(plan.id, 'existing'); // reused
    expect(plan.cycleCursor, 1); // rotation preserved
    expect(plan.days, hasLength(2));
    expect(plan.days.first.exercises.single.name, 'Bench Press');
  });

  testWidgets(
    'tap-to-edit: tapping an exercise opens it pre-filled and saving replaces it in place',
    (tester) async {
      final plans = _RecordingWorkoutPlanRepository();

      await tester.pumpWidget(
        _wrap(child: WorkoutPlanEditPage(initialPlan: _existingPlan()), plans: plans),
      );
      await tester.pump();

      await tester.tap(find.text('Bench Press'));
      await tester.pumpAndSettle();

      // Pre-filled from the existing exercise, not blank — and the sheet
      // knows it's editing (title + button label switch).
      expect(find.text('Edit exercise'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(const Key('exercise-name-field'))).controller!.text,
        'Bench Press',
      );

      await tester.enterText(
        find.byKey(const Key('exercise-name-field')),
        'Incline Bench Press',
      );
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(PillButton, 'Save changes'));
      await tester.tap(find.widgetWithText(PillButton, 'Save changes'));
      await tester.pumpAndSettle();

      // Replaced in place — not appended as a second exercise.
      expect(find.text('Incline Bench Press'), findsOneWidget);
      expect(find.text('Bench Press'), findsNothing);

      await tester.ensureVisible(find.widgetWithText(PillButton, 'Save plan'));
      await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
      await tester.pumpAndSettle();

      final day = plans.saved.single.days.first;
      expect(day.exercises, hasLength(1));
      final exercise = day.exercises.single;
      expect(exercise.id, 'e1'); // identity preserved, not regenerated
      expect(exercise.name, 'Incline Bench Press');
    },
  );

  testWidgets(
    'the rest wheel picker updates the saved rest and fires a selection-click haptic per tick',
    (tester) async {
      final plans = _RecordingWorkoutPlanRepository();
      final hapticCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'HapticFeedback.vibrate') hapticCalls.add(call.arguments as String);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(_wrap(child: const WorkoutPlanEditPage(), plans: plans));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('plan-name-field')), 'S');

      await tester.tap(find.text('Add day'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('day-label-field')), 'Push');
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(PillButton, 'Add day'));
      await tester.tap(find.widgetWithText(PillButton, 'Add day'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add exercise'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('exercise-name-field')), 'Bench Press');
      await tester.pump();

      // Default rest is 90s. Drag the wheel up by 3 items (15s each tick's
      // worth of 5s steps) to land on 90 + 3*5 = 105s ("1:45").
      await tester.drag(find.byKey(const Key('rest-picker')), const Offset(0, -34 * 3));
      await tester.pumpAndSettle();

      expect(hapticCalls, isNotEmpty);
      expect(hapticCalls, everyElement('HapticFeedbackType.selectionClick'));

      await tester.ensureVisible(find.widgetWithText(PillButton, 'Add exercise'));
      await tester.tap(find.widgetWithText(PillButton, 'Add exercise'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(PillButton, 'Save plan'));
      await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
      await tester.pumpAndSettle();

      final exercise = plans.saved.single.days.single.exercises.single;
      expect(exercise.sets.first.restSeconds, 105);
      expect(exercise.defaultRestSeconds, 105);
    },
  );

  testWidgets('delete flow: confirm removes the plan', (tester) async {
    final plans = _RecordingWorkoutPlanRepository();

    await tester.pumpWidget(
      _wrap(child: WorkoutPlanEditPage(initialPlan: _existingPlan()), plans: plans),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('workout-plan-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this plan?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(plans.deleted, ['existing']);
  });
}
