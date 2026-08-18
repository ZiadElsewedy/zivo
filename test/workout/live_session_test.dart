import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/exercise_history.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';

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
      muscleGroup: 'Chest',
      defaultRestSeconds: 90,
      sets: [
        // Weight kept under the 40kg warm-up qualifying threshold (see
        // warmup_policy_test.dart) so this generic CRUD fixture doesn't pick
        // up an auto-generated ramp — that's covered by its own group below.
        PlannedSet(order: 0, repTarget: RepTarget.fixed(5), restSeconds: 90, targetWeightKg: 30, type: SetType.working),
        PlannedSet(order: 1, repTarget: RepTarget.range(8, 10), restSeconds: 90, type: SetType.working),
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
  ],
);

final _t0 = DateTime(2026, 8, 18, 9);
final _t1 = DateTime(2026, 8, 18, 10);

LiveSession _fresh() => LiveSession.start(_day, id: 's1', planId: 'p1', now: _t0);

void main() {
  group('start', () {
    test('builds session-exercises and sets from the plan, actuals empty', () {
      final s = _fresh();
      expect(s.status, SessionStatus.active);
      expect(s.dayLabel, 'Push');
      expect(s.exercises, hasLength(2));
      expect(s.totalSets, 3);
      expect(s.completedSetCount, 0);
      expect(s.progress, 0);

      final bench = s.exercises.first;
      expect(bench.exerciseId, 'ex1');
      expect(bench.sets, hasLength(2));
      final firstSet = bench.sets.first;
      expect(firstSet.target, const RepTarget.fixed(5));
      expect(firstSet.targetWeightKg, 30); // carried from the plan
      expect(firstSet.actualWeightKg, isNull); // nothing performed yet
      expect(firstSet.done, isFalse);

      // Current = first set of the first exercise.
      expect(s.currentExercise?.exerciseId, 'ex1');
      expect(s.currentSet?.id, bench.sets.first.id);
    });
  });

  group('start: warm-up ramp integration', () {
    const heavyDay = WorkoutDay(
      id: 'day-b',
      slot: 'B',
      label: 'Legs',
      order: 0,
      exercises: [
        PlannedExercise(
          id: 'squat',
          name: 'Squat',
          order: 0,
          muscleGroup: 'Legs',
          defaultRestSeconds: 120,
          sets: [
            PlannedSet(
              order: 0,
              repTarget: RepTarget.fixed(5),
              restSeconds: 120,
              targetWeightKg: 80,
              type: SetType.working,
            ),
            PlannedSet(
              order: 1,
              repTarget: RepTarget.fixed(5),
              restSeconds: 120,
              targetWeightKg: 80,
              type: SetType.working,
            ),
          ],
        ),
        PlannedExercise(
          id: 'curl',
          name: 'Curl',
          order: 1,
          muscleGroup: 'Biceps',
          defaultRestSeconds: 60,
          sets: [
            PlannedSet(
              order: 0,
              repTarget: RepTarget.fixed(12),
              restSeconds: 60,
              targetWeightKg: 60, // heavy enough, but isolation never ramps
              type: SetType.working,
            ),
          ],
        ),
      ],
    );

    test('prepends a warm-up ramp before a qualifying compound\'s working sets', () {
      final s = LiveSession.start(heavyDay, id: 's1', planId: 'p1', now: _t0);
      final squat = s.exercises.first;
      // 80kg compound → the 3-step tier (see warmup_policy_test.dart).
      expect(squat.sets, hasLength(5));
      expect(squat.sets.sublist(0, 3).every((s) => s.type == SetType.warmup), isTrue);
      expect(squat.sets.sublist(3).every((s) => s.type == SetType.working), isTrue);
      // Ramp weights climb, floored/rounded, below the 80kg working weight.
      expect(squat.sets[0].targetWeightKg, 32.5);
      expect(squat.sets[1].targetWeightKg, 47.5);
      expect(squat.sets[2].targetWeightKg, 65.0);
      // Working sets keep the plan's own prescription untouched.
      expect(squat.sets[3].target, const RepTarget.fixed(5));
      expect(squat.sets[3].targetWeightKg, 80);
      // The derived "current set" is the first warm-up, not the first working set.
      expect(s.currentSet?.id, squat.sets.first.id);
    });

    test('isolation work never gets a ramp even at a qualifying weight', () {
      final s = LiveSession.start(heavyDay, id: 's1', planId: 'p1', now: _t0);
      final curl = s.exercises[1];
      expect(curl.sets, hasLength(1));
      expect(curl.sets.single.type, SetType.working);
    });

    test('a working set with no prescribed weight gets no ramp (nothing to ramp toward)', () {
      final s = LiveSession.start(_day, id: 's1', planId: 'p1', now: _t0);
      // ex1's first set is 30kg (sub-threshold, see the CRUD fixture above);
      // ex2 has no targetWeightKg at all.
      final row = s.exercises[1];
      expect(row.sets, hasLength(1));
      expect(row.sets.single.type, SetType.working);
    });
  });

  group('markSetDone', () {
    test('records actuals, defaults fixed reps, advances the current pointer', () {
      final s0 = _fresh();
      final firstId = s0.exercises.first.sets.first.id;

      // No reps given, fixed target → defaults to 5; weight given.
      final s1 = s0.markSetDone('ex1', firstId, actualWeightKg: 62.5);
      final done = s1.exercises.first.sets.first;
      expect(done.done, isTrue);
      expect(done.actualReps, 5);
      expect(done.actualWeightKg, 62.5);
      expect(s1.completedSetCount, 1);
      // Current advances to the second set of Bench.
      expect(s1.currentSet?.id, s0.exercises.first.sets[1].id);
    });

    test('range target leaves reps null unless supplied; purity holds', () {
      final s0 = _fresh();
      final secondId = s0.exercises.first.sets[1].id;
      final s1 = s0.markSetDone('ex1', secondId, actualWeightKg: 40);
      expect(s1.exercises.first.sets[1].actualReps, isNull);
      // Original untouched.
      expect(identical(s0, s1), isFalse);
      expect(s0.completedSetCount, 0);
    });
  });

  group('set CRUD', () {
    test('addSet appends inheriting the last set target/weight', () {
      final s = _fresh().addSet('ex1', setId: 'new-set');
      final bench = s.exercises.first;
      expect(bench.sets, hasLength(3));
      expect(bench.sets.last.id, 'new-set');
      expect(bench.sets.last.target, const RepTarget.range(8, 10)); // from last set
    });

    test('updateSet edits weight/reps and can clear a value', () {
      var s = _fresh();
      final id = s.exercises.first.sets.first.id;
      s = s.updateSet('ex1', id, actualWeightKg: 70, actualReps: 6);
      expect(s.exercises.first.sets.first.actualWeightKg, 70);
      expect(s.exercises.first.sets.first.actualReps, 6);
      // Clearing with an explicit null; targetWeightKg is preserved (30).
      s = s.updateSet('ex1', id, actualWeightKg: null);
      expect(s.exercises.first.sets.first.actualWeightKg, isNull);
      expect(s.exercises.first.sets.first.actualReps, 6); // untouched
      expect(s.exercises.first.sets.first.targetWeightKg, 30);
    });

    test('removeSet drops the set', () {
      final s0 = _fresh();
      final id = s0.exercises.first.sets.first.id;
      final s1 = s0.removeSet('ex1', id);
      expect(s1.exercises.first.sets, hasLength(1));
      expect(s1.totalSets, 2);
    });
  });

  group('exercise CRUD', () {
    test('addExercise and removeExercise mutate the list purely', () {
      const extra = SessionExercise(
        id: 'ex3',
        exerciseId: 'ex3',
        name: 'Fly',
        restSeconds: 60,
        sets: [LoggedSet(id: 'ex3-s0', target: RepTarget.fixed(8))],
      );
      final added = _fresh().addExercise(extra);
      expect(added.exercises, hasLength(3));
      expect(added.exercises.last.name, 'Fly');

      final removed = added.removeExercise('ex2');
      expect(removed.exercises.map((e) => e.exerciseId), ['ex1', 'ex3']);
    });

    test('renameExercise keeps the canonical id (machine swap)', () {
      final s = _fresh().renameExercise('ex1', 'Smith Machine Bench');
      expect(s.exercises.first.name, 'Smith Machine Bench');
      expect(s.exercises.first.exerciseId, 'ex1'); // history continuity
    });
  });

  group('session transitions', () {
    test('complete stamps completedAt and is terminal', () {
      final s = _fresh().complete(now: _t1);
      expect(s.status, SessionStatus.completed);
      expect(s.isComplete, isTrue);
      expect(s.completedAt, _t1);
      expect(s.elapsed, const Duration(hours: 1));
      // No-op once terminal.
      expect(identical(s, s.abandon(now: _t1)), isTrue);
    });

    test('abandon marks abandoned', () {
      final s = _fresh().abandon(now: _t1);
      expect(s.status, SessionStatus.abandoned);
      expect(s.completedAt, _t1);
    });

    test('allSetsDone flips once every set is done', () {
      var s = _fresh();
      expect(s.allSetsDone, isFalse);
      for (final e in s.exercises) {
        for (final set in e.sets) {
          s = s.markSetDone(e.id, set.id);
        }
      }
      expect(s.allSetsDone, isTrue);
      expect(s.currentSet, isNull);
    });
  });

  group('pause/resume', () {
    test('pause records pausedAt; activeElapsed freezes there', () {
      final s0 = _fresh(); // started at _t0
      final paused = s0.pause(now: _t0.add(const Duration(minutes: 10)));
      expect(paused.isPaused, isTrue);
      expect(paused.pausedAt, _t0.add(const Duration(minutes: 10)));

      // Frozen at the pause moment regardless of how much later `now` is.
      final laterNow = _t0.add(const Duration(minutes: 25));
      expect(paused.activeElapsed(now: laterNow), const Duration(minutes: 10));
    });

    test('resume folds the closed pause into pausedAccum and clears pausedAt', () {
      final paused = _fresh().pause(now: _t0.add(const Duration(minutes: 10)));
      final resumed = paused.resume(now: _t0.add(const Duration(minutes: 14)));

      expect(resumed.isPaused, isFalse);
      expect(resumed.pausedAt, isNull);
      expect(resumed.pausedAccum, const Duration(minutes: 4));

      // activeElapsed now counts real time again, minus the accumulated pause.
      final now = _t0.add(const Duration(minutes: 20));
      expect(resumed.activeElapsed(now: now), const Duration(minutes: 16)); // 20 - 4
    });

    test('pausedAccum keeps accumulating across multiple pause/resume cycles', () {
      var s = _fresh();
      s = s.pause(now: _t0.add(const Duration(minutes: 5)));
      s = s.resume(now: _t0.add(const Duration(minutes: 8))); // +3min paused
      s = s.pause(now: _t0.add(const Duration(minutes: 30)));
      s = s.resume(now: _t0.add(const Duration(minutes: 36))); // +6min paused

      expect(s.pausedAccum, const Duration(minutes: 9));
      expect(s.isPaused, isFalse);
    });

    test('pause is a no-op while already paused or once terminal', () {
      final paused = _fresh().pause(now: _t0.add(const Duration(minutes: 5)));
      final pausedAgain = paused.pause(now: _t0.add(const Duration(minutes: 9)));
      expect(pausedAgain.pausedAt, paused.pausedAt); // unchanged, not re-stamped

      final completed = _fresh().complete(now: _t1);
      expect(identical(completed, completed.pause(now: _t1)), isTrue);
    });

    test('resume is a no-op when not paused', () {
      final s = _fresh();
      expect(identical(s, s.resume(now: _t1)), isTrue);
    });

    test('complete closes an open pause first, and elapsed excludes all paused time', () {
      var s = _fresh(); // starts at _t0
      s = s.pause(now: _t0.add(const Duration(minutes: 20)));
      // Still paused when Finish is tapped an hour after starting.
      final finished = s.complete(now: _t0.add(const Duration(hours: 1)));

      expect(finished.isComplete, isTrue);
      expect(finished.isPaused, isFalse); // the open pause was closed
      // Paused from minute 20 to minute 60 → 40min excluded from the 60min
      // wall-clock span, leaving 20min of active elapsed.
      expect(finished.elapsed, const Duration(minutes: 20));
    });

    test('elapsed on a session that was never paused is unaffected (pausedAccum 0)', () {
      final s = _fresh().complete(now: _t1);
      expect(s.elapsed, const Duration(hours: 1));
    });
  });

  group('lastPerformanceFor', () {
    LiveSession completedBench({
      required String id,
      required DateTime at,
      required double weight,
      required int reps,
    }) {
      var s = LiveSession.start(_day, id: id, planId: 'p1', now: at);
      s = s.markSetDone('ex1', s.exercises.first.sets.first.id, actualWeightKg: weight, actualReps: reps);
      return s.complete(now: at);
    }

    test('returns the most recent completed session\'s done sets for the exercise', () {
      final older = completedBench(id: 'old', at: DateTime(2026, 8, 10), weight: 60, reps: 8);
      final newer = completedBench(id: 'new', at: DateTime(2026, 8, 15), weight: 62.5, reps: 8);

      final perf = lastPerformanceFor('ex1', [older, newer]);
      expect(perf, isNotNull);
      expect(perf!.performedAt, DateTime(2026, 8, 15));
      expect(perf.sets.first.actualWeightKg, 62.5);
      expect(perf.topWeightKg, 62.5);
    });

    test('ignores active/abandoned sessions and unknown exercises', () {
      final active = LiveSession.start(_day, id: 'a', planId: 'p1', now: _t0);
      final abandoned = completedBench(id: 'ab', at: DateTime(2026, 8, 1), weight: 50, reps: 8)
          .copyWith(status: SessionStatus.abandoned);

      expect(lastPerformanceFor('ex1', [active, abandoned]), isNull);
      expect(lastPerformanceFor('nope', []), isNull);
    });
  });
}
