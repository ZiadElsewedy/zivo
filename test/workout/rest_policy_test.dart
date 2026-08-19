import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/rest_policy.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/set_type.dart';

void main() {
  group('smartRestSeconds', () {
    test('bases rest on rep-target intensity for the first working set', () {
      expect(smartRestSeconds(repTargetMin: 5, workingSetIndex: 0), 115); // <=6
      expect(smartRestSeconds(repTargetMin: 6, workingSetIndex: 0), 115); // boundary
      expect(smartRestSeconds(repTargetMin: 7, workingSetIndex: 0), 90); // boundary
      expect(smartRestSeconds(repTargetMin: 12, workingSetIndex: 0), 90); // boundary
      expect(smartRestSeconds(repTargetMin: 13, workingSetIndex: 0), 60); // boundary
      expect(smartRestSeconds(repTargetMin: 20, workingSetIndex: 0), 60);
    });

    test('clamps small/isolation muscle groups down to 75s even at low reps', () {
      expect(
        smartRestSeconds(repTargetMin: 5, muscleGroup: 'Biceps', workingSetIndex: 0),
        75,
      );
      expect(
        smartRestSeconds(repTargetMin: 5, muscleGroup: 'Calves', workingSetIndex: 0),
        75,
      );
      // Case-insensitive, substring match against free-text muscle groups.
      expect(
        smartRestSeconds(repTargetMin: 5, muscleGroup: 'Rear delts', workingSetIndex: 0),
        75,
      );
      // Already <=75 (higher reps) — the clamp never raises it.
      expect(
        smartRestSeconds(repTargetMin: 15, muscleGroup: 'Triceps', workingSetIndex: 0),
        60,
      );
    });

    test('large compound muscle groups keep the full intensity-based base', () {
      for (final group in ['Chest', 'Back', 'Legs', 'Quads', 'Hamstrings', 'Glutes']) {
        expect(
          smartRestSeconds(repTargetMin: 5, muscleGroup: group, workingSetIndex: 0),
          115,
          reason: '$group should not be clamped',
        );
      }
    });

    test('unrecognized/null muscle group is treated as large (not clamped)', () {
      expect(smartRestSeconds(repTargetMin: 5, workingSetIndex: 0), 115);
      expect(
        smartRestSeconds(repTargetMin: 5, muscleGroup: 'Forehead', workingSetIndex: 0),
        115,
      );
    });

    test('decreases 10s per subsequent working set, floored at 45s', () {
      expect(smartRestSeconds(repTargetMin: 8, workingSetIndex: 0), 90);
      expect(smartRestSeconds(repTargetMin: 8, workingSetIndex: 1), 80);
      expect(smartRestSeconds(repTargetMin: 8, workingSetIndex: 2), 70);
      // 60 base, decaying past the floor.
      expect(smartRestSeconds(repTargetMin: 15, workingSetIndex: 0), 60);
      expect(smartRestSeconds(repTargetMin: 15, workingSetIndex: 1), 50);
      expect(smartRestSeconds(repTargetMin: 15, workingSetIndex: 2), 45); // would be 40
      expect(smartRestSeconds(repTargetMin: 15, workingSetIndex: 5), 45); // still floored
    });

    test('never returns 120s or more, regardless of inputs', () {
      final results = [
        smartRestSeconds(repTargetMin: 1, workingSetIndex: 0),
        smartRestSeconds(repTargetMin: 0, workingSetIndex: 0),
        smartRestSeconds(repTargetMin: -5, workingSetIndex: 0),
      ];
      for (final r in results) {
        expect(r, lessThan(120));
      }
    });
  });

  group('workingSetIndexOf', () {
    SessionExercise exerciseWith(List<LoggedSet> sets) => SessionExercise(
      id: 'e1',
      exerciseId: 'e1',
      name: 'Bench',
      restSeconds: 90,
      sets: sets,
    );

    test('0-based index counting only working-type sets before it', () {
      final s0 = const LoggedSet(id: 's0', target: RepTarget.fixed(8), type: SetType.working);
      final s1 = const LoggedSet(id: 's1', target: RepTarget.fixed(8), type: SetType.working);
      final s2 = const LoggedSet(id: 's2', target: RepTarget.fixed(8), type: SetType.working);
      final exercise = exerciseWith([s0, s1, s2]);

      expect(workingSetIndexOf(exercise, s0), 0);
      expect(workingSetIndexOf(exercise, s1), 1);
      expect(workingSetIndexOf(exercise, s2), 2);
    });

    test('a warmup set ahead of the working sets does not count toward the index', () {
      final warmup = const LoggedSet(id: 'w0', target: RepTarget.fixed(10), type: SetType.warmup);
      final s0 = const LoggedSet(id: 's0', target: RepTarget.fixed(8), type: SetType.working);
      final s1 = const LoggedSet(id: 's1', target: RepTarget.fixed(8), type: SetType.working);
      final exercise = exerciseWith([warmup, s0, s1]);

      expect(workingSetIndexOf(exercise, s0), 0);
      expect(workingSetIndexOf(exercise, s1), 1);
    });

    test('a non-working set resolves to 0 rather than throwing', () {
      final s0 = const LoggedSet(id: 's0', target: RepTarget.fixed(8), type: SetType.working);
      final dropset = const LoggedSet(
        id: 'd0',
        target: RepTarget.fixed(8),
        type: SetType.dropset,
      );
      final exercise = exerciseWith([s0, dropset]);

      expect(workingSetIndexOf(exercise, dropset), 0);
    });
  });
}
