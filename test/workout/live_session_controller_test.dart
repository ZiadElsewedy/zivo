import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
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

  test('a day with no sets settles straight into completed', () {
    final c = _controller(day: const WorkoutDay(
      id: 'a',
      slot: 'A',
      label: 'Push',
      order: 0,
      exercises: [],
    ));
    addTearDown(c.dispose);

    c.start();

    expect(c.session.isComplete, isTrue);
    // No warm-up for a session there is nothing to warm up for.
    expect(c.warmupRemaining, isNull);
  });

  test('a fresh session opens on the warm-up phase; a resumed one does not', () {
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
  });

  test('marking a set done logs the typed actuals and starts rest', () async {
    final clock = _Clock(DateTime(2026, 3, 1, 10));
    final c = _controller(now: clock.now);
    addTearDown(c.dispose);
    c.start();
    c.endWarmup();

    c.reps.text = '8';
    c.weight.text = '62.5';
    c.setDone(reducedMotion: true); // no completion-beat hold under reduced motion

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

  test('back() reverses the last resolved set, including a completing one', () async {
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
  });

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
      reason: 'an untouched session is indistinguishable from never starting one',
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
