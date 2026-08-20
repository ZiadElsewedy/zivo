import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/live_session_to_workout_log.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';

final _t0 = DateTime(2026, 1, 1, 9);
final _t1 = DateTime(2026, 1, 1, 10);

LiveSession _fresh() => LiveSession(
  id: 's1',
  planId: 'p1',
  dayId: 'day-a',
  dayLabel: 'Push',
  startedAt: _t0,
  status: SessionStatus.active,
  exercises: const [
    SessionExercise(
      id: 'ex1',
      exerciseId: 'ex1',
      name: 'Bench',
      restSeconds: 90,
      sets: [
        LoggedSet(id: 'ex1-s0', target: RepTarget.fixed(5)),
        LoggedSet(id: 'ex1-s1', target: RepTarget.fixed(5)),
      ],
    ),
    SessionExercise(
      id: 'ex2',
      exerciseId: 'ex2',
      name: 'Row',
      restSeconds: 60,
      sets: [LoggedSet(id: 'ex2-s0', target: RepTarget.range(8, 10))],
    ),
    SessionExercise(
      id: 'ex3',
      exerciseId: 'ex3',
      name: 'Curl',
      restSeconds: 45,
      sets: [LoggedSet(id: 'ex3-s0', target: RepTarget.toFailure())],
    ),
  ],
);

void main() {
  group('toWorkoutLog', () {
    test('maps a fully completed session, done-set counts, reps, and last weight', () {
      var s = _fresh();
      s = s.markSetDone('ex1', 'ex1-s0', actualReps: 5, actualWeightKg: 60);
      s = s.markSetDone('ex1', 'ex1-s1', actualReps: 5, actualWeightKg: 62.5);
      s = s.markSetDone('ex2', 'ex2-s0', actualReps: 9, actualWeightKg: 40);
      s = s.markSetDone('ex3', 'ex3-s0', actualReps: 12, actualWeightKg: 15);
      s = s.complete(now: _t1);

      final log = s.toWorkoutLog();
      expect(log.id, 's1');
      expect(log.title, 'Push');
      expect(log.performedAt, _t1);
      expect(log.exercises, hasLength(3));

      final bench = log.exercises[0];
      expect(bench.name, 'Bench');
      expect(bench.sets, 2);
      expect(bench.reps, 5); // best actual reps
      expect(bench.weightKg, 62.5); // last recorded actual weight

      final row = log.exercises[1];
      expect(row.name, 'Row');
      expect(row.sets, 1);
      expect(row.reps, 9);
      expect(row.weightKg, 40);

      final curl = log.exercises[2];
      expect(curl.name, 'Curl');
      expect(curl.sets, 1);
      expect(curl.reps, 12); // to-failure → best actual reps
      expect(curl.weightKg, 15);
    });

    test('skips exercises with no done sets', () {
      final s = _fresh().markSetDone('ex1', 'ex1-s0', actualReps: 5, actualWeightKg: 60);

      final log = s.toWorkoutLog();
      expect(log.exercises, hasLength(1));
      expect(log.exercises.single.name, 'Bench');
      expect(log.exercises.single.sets, 1);
    });

    test('a skipped set logs no volume — excluded from sets/reps/weight entirely', () {
      var s = _fresh();
      s = s.markSetDone('ex1', 'ex1-s0', actualReps: 5, actualWeightKg: 60);
      s = s.markSetSkipped('ex1', 'ex1-s1'); // second Bench set skipped
      s = s.markSetSkipped('ex2', 'ex2-s0'); // Row's only set skipped

      final log = s.toWorkoutLog();
      // Row has zero done sets (its one set was skipped) — excluded entirely,
      // same as an exercise nobody touched.
      expect(log.exercises.map((e) => e.name), ['Bench']);
      final bench = log.exercises.single;
      expect(bench.sets, 1); // only the completed set counts
      expect(bench.weightKg, 60); // the skipped set's (null) weight isn't the "last"
    });

    test('performedAt falls back to startedAt when completedAt is null', () {
      final s = _fresh().markSetDone('ex1', 'ex1-s0', actualReps: 5, actualWeightKg: 60);
      expect(s.completedAt, isNull);
      expect(s.toWorkoutLog().performedAt, _t0);
    });

    test('a set with no actual reps recorded falls back to its target minimum', () {
      final s = _fresh().markSetDone('ex2', 'ex2-s0', actualWeightKg: 40);
      // A range target's markSetDone leaves actualReps null unless supplied.
      expect(s.exercises[1].sets.single.actualReps, isNull);

      final log = s.toWorkoutLog();
      expect(log.exercises.single.reps, 8); // range → min
    });
  });
}
