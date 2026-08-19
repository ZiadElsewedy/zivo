import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/progression.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';

LoggedSet _done({required int reps, double? weightKg}) => LoggedSet(
  id: 'prev',
  target: RepTarget.fixed(reps),
  done: true,
  actualReps: reps,
  actualWeightKg: weightKg,
);

void main() {
  group('computeGoal — no previous performance', () {
    test('fixed target: the plan prescription, reps = the fixed count', () {
      final goal = computeGoal(target: const RepTarget.fixed(8), targetWeightKg: 60);
      expect(goal.weightKg, 60);
      expect(goal.repsLabel, '8');
      expect(goal.label, '60kg × 8');
    });

    test('range target: reps = the range floor, not the whole range', () {
      final goal = computeGoal(target: const RepTarget.range(6, 10), targetWeightKg: 40);
      expect(goal.repsLabel, '6');
      expect(goal.label, '40kg × 6');
    });

    test('to-failure target: "AMRAP", no rep count', () {
      final goal = computeGoal(target: const RepTarget.toFailure(), targetWeightKg: 20);
      expect(goal.repsLabel, 'AMRAP');
      expect(goal.label, '20kg AMRAP');
    });

    test('null previous is the same as an unlogged previous (no actualReps)', () {
      final unlogged = const LoggedSet(id: 'x', target: RepTarget.fixed(8));
      final a = computeGoal(target: const RepTarget.fixed(8), targetWeightKg: 60);
      final b = computeGoal(
        target: const RepTarget.fixed(8),
        targetWeightKg: 60,
        previous: unlogged,
      );
      expect(a.label, b.label);
    });

    test('no plan weight either (bodyweight movement) → weight stays null', () {
      final goal = computeGoal(target: const RepTarget.fixed(12));
      expect(goal.weightKg, isNull);
      expect(goal.label, '× 12');
    });
  });

  group('computeGoal — hit the top of the rep target → step weight up', () {
    test('fixed target hit exactly (prevReps >= the fixed count) → +2.5kg compound, reps reset', () {
      final goal = computeGoal(
        target: const RepTarget.fixed(8),
        targetWeightKg: 60,
        previous: _done(reps: 8, weightKg: 60),
        muscleGroup: 'Chest',
      );
      expect(goal.weightKg, 62.5);
      expect(goal.repsLabel, '8'); // floor == fixed count here
      expect(goal.label, '62.5kg × 8');
    });

    test('range target, prevReps beats the max → +2.5kg compound, reps reset to the floor', () {
      final goal = computeGoal(
        target: const RepTarget.range(6, 8),
        targetWeightKg: 60,
        previous: _done(reps: 9, weightKg: 60), // overshot the max
        muscleGroup: 'Back',
      );
      expect(goal.weightKg, 62.5);
      expect(goal.repsLabel, '6');
    });

    test('small/isolation muscle group gets the smaller +1.25kg jump', () {
      final goal = computeGoal(
        target: const RepTarget.range(10, 12),
        targetWeightKg: 15,
        previous: _done(reps: 12, weightKg: 15),
        muscleGroup: 'Biceps',
      );
      expect(goal.weightKg, 16.25);
    });

    test(
      'hit the top with no weight ever tracked (bodyweight) → keep adding '
      'reps, not reset to the floor (that would ask for fewer than just done)',
      () {
        final goal = computeGoal(
          target: const RepTarget.fixed(15),
          previous: _done(reps: 15),
          muscleGroup: 'Abs',
        );
        expect(goal.weightKg, isNull);
        expect(goal.repsLabel, '16'); // +1, not reset to 15
      },
    );

    test(
      'range target, prevReps at/above the max, no weight tracked → still '
      '+1 rep uncapped, not reset to the floor',
      () {
        final goal = computeGoal(
          target: const RepTarget.range(8, 12),
          previous: _done(reps: 14), // already past the max
        );
        expect(goal.weightKg, isNull);
        expect(goal.repsLabel, '15'); // prevReps + 1, uncapped
      },
    );

    test('previous weight (not the plan target) is what gets incremented', () {
      final goal = computeGoal(
        target: const RepTarget.range(6, 8),
        targetWeightKg: 60, // plan says 60, but the set was actually done heavier
        previous: _done(reps: 8, weightKg: 65),
        muscleGroup: 'Chest',
      );
      expect(goal.weightKg, 67.5);
    });
  });

  group('computeGoal — short of the top → same weight, one more rep', () {
    test('range target, mid-range → +1 rep, same weight', () {
      final goal = computeGoal(
        target: const RepTarget.range(6, 10),
        targetWeightKg: 50,
        previous: _done(reps: 7, weightKg: 50),
      );
      expect(goal.weightKg, 50);
      expect(goal.repsLabel, '8');
    });

    test('a set logged one rep under the target top still only asks for the top, not beyond', () {
      final goal = computeGoal(
        target: const RepTarget.range(6, 8),
        targetWeightKg: 50,
        previous: _done(reps: 7, weightKg: 50), // one under the max of 8
      );
      expect(goal.repsLabel, '8'); // capped at the top, not '9'
      expect(goal.weightKg, 50); // same weight — hasn't hit the top yet
    });
  });

  group('computeGoal — to-failure with previous performance', () {
    test('always "beat last" — one more rep than last time, same weight', () {
      final goal = computeGoal(
        target: const RepTarget.toFailure(),
        targetWeightKg: 20,
        previous: _done(reps: 11, weightKg: 20),
      );
      expect(goal.weightKg, 20);
      expect(goal.repsLabel, '12');
      expect(goal.label, '20kg × 12');
    });
  });
}
