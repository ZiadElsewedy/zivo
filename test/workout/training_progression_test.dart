import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zivo/core/util/calendar.dart';
import 'package:zivo/features/home/domain/today_pulse.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/training_dashboard_stats.dart';
import 'package:zivo/features/workout/domain/training_streak.dart';
import 'package:zivo/features/workout/domain/up_next_selection.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/controllers/live_session_controller.dart';

/// The one mental model, end to end through the real session controller:
///
///   TRAIN        → a session is created → the rotation advances.
///   DON'T TRAIN  → no session → the rotation waits.
///
/// Workout PROGRESSION (sessions, the cursor) and CALENDAR adherence (which
/// days had training) are two separate things, asserted separately below.

WorkoutDay _day(String id, int order) => WorkoutDay(
  id: id,
  slot: id.toUpperCase(),
  label: id,
  order: order,
  exercises: const [
    PlannedExercise(
      id: 'bench',
      name: 'Bench',
      order: 0,
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

final _ppl = WorkoutPlan(
  id: 'ppl',
  name: 'PPL',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 1),
  cycleCursor: 0,
  days: [_day('push', 0), _day('pull', 1), _day('legs', 2)],
);

class _Ticks implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

/// Sep 21, 22, 23, 24 at 10:00.
DateTime _sep(int day, [int hour = 10]) => DateTime(2026, 9, day, hour);

class _Harness {
  _Harness() {
    plans.savePlan(_ppl);
  }

  final plans = InMemoryWorkoutPlanRepository();
  final sessions = InMemoryWorkoutSessionRepository();
  final workouts = InMemoryWorkoutRepository();

  WorkoutPlan get plan => plans.activePlan!;

  /// What Today's card offers at [now] — the same call Today makes.
  String? upNext(DateTime now) =>
      resolveUpNext(plan, sessions.activeSession, now: now).day?.id;

  /// Starts the due workout, logs one working set, finishes — the real path.
  Future<void> train(DateTime at) async {
    var clock = at;
    final day = resolveUpNext(plan, sessions.activeSession, now: at).day!;
    final c = LiveSessionController(
      day: day,
      plan: plan,
      sessions: sessions,
      vsync: _Ticks(),
      now: () => clock,
    );
    c.start();
    c.reps.text = '5';
    c.weight.text = '60';
    clock = clock.add(const Duration(minutes: 5));
    c.setDone(reducedMotion: true);
    clock = clock.add(const Duration(minutes: 30));
    expect(c.finishNow(workouts: workouts, plans: plans), isTrue);
    await Future<void>.delayed(Duration.zero);
    c.dispose();
  }

  int get completedSessions => computeTrainingDashboardStats(
    sessions: sessions.current,
    now: _sep(30),
  ).totalCompletedSessions;

  void dispose() => plans.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Harness h;
  setUp(() {
    // The session persists its rest countdown to device prefs.
    SharedPreferences.setMockInitialValues({});
    h = _Harness();
  });
  tearDown(() => h.dispose());

  test(
    'completing a workout creates one session and advances the rotation',
    () async {
      expect(h.upNext(_sep(21)), 'push');
      await h.train(_sep(21));
      expect(h.sessions.current, hasLength(1));
      expect(h.sessions.current.single.dayId, 'push');
      expect(h.upNext(_sep(21, 18)), 'pull');
    },
  );

  test(
    "not training creates no session, and tomorrow the same workout waits",
    () async {
      await h.train(_sep(21));
      // Sep 22: the user doesn't train. Nothing is written for the day.
      expect(h.upNext(_sep(22)), 'pull');
      expect(h.sessions.current, hasLength(1));
      // Sep 23: still Pull — a calendar day passing never moves the rotation.
      expect(h.upNext(_sep(23)), 'pull');
      expect(h.plan.cycleCursor, 1);
    },
  );

  test('training the next day increments the count and advances', () async {
    await h.train(_sep(21)); // Push
    await h.train(_sep(23)); // Pull — Sep 22 had nothing
    await h.train(_sep(24)); // Legs
    expect(h.sessions.current.map((s) => s.dayId).toSet(), {
      'push',
      'pull',
      'legs',
    });
    expect(h.completedSessions, 3, reason: 'sequential: one per real session');
    expect(h.upNext(_sep(25)), 'push', reason: 'the cycle wrapped');
  });

  test(
    'a missed calendar day is never a session, and never numbered as one',
    () async {
      await h.train(_sep(21));
      await h.train(_sep(23));
      final days = {
        for (final s in h.sessions.current) startOfDay(s.completedAt!),
      };
      expect(days, {DateTime(2026, 9, 21), DateTime(2026, 9, 23)});
      expect(
        h.sessions.current.where(
          (s) => startOfDay(s.startedAt) == DateTime(2026, 9, 22),
        ),
        isEmpty,
      );
      expect(h.completedSessions, 2);
    },
  );

  test(
    'calendar adherence sees the inactive day; progression does not',
    () async {
      await h.train(_sep(21));
      await h.train(_sep(23));
      await h.train(_sep(24));

      // Calendar: Sep 21 ✅ · Sep 22 — · Sep 23 ✅ · Sep 24 ✅
      final week = weekActivity(h.sessions.current, _sep(24, 20), days: 4);
      expect([for (final d in week) d.workouts], [1, 0, 1, 1]);

      // The streak reads the same history: Sep 22 is a day off inside the
      // allowance, not a session and not a break.
      final streak = computeTrainingStreak(
        sessions: h.sessions.current,
        now: _sep(24, 20),
      );
      expect(streak.currentDays, 3);
      final sep22 = streak.days.singleWhere(
        (d) => d.day == DateTime(2026, 9, 22),
      );
      expect(sep22.isTrained, isFalse);
      expect(sep22.sessionCount, 0);

      // Progression: three sessions, Push → Pull → Legs, whatever the calendar.
      expect(h.completedSessions, 3);
      expect(h.upNext(_sep(25)), 'push');
    },
  );
}
