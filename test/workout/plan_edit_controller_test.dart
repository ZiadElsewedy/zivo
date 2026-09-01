import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/controllers/plan_edit_controller.dart';

/// The split editor's rules, asserted directly.
///
/// The rotation cursor is why this class exists. A plan stores `cycleCursor`
/// as an *index*, the editor lets days be dragged around, and getting that
/// wrong silently changes which workout Home offers you next — a bug you would
/// only notice a day later. It was 30 lines inside a `_save` method in a
/// 1,813-line `State`; here it is a property of an object.
void main() {
  test('a new plan starts saveable only once it has a name and a day', () {
    final c = PlanEditController(asSplit: false);
    addTearDown(c.dispose);

    expect(c.canSave, isFalse);
    c.name.text = 'Push Pull Legs';
    expect(
      c.canSave,
      isFalse,
      reason: 'a named plan with no days is not a plan',
    );

    c.addDay(_draft('d1', 'A', 'Push'));
    expect(c.canSave, isTrue);

    c.removeDay('d1');
    expect(c.canSave, isFalse);
  });

  test('slots run A, B, C… as days are added', () {
    final c = PlanEditController(asSplit: false);
    addTearDown(c.dispose);

    expect(c.nextSlot, 'A');
    c.addDay(_draft('d1', 'A', 'Push'));
    expect(c.nextSlot, 'B');
    c.addDay(_draft('d2', 'B', 'Pull'));
    expect(c.nextSlot, 'C');
  });

  group('the rotation cursor follows its day, not its index', () {
    test('reordering days keeps the cursor on the same workout', () {
      // The plan's cursor points at day B (order 1).
      final c = PlanEditController(
        initialPlan: _plan(cursor: 1),
        asSplit: false,
      );
      addTearDown(c.dispose);
      expect(c.days.map((d) => d.id), ['a', 'b', 'c']);

      // Drag B to the front: A, B, C → B, A, C.
      c.reorderDays(1, 0);

      final saved = c.buildPlan();
      expect(saved.days.map((d) => d.id), ['b', 'a', 'c']);
      expect(
        saved.days[saved.cycleCursor].id,
        'b',
        reason: 'the cursor must still point at the day it pointed at before',
      );
      expect(saved.cycleCursor, 0);
    });

    test('deleting the cursor day falls back to the first day', () {
      final c = PlanEditController(
        initialPlan: _plan(cursor: 1),
        asSplit: false,
      );
      addTearDown(c.dispose);

      c.removeDay('b');

      expect(c.buildPlan().cycleCursor, 0);
    });

    test('a plan with no days saves a cursor of 0 rather than -1', () {
      final c = PlanEditController(
        initialPlan: _plan(cursor: 1),
        asSplit: false,
      );
      addTearDown(c.dispose);

      for (final id in ['a', 'b', 'c']) {
        c.removeDay(id);
      }

      expect(c.buildPlan().cycleCursor, 0);
    });
  });

  test('saving renumbers day order and exercise order from position', () {
    final c = PlanEditController(asSplit: false);
    addTearDown(c.dispose);
    c.name.text = 'Split';
    c
      ..addDay(_draft('d1', 'A', 'Push'))
      ..addDay(_draft('d2', 'B', 'Pull'))
      ..addExercise(0, _exercise('e1', 'Bench', order: 7))
      ..addExercise(0, _exercise('e2', 'Fly', order: 3))
      ..reorderDays(1, 0);

    final plan = c.buildPlan();

    expect(plan.days.map((d) => d.order), [0, 1]);
    expect(plan.days[1].exercises.map((e) => e.order), [0, 1]);
    expect(
      plan.days[1].exercises.map((e) => e.id),
      ['e1', 'e2'],
      reason: 'order comes from position, identity is preserved',
    );
  });

  test('an imported plan keeps its source through the review edit', () {
    final c = PlanEditController(
      initialPlan: _plan(cursor: 0, source: WorkoutPlanSource.pdf),
      asSplit: false,
    );
    addTearDown(c.dispose);
    c.name.text = 'Reviewed';

    expect(
      c.buildPlan().source,
      WorkoutPlanSource.pdf,
      reason: 'only a genuinely new plan defaults to manual',
    );
  });

  test('bulk rest overwrites every exercise and every set', () {
    final c = PlanEditController(asSplit: false);
    addTearDown(c.dispose);
    c
      ..addDay(_draft('d1', 'A', 'Push'))
      ..addDay(_draft('d2', 'B', 'Pull'))
      ..addExercise(0, _exercise('e1', 'Bench'))
      ..addExercise(1, _exercise('e2', 'Row'));

    c.applyDefaultRest(45);

    for (final day in c.days) {
      for (final exercise in day.exercises) {
        expect(exercise.defaultRestSeconds, 45);
        expect(exercise.sets.map((s) => s.restSeconds), everyElement(45));
      }
    }
  });

  test('the rest wheel seeds from the first exercise, else 90', () {
    final c = PlanEditController(asSplit: false);
    addTearDown(c.dispose);
    expect(c.seedRest, 90);

    c
      ..addDay(_draft('d1', 'A', 'Push'))
      ..addExercise(0, _exercise('e1', 'Bench', rest: 120));

    expect(c.seedRest, 120);
  });

  test('replacing an exercise keeps its position and id', () {
    final c = PlanEditController(asSplit: false);
    addTearDown(c.dispose);
    c
      ..addDay(_draft('d1', 'A', 'Push'))
      ..addExercise(0, _exercise('e1', 'Bench'))
      ..addExercise(0, _exercise('e2', 'Fly'));

    c.replaceExercise(0, 0, _exercise('e1', 'Incline Bench'));

    expect(c.days[0].exercises.map((e) => e.name), ['Incline Bench', 'Fly']);
  });
}

// ---- Fixtures ---------------------------------------------------------------

DayDraft _draft(String id, String slot, String label) =>
    DayDraft(id: id, slot: slot, label: label);

PlannedExercise _exercise(
  String id,
  String name, {
  int order = 0,
  int rest = 90,
}) => PlannedExercise(
  id: id,
  name: name,
  order: order,
  defaultRestSeconds: rest,
  sets: [
    PlannedSet(
      order: 0,
      repTarget: const RepTarget.fixed(5),
      restSeconds: rest,
      type: SetType.working,
    ),
  ],
);

WorkoutPlan _plan({
  required int cursor,
  WorkoutPlanSource source = WorkoutPlanSource.manual,
}) => WorkoutPlan(
  id: 'p1',
  name: 'Test Split',
  status: WorkoutPlanStatus.active,
  source: source,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  cycleCursor: cursor,
  days: const [
    WorkoutDay(id: 'a', slot: 'A', label: 'Push', order: 0, exercises: []),
    WorkoutDay(id: 'b', slot: 'B', label: 'Pull', order: 1, exercises: []),
    WorkoutDay(id: 'c', slot: 'C', label: 'Legs', order: 2, exercises: []),
  ],
);
