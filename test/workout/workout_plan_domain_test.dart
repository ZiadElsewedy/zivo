import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_format.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';

PlannedSet _set({
  int order = 0,
  RepTarget repTarget = const RepTarget.fixed(10),
  int restSeconds = 90,
  double? targetWeightKg,
  double? rpe,
  SetType type = SetType.working,
}) => PlannedSet(
  order: order,
  repTarget: repTarget,
  restSeconds: restSeconds,
  targetWeightKg: targetWeightKg,
  rpe: rpe,
  type: type,
);

WorkoutDay _day({
  String id = 'd1',
  String slot = 'A',
  String label = 'Push A',
  int order = 0,
  List<PlannedExercise> exercises = const [],
}) => WorkoutDay(id: id, slot: slot, label: label, order: order, exercises: exercises);

WorkoutPlan _plan({List<WorkoutDay> days = const [], int cycleCursor = 0}) => WorkoutPlan(
  id: 'p1',
  name: 'Push Pull Legs',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  days: days,
  cycleCursor: cycleCursor,
);

void main() {
  group('RepTarget', () {
    test('fixed carries the same reps as min and max, and is value-equal', () {
      const a = RepTarget.fixed(10);
      const b = RepTarget.fixed(10);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.kind, RepTargetKind.fixed);
      expect(a.min, 10);
      expect(a.max, 10);
      expect(repTargetLabel(a), '10');
    });

    test('range carries distinct min/max and is value-equal', () {
      const a = RepTarget.range(8, 12);
      const b = RepTarget.range(8, 12);
      expect(a, b);
      expect(repTargetLabel(a), '8–12');
    });

    test('toFailure carries no min/max and is value-equal', () {
      const a = RepTarget.toFailure();
      const b = RepTarget.toFailure();
      expect(a, b);
      expect(a.min, isNull);
      expect(a.max, isNull);
      expect(repTargetLabel(a), 'To failure');
    });

    test('different kinds or bounds are not equal', () {
      expect(const RepTarget.fixed(10), isNot(const RepTarget.fixed(8)));
      expect(const RepTarget.fixed(10), isNot(const RepTarget.range(8, 10)));
    });
  });

  group('restLabel', () {
    test('formats seconds as mm:ss', () {
      expect(restLabel(120), '2:00');
      expect(restLabel(45), '0:45');
      expect(restLabel(90), '1:30');
      expect(restLabel(5), '0:05');
    });
  });

  group('setSummary', () {
    test('omits the weight when unset', () {
      final s = _set(repTarget: const RepTarget.fixed(10), restSeconds: 90);
      expect(setSummary(s), '10 reps · rest 1:30');
    });

    test('includes an integer weight without a trailing .0', () {
      final s = _set(repTarget: const RepTarget.fixed(10), restSeconds: 120, targetWeightKg: 60);
      expect(setSummary(s), '10 reps · 60kg · rest 2:00');
    });

    test('keeps a fractional weight', () {
      final s = _set(repTarget: const RepTarget.fixed(8), restSeconds: 90, targetWeightKg: 22.5);
      expect(setSummary(s), '8 reps · 22.5kg · rest 1:30');
    });

    test('formats a range target', () {
      final s = _set(repTarget: const RepTarget.range(8, 12), restSeconds: 90);
      expect(setSummary(s), '8–12 reps · rest 1:30');
    });

    test('formats a to-failure target without the "reps" suffix', () {
      final s = _set(repTarget: const RepTarget.toFailure(), restSeconds: 45);
      expect(setSummary(s), 'To failure · rest 0:45');
    });
  });

  group('PlannedExercise', () {
    test('setCount reflects the number of sets', () {
      final e = PlannedExercise(
        id: 'e1',
        name: 'Bench Press',
        order: 0,
        defaultRestSeconds: 90,
        sets: [_set(order: 0), _set(order: 1), _set(order: 2)],
      );
      expect(e.setCount, 3);
    });

    test('workingSetCount excludes non-working sets', () {
      final e = PlannedExercise(
        id: 'e1',
        name: 'Bench Press',
        order: 0,
        defaultRestSeconds: 90,
        sets: [
          _set(order: 0, type: SetType.warmup),
          _set(order: 1, type: SetType.working),
          _set(order: 2, type: SetType.working),
          _set(order: 3, type: SetType.dropset),
        ],
      );
      expect(e.workingSetCount, 2);
    });

    test('copyWith overrides only the given fields', () {
      final e = PlannedExercise(
        id: 'e1',
        name: 'Bench Press',
        order: 0,
        muscleGroup: 'Chest',
        defaultRestSeconds: 90,
        sets: [_set()],
      );
      final renamed = e.copyWith(name: 'Incline Bench Press', order: 1);
      expect(renamed.id, e.id);
      expect(renamed.name, 'Incline Bench Press');
      expect(renamed.order, 1);
      expect(renamed.muscleGroup, e.muscleGroup);
      expect(renamed.defaultRestSeconds, e.defaultRestSeconds);
      expect(renamed.sets, e.sets);
    });

    test('plannedExerciseMeta pluralises sets and appends the muscle group', () {
      final e = PlannedExercise(
        id: 'e1',
        name: 'Bench Press',
        order: 0,
        muscleGroup: 'Chest',
        defaultRestSeconds: 90,
        sets: [_set(order: 0), _set(order: 1), _set(order: 2), _set(order: 3)],
      );
      expect(plannedExerciseMeta(e), '4 sets · Chest');
    });

    test('plannedExerciseMeta uses the singular and omits an absent muscle group', () {
      final e = PlannedExercise(id: 'e1', name: 'Plank', order: 0, defaultRestSeconds: 60, sets: [_set()]);
      expect(plannedExerciseMeta(e), '1 set');
    });
  });

  group('workoutDayMeta', () {
    test('pluralises exercises', () {
      final e = PlannedExercise(id: 'e1', name: 'A', order: 0, defaultRestSeconds: 90, sets: const []);
      final day = _day(exercises: [e, e]);
      expect(workoutDayMeta(day), '2 exercises');
    });

    test('uses the singular for one exercise', () {
      final e = PlannedExercise(id: 'e1', name: 'A', order: 0, defaultRestSeconds: 90, sets: const []);
      final day = _day(exercises: [e]);
      expect(workoutDayMeta(day), '1 exercise');
    });
  });

  group('WorkoutPlan.nextDay', () {
    test('picks the day matching cycleCursor', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final dayB = _day(id: 'b', slot: 'B', order: 1);
      final dayC = _day(id: 'c', slot: 'C', order: 2);
      final plan = _plan(days: [dayA, dayB, dayC], cycleCursor: 1);
      expect(plan.nextDay, dayB);
    });

    test('null when no day has an order matching cycleCursor', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final plan = _plan(days: [dayA], cycleCursor: 5);
      expect(plan.nextDay, isNull);
    });

    test('null when the plan has no days', () {
      expect(_plan(days: const []).nextDay, isNull);
    });
  });

  group('WorkoutPlan.advanceCursor', () {
    test('advances to the next day in the rotation', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final dayB = _day(id: 'b', slot: 'B', order: 1);
      final dayC = _day(id: 'c', slot: 'C', order: 2);
      final plan = _plan(days: [dayA, dayB, dayC], cycleCursor: 0);

      final advanced = plan.advanceCursor();

      expect(advanced.cycleCursor, 1);
      expect(advanced.nextDay, dayB);
    });

    test('wraps around from the last day back to the first', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final dayB = _day(id: 'b', slot: 'B', order: 1);
      final dayC = _day(id: 'c', slot: 'C', order: 2);
      final plan = _plan(days: [dayA, dayB, dayC], cycleCursor: 2);

      final advanced = plan.advanceCursor();

      expect(advanced.cycleCursor, 0);
      expect(advanced.nextDay, dayA);
    });

    test('is pure: the original instance is unchanged', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final dayB = _day(id: 'b', slot: 'B', order: 1);
      final plan = _plan(days: [dayA, dayB], cycleCursor: 0);

      final advanced = plan.advanceCursor();

      expect(plan.cycleCursor, 0);
      expect(advanced.cycleCursor, 1);
      expect(identical(plan, advanced), isFalse);
    });

    test('preserves other fields', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final plan = _plan(days: [dayA], cycleCursor: 0);

      final advanced = plan.advanceCursor();

      expect(advanced.id, plan.id);
      expect(advanced.name, plan.name);
      expect(advanced.status, plan.status);
      expect(advanced.source, plan.source);
      expect(advanced.createdAt, plan.createdAt);
      expect(advanced.updatedAt, plan.updatedAt);
      expect(advanced.days, plan.days);
    });
  });

  group('WorkoutPlan.copyWith', () {
    test('overrides only the given fields', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final plan = _plan(days: [dayA], cycleCursor: 0);

      final renamed = plan.copyWith(name: 'PPL v2', status: WorkoutPlanStatus.archived);

      expect(renamed.id, plan.id);
      expect(renamed.name, 'PPL v2');
      expect(renamed.status, WorkoutPlanStatus.archived);
      expect(renamed.source, plan.source);
      expect(renamed.createdAt, plan.createdAt);
      expect(renamed.updatedAt, plan.updatedAt);
      expect(renamed.days, plan.days);
      expect(renamed.cycleCursor, plan.cycleCursor);
    });
  });
}
