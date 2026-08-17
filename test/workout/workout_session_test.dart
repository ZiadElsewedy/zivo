import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_phase.dart';
import 'package:zivo/features/workout/domain/session_to_workout_log.dart';
import 'package:zivo/features/workout/domain/set_log.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_session.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';

// A day with three exercises whose first-set targets exercise all three reps
// mappings (fixed, range, to-failure) and a total of four sets.
const _day = WorkoutDay(
  id: 'day-a',
  slot: 'A',
  label: 'Push',
  order: 0,
  exercises: [
    PlannedExercise(
      id: 'ex1',
      name: 'Bench',
      order: 0,
      defaultRestSeconds: 120,
      sets: [
        PlannedSet(order: 0, repTarget: RepTarget.fixed(5), restSeconds: 90, type: SetType.working),
        PlannedSet(order: 1, repTarget: RepTarget.fixed(5), restSeconds: 120, type: SetType.working),
      ],
    ),
    PlannedExercise(
      id: 'ex2',
      name: 'Row',
      order: 1,
      defaultRestSeconds: 60,
      sets: [
        PlannedSet(order: 0, repTarget: RepTarget.range(8, 10), restSeconds: 60, type: SetType.working),
      ],
    ),
    PlannedExercise(
      id: 'ex3',
      name: 'Curl',
      order: 2,
      defaultRestSeconds: 45,
      sets: [
        PlannedSet(order: 0, repTarget: RepTarget.toFailure(), restSeconds: 45, type: SetType.failure),
      ],
    ),
  ],
);

final _t0 = DateTime(2026, 1, 1, 9, 0);
final _t1 = DateTime(2026, 1, 1, 9, 5);

WorkoutSession _fresh() =>
    WorkoutSession.start(_day, id: 's1', planId: 'p1', now: _t0);

/// Drives a session from [running] through completing the current set and
/// ending the rest, so tests can walk the pointer forward compactly.
WorkoutSession _completeAndAdvance(
  WorkoutSession s, {
  int? actualReps,
  double? actualWeightKg,
}) => s
    .completeCurrentSet(actualReps: actualReps, actualWeightKg: actualWeightKg, now: _t1)
    .endRest();

void main() {
  group('start', () {
    test('begins running at 0/0 with an empty log', () {
      final s = _fresh();
      expect(s.phase, SessionPhase.running);
      expect(s.currentExerciseIndex, 0);
      expect(s.currentSetIndex, 0);
      expect(s.logs, isEmpty);
      expect(s.startedAt, _t0);
      expect(s.completedAt, isNull);
    });

    test('exposes the current pointers, counts, and rest', () {
      final s = _fresh();
      expect(s.currentExercise?.id, 'ex1');
      expect(s.currentSet, _day.exercises[0].sets[0]);
      expect(s.currentSetNumber, 1);
      expect(s.exerciseSetCount, 2);
      expect(s.nextExercise?.id, 'ex2');
      expect(s.totalSets, 4);
      expect(s.completedSetCount, 0);
      expect(s.currentRestSeconds, 90);
      expect(s.isResting, isFalse);
      expect(s.isComplete, isFalse);
    });
  });

  group('completeCurrentSet', () {
    test('appends a done log with the given actuals and enters resting without advancing', () {
      final s = _fresh().completeCurrentSet(actualReps: 5, actualWeightKg: 60, now: _t1);

      expect(s.phase, SessionPhase.resting);
      expect(s.isResting, isTrue);
      // Pointer unchanged — the rest belongs to the set just finished.
      expect(s.currentExerciseIndex, 0);
      expect(s.currentSetIndex, 0);
      expect(s.completedSetCount, 1);
      // Rest reflects the just-completed set.
      expect(s.currentRestSeconds, 90);
      expect(
        s.logs.single,
        const SetLog(
          exerciseId: 'ex1',
          setOrder: 0,
          target: RepTarget.fixed(5),
          actualReps: 5,
          actualWeightKg: 60,
          done: true,
        ),
      );
    });

    test('defaults actualReps to the target when null and the target is fixed', () {
      final s = _fresh().completeCurrentSet(actualWeightKg: 60, now: _t1);
      expect(s.logs.single.actualReps, 5);
    });

    test('leaves actualReps null when unset and the target is a range', () {
      // Advance through ex1's two sets to ex2 (range target), then complete with
      // no reps given.
      final atEx2 = _completeAndAdvance(_completeAndAdvance(_fresh()));
      expect(atEx2.currentExercise?.id, 'ex2');
      final resting = atEx2.completeCurrentSet(now: _t1);
      expect(resting.logs.last.actualReps, isNull);
    });

    test('is a no-op when not running (e.g. during rest)', () {
      final resting = _fresh().completeCurrentSet(actualReps: 5, now: _t1);
      final again = resting.completeCurrentSet(actualReps: 9, now: _t1);
      expect(again.logs, hasLength(1));
      expect(identical(resting, again), isTrue);
    });
  });

  group('endRest advances the pointer', () {
    test('to the next set within the same exercise', () {
      final s = _fresh().completeCurrentSet(actualReps: 5, now: _t1).endRest();
      expect(s.phase, SessionPhase.running);
      expect(s.currentExerciseIndex, 0);
      expect(s.currentSetIndex, 1);
      expect(s.currentSetNumber, 2);
      expect(s.currentRestSeconds, 120);
    });

    test('to the next exercise (set 0) after an exercise\'s last set', () {
      // Finish both sets of ex1.
      final afterFirst = _completeAndAdvance(_fresh(), actualReps: 5);
      final restingAfterLast =
          afterFirst.completeCurrentSet(actualReps: 5, now: _t1);
      // Last set of ex1 → resting, pointer still on ex1 set 1.
      expect(restingAfterLast.phase, SessionPhase.resting);
      expect(restingAfterLast.currentExerciseIndex, 0);
      expect(restingAfterLast.currentSetIndex, 1);

      final atEx2 = restingAfterLast.endRest();
      expect(atEx2.phase, SessionPhase.running);
      expect(atEx2.currentExerciseIndex, 1);
      expect(atEx2.currentSetIndex, 0);
      expect(atEx2.currentExercise?.id, 'ex2');
    });

    test('is a no-op when not resting', () {
      final s = _fresh();
      expect(identical(s, s.endRest()), isTrue);
    });
  });

  group('completing the final set', () {
    test('goes straight to completed (no rest) and stamps completedAt', () {
      // Walk to the final exercise's only set.
      var s = _completeAndAdvance(_fresh(), actualReps: 5); // ex1 set0 → ex1 set1
      s = _completeAndAdvance(s, actualReps: 5); // ex1 set1 → ex2 set0
      s = _completeAndAdvance(s, actualReps: 9); // ex2 set0 → ex3 set0
      expect(s.currentExercise?.id, 'ex3');
      expect(s.phase, SessionPhase.running);

      final done = s.completeCurrentSet(actualReps: 12, now: _t1);
      expect(done.phase, SessionPhase.completed);
      expect(done.isComplete, isTrue);
      expect(done.isResting, isFalse);
      expect(done.completedAt, _t1);
      expect(done.completedSetCount, 4);
    });
  });

  group('currentRestSeconds', () {
    test('reflects the just-completed set during rest', () {
      // Complete ex2's set (rest 60) and check the rest window.
      var s = _completeAndAdvance(_fresh(), actualReps: 5);
      s = _completeAndAdvance(s, actualReps: 5); // now at ex2 set0
      final resting = s.completeCurrentSet(actualReps: 9, now: _t1);
      expect(resting.isResting, isTrue);
      expect(resting.currentRestSeconds, 60);
    });
  });

  group('abandon', () {
    test('marks abandoned and stamps completedAt', () {
      final s = _fresh().abandon(now: _t1);
      expect(s.phase, SessionPhase.abandoned);
      expect(s.completedAt, _t1);
    });

    test('is a no-op once terminal', () {
      final done = _fresh().abandon(now: _t0);
      expect(identical(done, done.abandon(now: _t1)), isTrue);
    });
  });

  group('purity', () {
    test('transitions never mutate the receiver and return a new instance', () {
      final original = _fresh();
      final next = original.completeCurrentSet(actualReps: 5, actualWeightKg: 60, now: _t1);

      expect(identical(original, next), isFalse);
      // Original is untouched.
      expect(original.phase, SessionPhase.running);
      expect(original.logs, isEmpty);
      expect(original.currentSetIndex, 0);
      expect(original.completedAt, isNull);
    });
  });

  group('empty day guard', () {
    const emptyDay = WorkoutDay(id: 'd', slot: 'A', label: 'Empty', order: 0, exercises: []);

    test('getters return null and completeCurrentSet no-ops', () {
      final s = WorkoutSession.start(emptyDay, id: 's', planId: 'p', now: _t0);
      expect(s.currentExercise, isNull);
      expect(s.currentSet, isNull);
      expect(s.totalSets, 0);
      expect(identical(s, s.completeCurrentSet(now: _t1)), isTrue);
    });
  });

  group('toWorkoutLog', () {
    test('maps a fully completed session, done-set counts, reps, and last weight', () {
      var s = _fresh();
      s = _completeAndAdvance(s, actualReps: 5, actualWeightKg: 60); // ex1 set0
      s = _completeAndAdvance(s, actualReps: 5, actualWeightKg: 62.5); // ex1 set1
      s = _completeAndAdvance(s, actualReps: 9, actualWeightKg: 40); // ex2 set0
      final done = s.completeCurrentSet(actualReps: 12, actualWeightKg: 15, now: _t1); // ex3 set0
      expect(done.phase, SessionPhase.completed);

      final log = done.toWorkoutLog();
      expect(log.id, 's1');
      expect(log.title, 'Push');
      expect(log.performedAt, _t1);
      expect(log.exercises, hasLength(3));

      final bench = log.exercises[0];
      expect(bench.name, 'Bench');
      expect(bench.sets, 2);
      expect(bench.reps, 5); // fixed first-set target
      expect(bench.weightKg, 62.5); // last recorded actual weight

      final row = log.exercises[1];
      expect(row.name, 'Row');
      expect(row.sets, 1);
      expect(row.reps, 8); // range → min
      expect(row.weightKg, 40);

      final curl = log.exercises[2];
      expect(curl.name, 'Curl');
      expect(curl.sets, 1);
      expect(curl.reps, 12); // to-failure → best actual reps
      expect(curl.weightKg, 15);
    });

    test('skips exercises with no completed sets and falls back to startedAt', () {
      // Finish only ex1's two sets, then abandon before ex2/ex3.
      var s = _fresh();
      s = _completeAndAdvance(s, actualReps: 5, actualWeightKg: 60);
      final abandoned = s
          .completeCurrentSet(actualReps: 5, actualWeightKg: 60, now: _t1)
          .endRest() // now at ex2, running
          .abandon(now: _t1);

      final log = abandoned.toWorkoutLog();
      expect(log.exercises, hasLength(1));
      expect(log.exercises.single.name, 'Bench');
      // performedAt uses completedAt when present (abandon stamped it).
      expect(log.performedAt, _t1);
    });

    test('performedAt falls back to startedAt when completedAt is null', () {
      // A session mid-flight (never completed/abandoned) still projects.
      final s = _fresh().completeCurrentSet(actualReps: 5, actualWeightKg: 60, now: _t1);
      expect(s.completedAt, isNull);
      expect(s.toWorkoutLog().performedAt, _t0);
    });
  });
}
