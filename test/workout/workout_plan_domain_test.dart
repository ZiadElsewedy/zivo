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
      expect(repTargetFigure(a), '10');
    });

    test('range carries distinct min/max and is value-equal', () {
      const a = RepTarget.range(8, 12);
      const b = RepTarget.range(8, 12);
      expect(a, b);
      expect(repTargetFigure(a), '8–12');
    });

    test('toFailure carries no min/max and is value-equal', () {
      const a = RepTarget.toFailure();
      const b = RepTarget.toFailure();
      expect(a, b);
      expect(a.min, isNull);
      expect(a.max, isNull);
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

  // The prose these used to assert ("10 reps · rest 1:30", "3 × 8–10 · rest
  // 1:30") moved to `workout_labels_test.dart` when it moved out of `domain/`:
  // it is language, and it now has to be asserted in a locale. What stays here
  // is the part that is genuinely domain logic — which sets get collapsed
  // together, and in what order.
  group('collapsedSetGroups', () {
    test('collapses identical consecutive sets into one group', () {
      final sets = [
        _set(order: 0, repTarget: const RepTarget.range(8, 10), restSeconds: 90),
        _set(order: 1, repTarget: const RepTarget.range(8, 10), restSeconds: 90),
        _set(order: 2, repTarget: const RepTarget.range(8, 10), restSeconds: 90),
      ];
      final groups = collapsedSetGroups(sets);
      expect(groups, hasLength(1));
      expect(groups.single, hasLength(3));
    });

    test('a differing weight or target starts a new group', () {
      final sets = [
        _set(order: 0, repTarget: const RepTarget.range(8, 10), restSeconds: 90, targetWeightKg: 40),
        _set(order: 1, repTarget: const RepTarget.range(8, 10), restSeconds: 90, targetWeightKg: 40),
        _set(order: 2, repTarget: const RepTarget.range(6, 8), restSeconds: 90, targetWeightKg: 45),
      ];
      expect(collapsedSetGroups(sets).map((g) => g.length), [2, 1]);
    });

    test('every set differing yields one group per set', () {
      final sets = [
        _set(order: 0, repTarget: const RepTarget.fixed(12), restSeconds: 60),
        _set(order: 1, repTarget: const RepTarget.fixed(10), restSeconds: 75),
        _set(order: 2, repTarget: const RepTarget.toFailure(), restSeconds: 90),
      ];
      expect(collapsedSetGroups(sets).map((g) => g.length), [1, 1, 1]);
    });

    test('a non-adjacent repeat of the same spec is NOT re-merged', () {
      final sets = [
        _set(order: 0, repTarget: const RepTarget.fixed(10), restSeconds: 90),
        _set(order: 1, repTarget: const RepTarget.fixed(8), restSeconds: 90),
        _set(order: 2, repTarget: const RepTarget.fixed(10), restSeconds: 90),
      ];
      expect(collapsedSetGroups(sets).map((g) => g.first.repTarget.min), [10, 8, 10]);
    });

    test('empty sets list yields no groups', () {
      expect(collapsedSetGroups(const []), isEmpty);
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
  });

  group('WorkoutPlan.nextDay', () {
    test('picks the day matching cycleCursor', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final dayB = _day(id: 'b', slot: 'B', order: 1);
      final dayC = _day(id: 'c', slot: 'C', order: 2);
      final plan = _plan(days: [dayA, dayB, dayC], cycleCursor: 1);
      expect(plan.nextDay, dayB);
    });

    test('falls back to the first day by order when no day matches cycleCursor', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final dayB = _day(id: 'b', slot: 'B', order: 1);
      final plan = _plan(days: [dayB, dayA], cycleCursor: 5);
      expect(plan.nextDay, dayA);
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

  group('WorkoutPlan.advanceToAfterDay', () {
    test('moves the cursor past the day that was actually trained — not +1 from the old head', () {
      // Cursor on A, but the user trained C out of order. The recommendation
      // must land on A (after C wraps), NOT B (blind +1 from A).
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final dayB = _day(id: 'b', slot: 'B', order: 1);
      final dayC = _day(id: 'c', slot: 'C', order: 2);
      final plan = _plan(days: [dayA, dayB, dayC], cycleCursor: 0);

      final advanced = plan.advanceToAfterDay('c');

      expect(advanced.cycleCursor, 0);
      expect(advanced.nextDay, dayA);
    });

    test('in-order completion matches advanceCursor', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final dayB = _day(id: 'b', slot: 'B', order: 1);
      final dayC = _day(id: 'c', slot: 'C', order: 2);
      final plan = _plan(days: [dayA, dayB, dayC], cycleCursor: 0);

      final advanced = plan.advanceToAfterDay('a');

      expect(advanced.cycleCursor, 1);
      expect(advanced.nextDay, dayB);
    });

    test('wraps past the last day back to the first', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final dayB = _day(id: 'b', slot: 'B', order: 1);
      final plan = _plan(days: [dayA, dayB], cycleCursor: 1);

      final advanced = plan.advanceToAfterDay('b');

      expect(advanced.nextDay, dayA);
    });

    test('unknown dayId (plan edited mid-session) falls back to a one-step advance', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final dayB = _day(id: 'b', slot: 'B', order: 1);
      final dayC = _day(id: 'c', slot: 'C', order: 2);
      final plan = _plan(days: [dayA, dayB, dayC], cycleCursor: 1);

      final advanced = plan.advanceToAfterDay('deleted-day');

      expect(advanced.cycleCursor, 2);
    });

    test('is pure and preserves other fields', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final dayB = _day(id: 'b', slot: 'B', order: 1);
      final plan = _plan(days: [dayA, dayB], cycleCursor: 0);

      final advanced = plan.advanceToAfterDay('b');

      expect(plan.cycleCursor, 0);
      expect(identical(plan, advanced), isFalse);
      expect(advanced.id, plan.id);
      expect(advanced.name, plan.name);
      expect(advanced.days, plan.days);
    });
  });

  group('WorkoutPlan.swapDays', () {
    test('trades the two days\' rotation positions and leaves the cursor alone', () {
      final legs = _day(id: 'legs', slot: 'A', label: 'Legs', order: 0);
      final arms = _day(id: 'arms', slot: 'B', label: 'Arms', order: 1);
      final chest = _day(id: 'chest', slot: 'C', label: 'Chest', order: 2);
      final plan = _plan(days: [legs, arms, chest], cycleCursor: 0);

      final swapped = plan.swapDays('legs', 'arms');

      // The cursor is an `order`, so it now resolves to the day that MOVED
      // into position 0 — Arms is what gets trained today.
      expect(swapped.cycleCursor, 0);
      expect(swapped.nextDay?.id, 'arms');
      expect(swapped.days.firstWhere((d) => d.id == 'arms').order, 0);
      expect(swapped.days.firstWhere((d) => d.id == 'legs').order, 1);
      expect(swapped.days.firstWhere((d) => d.id == 'chest').order, 2);
    });

    test('the displaced day comes up next, so no day loses its turn', () {
      // The whole point: Legs was due, Arms is trained instead, and finishing
      // Arms must put Legs back in front — not skip it the way a bare
      // advanceToAfterDay would.
      final legs = _day(id: 'legs', slot: 'A', label: 'Legs', order: 0);
      final arms = _day(id: 'arms', slot: 'B', label: 'Arms', order: 1);
      final chest = _day(id: 'chest', slot: 'C', label: 'Chest', order: 2);
      final plan = _plan(days: [legs, arms, chest], cycleCursor: 0);

      final afterArms = plan.swapDays('legs', 'arms').advanceToAfterDay('arms');
      expect(afterArms.nextDay?.id, 'legs');

      final afterLegs = afterArms.advanceToAfterDay('legs');
      expect(afterLegs.nextDay?.id, 'chest');

      // ...and without the swap, Legs is what gets dropped.
      expect(plan.advanceToAfterDay('arms').nextDay?.id, 'chest');
    });

    test('keeps each day\'s slot letter — slot is identity, order is position', () {
      final legs = _day(id: 'legs', slot: 'A', label: 'Legs', order: 0);
      final arms = _day(id: 'arms', slot: 'B', label: 'Arms', order: 1);
      final plan = _plan(days: [legs, arms], cycleCursor: 0);

      final swapped = plan.swapDays('legs', 'arms');

      expect(swapped.days.firstWhere((d) => d.id == 'arms').slot, 'B');
      expect(swapped.days.firstWhere((d) => d.id == 'legs').slot, 'A');
    });

    test('swapping a day with a non-cursor day still keeps every day in the cycle', () {
      final legs = _day(id: 'legs', slot: 'A', label: 'Legs', order: 0);
      final arms = _day(id: 'arms', slot: 'B', label: 'Arms', order: 1);
      final chest = _day(id: 'chest', slot: 'C', label: 'Chest', order: 2);
      final plan = _plan(days: [legs, arms, chest], cycleCursor: 0);

      var next = plan.swapDays('legs', 'chest');
      expect(next.nextDay?.id, 'chest');

      final trained = <String>[];
      for (var i = 0; i < 3; i++) {
        final day = next.nextDay!;
        trained.add(day.id);
        next = next.advanceToAfterDay(day.id);
      }

      expect(trained, ['chest', 'arms', 'legs']);
    });

    test('the same id twice, or an unknown id, is a no-op', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final dayB = _day(id: 'b', slot: 'B', order: 1);
      final plan = _plan(days: [dayA, dayB], cycleCursor: 0);

      expect(identical(plan.swapDays('a', 'a'), plan), isTrue);
      expect(identical(plan.swapDays('a', 'gone'), plan), isTrue);
      expect(identical(plan.swapDays('gone', 'a'), plan), isTrue);
    });

    test('is pure and preserves other fields', () {
      final dayA = _day(id: 'a', slot: 'A', order: 0);
      final dayB = _day(id: 'b', slot: 'B', order: 1);
      final plan = _plan(days: [dayA, dayB], cycleCursor: 0);

      final swapped = plan.swapDays('a', 'b');

      expect(plan.days.first.order, 0); // untouched
      expect(swapped.id, plan.id);
      expect(swapped.name, plan.name);
      expect(swapped.status, plan.status);
      expect(swapped.createdAt, plan.createdAt);
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
