import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/workout.dart';
import 'package:zivo/features/workout/domain/workout_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_outcome.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/controllers/live_session_controller.dart';

/// The session rules, asserted directly.
///
/// Every one of these used to require pumping [LiveSessionPage] with a fake
/// clock and finding widgets by key, because the rules lived inside the
/// page's `State`. They are statements about the session, not about the
/// screen, so they belong here — the widget tests in
/// `live_session_page_test.dart` still cover what the screen *shows*.
void main() {
  setUp(() {
    // The controller drives real `Ticker`s and persists the rest countdown
    // through `SharedPreferences`; both need a binding, neither needs a
    // widget tree.
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  _carryForwardTests();
  _finishNowTests();
  _backgroundClockTests();

  test('a day with no sets settles straight into completed', () {
    final c = _controller(
      day: const WorkoutDay(
        id: 'a',
        slot: 'A',
        label: 'Push',
        order: 0,
        exercises: [],
      ),
    );
    addTearDown(c.dispose);

    c.start();

    expect(c.session.isComplete, isTrue);
    // No warm-up for a session there is nothing to warm up for.
    expect(c.warmupRemaining, isNull);
  });

  test(
    'a fresh session opens on the warm-up phase; a resumed one does not',
    () {
      final fresh = _controller();
      addTearDown(fresh.dispose);
      fresh.start();
      expect(fresh.warmupRemaining, isNotNull);

      final resumed = _controller(resume: _startedSession());
      addTearDown(resumed.dispose);
      resumed.start();
      expect(
        resumed.warmupRemaining,
        isNull,
        reason: 'resuming is not "before your first set"',
      );
    },
  );

  test('marking a set done logs the typed actuals and starts rest', () async {
    final clock = _Clock(DateTime(2026, 3, 1, 10));
    final c = _controller(now: clock.now);
    addTearDown(c.dispose);
    c.start();
    c.endWarmup();

    c.reps.text = '8';
    c.weight.text = '62.5';
    c.setDone(
      reducedMotion: true,
    ); // no completion-beat hold under reduced motion

    final logged = c.session.exercises.first.sets.first;
    expect(logged.done, isTrue);
    expect(logged.actualReps, 8);
    expect(logged.actualWeightKg, 62.5);
  });

  test('a comma decimal is accepted as a weight', () {
    final c = _controller();
    addTearDown(c.dispose);
    c.start();
    c.endWarmup();

    c.reps.text = '8';
    c.weight.text = '62,5';
    c.setDone(reducedMotion: true);

    expect(c.session.exercises.first.sets.first.actualWeightKg, 62.5);
  });

  test(
    'back() reverses the last resolved set, including a completing one',
    () async {
      final c = _controller(day: _oneSetDay());
      addTearDown(c.dispose);
      c.start();
      c.endWarmup();

      c.reps.text = '5';
      c.setDone(reducedMotion: true);
      await Future<void>.delayed(Duration.zero);
      expect(c.session.isComplete, isTrue);

      c.back();

      expect(
        c.session.isComplete,
        isFalse,
        reason: 'undo must be able to reverse the very last set of a workout',
      );
      expect(c.session.exercises.first.sets.first.done, isFalse);
    },
  );

  test('pause freezes the rest countdown and resume restores it', () async {
    final clock = _Clock(DateTime(2026, 3, 1, 10));
    final c = _controller(now: clock.now);
    addTearDown(c.dispose);
    c.start();
    c.endWarmup();
    c.reps.text = '5';
    c.setDone(reducedMotion: true);
    await Future<void>.delayed(Duration.zero);

    final beforePause = c.restRemaining;
    expect(beforePause, isNotNull);

    c.togglePause();
    clock.advance(const Duration(seconds: 30));
    expect(
      c.restRemaining,
      beforePause,
      reason: 'a paused countdown must not bleed away while paused',
    );

    c.togglePause();
    expect(c.restRemaining, beforePause);
  });

  test('adjusting rest past its remaining time ends the rest', () async {
    final c = _controller();
    addTearDown(c.dispose);
    c.start();
    c.endWarmup();
    c.reps.text = '5';
    c.setDone(reducedMotion: true);
    await Future<void>.delayed(Duration.zero);
    expect(c.restRemaining, isNotNull);

    c.adjustRest(-1000);

    expect(c.restRemaining, isNull);
  });

  test('leave() discards a session with nothing logged and no draft', () async {
    final sessions = InMemoryWorkoutSessionRepository();
    final c = _controller(sessions: sessions);
    addTearDown(c.dispose);
    c.start();
    await Future<void>.delayed(Duration.zero);

    expect(c.leave(), isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(
      sessions.current.where((s) => s.id == c.session.id),
      isEmpty,
      reason:
          'an untouched session is indistinguishable from never starting one',
    );
  });

  test('leave() keeps a session that has only a typed draft', () async {
    final sessions = InMemoryWorkoutSessionRepository();
    final c = _controller(sessions: sessions);
    addTearDown(c.dispose);
    c.start();
    c.endWarmup();

    c.reps.text = '7';
    c.onActualChanged();
    expect(c.leave(), isTrue); // flushes the pending debounce synchronously
    await Future<void>.delayed(Duration.zero);

    expect(
      sessions.current.map((s) => s.id),
      contains(c.session.id),
      reason: 'a typed-but-not-done draft must never be discarded as "empty"',
    );
    expect(c.session.exercises.first.sets.first.actualReps, 7);
  });

  test('leave() and finish() are guarded against a second call', () {
    final c = _controller();
    addTearDown(c.dispose);
    c.start();

    expect(c.leave(), isTrue);
    expect(c.leave(), isFalse, reason: 'a double-tap must not pop twice');
  });
}

// ---- Fixtures ---------------------------------------------------------------

class _Clock {
  _Clock(this._at);
  DateTime _at;
  DateTime now() => _at;
  void advance(Duration d) => _at = _at.add(d);
}

/// A no-op [TickerProvider]: these tests assert state transitions, not frames,
/// and a real ticker would need a live scheduler.
class _NoopTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

// ---- The load carry-forward -------------------------------------------------
//
// `computeGoal` only suggests a weight when it has an index-aligned set from
// the last time the exercise was trained, or a `targetWeightKg` on the plan.
// A split written without loads has neither, so before this the weight field
// was empty on every single set, forever — which is both pure re-typing and
// the reason sets ended up logged with no load at all.

void _carryForwardTests() {
  test('the weight typed on one set carries to the next set of the same '
      'exercise', () async {
    final c = _controller();
    addTearDown(c.dispose);
    c.start();
    c.endWarmup();

    expect(
      c.weight.text,
      isEmpty,
      reason: 'the very first set has genuinely nothing to go on',
    );

    c.reps.text = '5';
    c.weight.text = '20';
    c.setDone(reducedMotion: true);
    await Future<void>.delayed(Duration.zero);

    expect(c.weight.text, '20', reason: 'you type a load once, not per set');
  });

  test('the last load is carried in when the progression engine cannot price '
      'the set (a load logged without a rep count)', () async {
    final sessions = InMemoryWorkoutSessionRepository(
      seed: [_historyWithA(alignedReps: null, alignedWeight: 40)],
    );
    final c = _controller(sessions: sessions);
    addTearDown(c.dispose);
    c.start();
    // The history subscription lands asynchronously and re-runs the prefill.
    await Future<void>.delayed(Duration.zero);
    c.endWarmup();

    expect(
      c.weight.text,
      '40',
      reason: 'no reps to progress from, but the load is not a mystery',
    );
  });

  test('a carried load is a suggestion, not a draft — nothing is persisted '
      'until the set is committed', () async {
    final sessions = InMemoryWorkoutSessionRepository(
      seed: [_historyWithA(alignedReps: null, alignedWeight: 40)],
    );
    final c = _controller(sessions: sessions);
    addTearDown(c.dispose);
    c.start();
    await Future<void>.delayed(Duration.zero);
    c.endWarmup();

    expect(c.weight.text, '40');
    expect(
      c.session.exercises.first.sets.first.actualWeightKg,
      isNull,
      reason: 'a prefilled suggestion must not read back as logged data',
    );
  });

  test('index alignment failing does not lose the load: any set of that '
      'history still counts', () async {
    // Last time, set 0 was done at 40kg and set 1 was done unweighted — so
    // today's set 1 aligns with a set that carries no load at all. Index
    // alignment breaks like this the moment a set is added or dropped, and
    // last week's 40kg is still the honest answer when it does.
    final sessions = InMemoryWorkoutSessionRepository(
      seed: [
        _historyWithA(alignedReps: 5, alignedWeight: 40, secondWeight: null),
      ],
    );
    final c = _controller(sessions: sessions);
    addTearDown(c.dispose);
    c.start();
    await Future<void>.delayed(Duration.zero);

    final exercise = c.session.exercises.first;
    expect(c.carriedWeightFor(exercise, exercise.sets[1]), 40);
  });

  test('nothing is invented for a movement that has never carried a load', () {
    final c = _controller();
    addTearDown(c.dispose);
    c.start();
    c.endWarmup();

    expect(c.weight.text, isEmpty);
  });
}

/// A completed session for the same exercise ('ex1'), shaped per test: what
/// today's index-aligned set will line up against, plus a second set.
LiveSession _historyWithA({
  required int? alignedReps,
  required double? alignedWeight,
  double? secondWeight,
}) => LiveSession(
  id: 'prev1',
  planId: 'p1',
  dayId: 'a',
  dayLabel: 'Push',
  startedAt: DateTime(2026, 1, 1, 9),
  completedAt: DateTime(2026, 1, 1, 10),
  status: SessionStatus.completed,
  exercises: [
    SessionExercise(
      id: 'ex1',
      exerciseId: 'ex1',
      name: 'Bench',
      restSeconds: 90,
      sets: [
        LoggedSet(
          id: 's0',
          target: const RepTarget.fixed(5),
          outcome: SetOutcome.completed,
          actualReps: alignedReps,
          actualWeightKg: alignedWeight,
        ),
        LoggedSet(
          id: 's1',
          target: const RepTarget.fixed(5),
          outcome: SetOutcome.completed,
          actualReps: 5,
          actualWeightKg: secondWeight,
        ),
      ],
    ),
  ],
);

LiveSessionController _controller({
  WorkoutDay? day,
  LiveSession? resume,
  InMemoryWorkoutSessionRepository? sessions,
  DateTime Function()? now,
}) {
  final theDay = day ?? _day();
  return LiveSessionController(
    day: theDay,
    plan: _plan(theDay),
    sessions: sessions ?? InMemoryWorkoutSessionRepository(),
    vsync: _NoopTickerProvider(),
    now: now ?? () => DateTime(2026, 3, 1, 10),
    resume: resume,
  );
}

WorkoutDay _day() => const WorkoutDay(
  id: 'a',
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
        PlannedSet(
          order: 0,
          repTarget: RepTarget.fixed(5),
          restSeconds: 90,
          type: SetType.working,
        ),
        PlannedSet(
          order: 1,
          repTarget: RepTarget.fixed(5),
          restSeconds: 90,
          type: SetType.working,
        ),
      ],
    ),
  ],
);

/// A day with exactly one set, so a single Done completes the session.
WorkoutDay _oneSetDay() => const WorkoutDay(
  id: 'a',
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
        PlannedSet(
          order: 0,
          repTarget: RepTarget.fixed(5),
          restSeconds: 90,
          type: SetType.working,
        ),
      ],
    ),
  ],
);

WorkoutPlan _plan(WorkoutDay day) => WorkoutPlan(
  id: 'p1',
  name: 'Test Split',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  cycleCursor: 0,
  days: [day],
);

LiveSession _startedSession() => LiveSession.start(
  _day(),
  id: 's1',
  planId: 'p1',
  now: DateTime(2026, 3, 1, 9),
);

// ---------------------------------------------------------------------------

/// FINISH NOW — the exit that was missing, and the promise it has to keep.
void _finishNowTests() {
  group('finishNow', () {
    test('ends the session at now, with sets still pending', () {
      var clock = DateTime(2026, 3, 1, 10);
      final sessions = InMemoryWorkoutSessionRepository();
      final c = _controller(sessions: sessions, now: () => clock);
      addTearDown(c.dispose);
      c.start();

      c.reps.text = '8';
      c.weight.text = '60';
      clock = clock.add(const Duration(minutes: 12));
      c.setDone(reducedMotion: true);

      clock = clock.add(const Duration(minutes: 36));
      final workouts = _RecordingWorkoutRepository();
      final plans = InMemoryWorkoutPlanRepository();
      addTearDown(plans.dispose);

      expect(c.finishNow(workouts: workouts, plans: plans), isTrue);

      expect(c.session.status, SessionStatus.completed);
      expect(c.session.completedAt, clock);
      expect(c.session.elapsed, const Duration(minutes: 48));
      expect(c.session.durationSource, DurationSource.measured);
    });

    test('logs NOTHING the user did not — no sets, weights or completions', () {
      var clock = DateTime(2026, 3, 1, 10);
      final c = _controller(now: () => clock);
      addTearDown(c.dispose);
      c.start();

      final totalSets = c.session.totalSets;
      c.reps.text = '8';
      c.weight.text = '60';
      clock = clock.add(const Duration(minutes: 5));
      c.setDone(reducedMotion: true);

      clock = clock.add(const Duration(minutes: 20));
      final plans = InMemoryWorkoutPlanRepository();
      addTearDown(plans.dispose);
      c.finishNow(workouts: _RecordingWorkoutRepository(), plans: plans);

      expect(c.session.completedSetCount, 1);
      expect(c.session.totalSets, totalSets, reason: 'no set was added');
      expect(
        c.session.allSets.where((s) => s.skipped),
        isEmpty,
        reason: 'a pending set is NOT a skipped one — skipping is a choice',
      );
      for (final set in c.session.allSets.where((s) => s.pending)) {
        expect(set.actualReps, isNull);
        expect(set.actualWeightKg, isNull);
        expect(set.resolvedAt, isNull);
      }
    });

    test('the finished session still counts as a day trained', () {
      var clock = DateTime(2026, 3, 1, 10);
      final c = _controller(now: () => clock);
      addTearDown(c.dispose);
      c.start();
      c.reps.text = '8';
      c.weight.text = '60';
      clock = clock.add(const Duration(minutes: 5));
      c.setDone(reducedMotion: true);

      final plans = InMemoryWorkoutPlanRepository();
      addTearDown(plans.dispose);
      c.finishNow(workouts: _RecordingWorkoutRepository(), plans: plans);

      expect(c.session.hasCompletedWorkingSet, isTrue);
    });

    test('refuses a second call while the first is in flight', () {
      final c = _controller();
      addTearDown(c.dispose);
      c.start();
      final plans = InMemoryWorkoutPlanRepository();
      addTearDown(plans.dispose);
      final workouts = _RecordingWorkoutRepository();

      expect(c.finishNow(workouts: workouts, plans: plans), isTrue);
      expect(c.finishNow(workouts: workouts, plans: plans), isFalse);
    });
  });
}

// ---------------------------------------------------------------------------

/// The background clock — the fix at the source for the nineteen-hour session.
void _backgroundClockTests() {
  group('time spent in the background', () {
    test('a long absence is folded into the paused total, not into training', () {
      var clock = DateTime(2026, 3, 1, 10);
      final c = _controller(now: () => clock);
      addTearDown(c.dispose);
      c.start();
      c.reps.text = '8';
      c.weight.text = '60';
      clock = clock.add(const Duration(minutes: 30));
      c.setDone(reducedMotion: true);

      // Phone locked, user goes home, opens the app the next morning.
      c.onAppPaused();
      clock = clock.add(const Duration(hours: 14));
      c.onAppResumed();

      // The workout was 30 minutes; the app was away for 14 hours. What
      // survives is those 30 minutes plus the grace window — the app does not
      // claim to know the user left the moment the screen went off, so the
      // first `kStaleInactivityGrace` of any absence is still counted as
      // training. Everything past it is not.
      expect(
        c.session.activeElapsed(now: clock),
        const Duration(minutes: 30) + kStaleInactivityGrace,
      );
      expect(
        c.session.pausedAccum,
        const Duration(hours: 14) - kStaleInactivityGrace,
      );
    });

    test('a glance at a notification is not deducted from the workout', () {
      var clock = DateTime(2026, 3, 1, 10);
      final c = _controller(now: () => clock);
      addTearDown(c.dispose);
      c.start();

      c.onAppPaused();
      clock = clock.add(const Duration(seconds: 40));
      c.onAppResumed();

      expect(
        c.session.pausedAccum,
        Duration.zero,
        reason: 'inside the grace window — the user is still in the gym',
      );
    });

    test('a rest that was counting down while away is not deducted', () async {
      var clock = DateTime(2026, 3, 1, 10);
      final c = _controller(now: () => clock);
      addTearDown(c.dispose);
      c.start();
      c.endWarmup();
      c.reps.text = '8';
      c.weight.text = '60';
      c.setDone(reducedMotion: true);
      await Future<void>.delayed(Duration.zero);
      expect(c.restRemaining, isNotNull, reason: 'a rest is running');

      // Phone locked through the rest and a little after — all of it is the
      // workout, so none of it should be deducted.
      c.onAppPaused();
      clock = clock.add(const Duration(minutes: 2));
      c.onAppResumed();

      expect(c.session.pausedAccum, Duration.zero);
    });

    test('a resume with no preceding pause changes nothing', () {
      var clock = DateTime(2026, 3, 1, 10);
      final c = _controller(now: () => clock);
      addTearDown(c.dispose);
      c.start();
      clock = clock.add(const Duration(hours: 5));

      c.onAppResumed();

      expect(c.session.pausedAccum, Duration.zero);
    });

    test('an explicitly paused session is left to its own pause bookkeeping', () {
      var clock = DateTime(2026, 3, 1, 10);
      final c = _controller(now: () => clock);
      addTearDown(c.dispose);
      c.start();
      c.togglePause();
      final pausedAt = c.session.pausedAt;

      c.onAppPaused();
      clock = clock.add(const Duration(hours: 6));
      c.onAppResumed();

      expect(c.session.pausedAt, pausedAt, reason: 'still the same open pause');
      expect(c.session.pausedAccumMs, 0, reason: 'not double-counted');
    });
  });
}

/// A [WorkoutRepository] that only needs to accept a write.
class _RecordingWorkoutRepository implements WorkoutRepository {
  final List<Workout> added = [];

  @override
  Future<void> add(Workout workout) async => added.add(workout);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
