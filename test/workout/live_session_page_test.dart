import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_repository.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_repository.dart';
import 'package:zivo/features/workout/domain/workout_session_repository.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/presentation/pages/live_session_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// Records what the player writes, so tests can assert the completion path
/// persists and the discard path writes nothing.
class _RecordingWorkoutRepository implements WorkoutRepository {
  final List<Workout> added = [];

  @override
  List<Workout> get current => added;

  @override
  Stream<List<Workout>> watchAll() => Stream.value(added);

  @override
  Future<void> add(Workout workout) async {
    // A small artificial delay widens the async window enough for a rapid
    // double-tap on Finish to actually race, so the re-entrancy guard has
    // something real to prove.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    added.add(workout);
  }

  @override
  Future<void> update(Workout workout) async {}

  @override
  Future<void> remove(String id) async {}
}

class _RecordingWorkoutPlanRepository implements WorkoutPlanRepository {
  final List<WorkoutPlan> saved = [];
  WorkoutPlan? _active;

  @override
  WorkoutPlan? get activePlan => _active;

  @override
  Stream<WorkoutPlan?> watchActivePlan() => Stream.value(_active);

  @override
  Future<void> savePlan(WorkoutPlan plan) async {
    saved.add(plan);
    _active = plan;
  }

  @override
  Future<void> deletePlan(String id) async {}
}

WorkoutPlan _plan() => WorkoutPlan(
  id: 'p1',
  name: 'Test Split',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  cycleCursor: 0,
  days: const [
    WorkoutDay(
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
            PlannedSet(order: 0, repTarget: RepTarget.fixed(5), restSeconds: 90, type: SetType.working),
            PlannedSet(order: 1, repTarget: RepTarget.fixed(5), restSeconds: 60, type: SetType.working),
          ],
        ),
      ],
    ),
    WorkoutDay(id: 'b', slot: 'B', label: 'Pull', order: 1, exercises: []),
  ],
);

/// A completed session from "last time", trained on the same canonical
/// exercise id ('ex1') so `lastPerformanceFor` picks it up.
LiveSession _previousSession() => LiveSession(
  id: 'prev1',
  planId: 'p1',
  dayId: 'a',
  dayLabel: 'Push',
  startedAt: DateTime(2026, 1, 1, 9),
  completedAt: DateTime(2026, 1, 1, 10),
  status: SessionStatus.completed,
  exercises: const [
    SessionExercise(
      id: 'ex1',
      exerciseId: 'ex1',
      name: 'Bench',
      restSeconds: 90,
      sets: [
        LoggedSet(
          id: 's0',
          target: RepTarget.fixed(5),
          done: true,
          actualReps: 5,
          actualWeightKg: 55,
        ),
        LoggedSet(
          id: 's1',
          target: RepTarget.fixed(5),
          done: true,
          actualReps: 5,
          actualWeightKg: 57.5,
        ),
      ],
    ),
  ],
);

Widget _wrap({
  required WorkoutRepository workouts,
  required WorkoutPlanRepository workoutPlans,
  required WorkoutSessionRepository workoutSessions,
  required WorkoutDay day,
  required WorkoutPlan plan,
  LiveSession? resume,
  DateTime Function()? now,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: workouts,
    workoutPlans: workoutPlans,
    workoutSessions: workoutSessions,
    university: InMemoryUniversityRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      LiveSessionPage(day: day, plan: plan, resume: resume, now: now),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// [LiveSessionPage] wraps its current-set/rest indicators in *repeating*
/// animation controllers (the ember pulse, the rest breathing scale) that
/// never settle on their own — `pumpAndSettle` would hang while either view
/// is on screen, so every step advances by a fixed, generous duration instead.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets(
    'happy path: start → previous performance + delta → done → rest (±15s) → '
    'skip → complete → finish persists + advances',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      await sessions.saveSession(_previousSession());
      final plan = _plan();

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
        ),
      );
      await tester.tap(find.text('go'));
      await _settle(tester);

      // Set 1 of the first exercise, previous performance shown inline.
      expect(find.text('SET 1 OF 2'), findsOneWidget);
      expect(find.text('Bench'), findsOneWidget);
      expect(find.text('Previous 55kg × 5'), findsOneWidget);

      // Autosaved as an active session as soon as it starts.
      expect(sessions.current.any((s) => s.status == SessionStatus.active), isTrue);

      // Type a heavier weight than last time → the Pulse progression delta.
      // Reps is the first TextField (index 0), Weight the second (index 1).
      await tester.enterText(find.byType(TextField).at(1), '60');
      await tester.pump();
      expect(find.text('+5kg'), findsOneWidget);

      // Complete set 1 → rest countdown (90s → "1:30"), warm gray "Rest".
      await tester.tap(find.text('Done'));
      await _settle(tester);
      expect(find.text('Skip rest'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
      expect(find.text('REST'), findsOneWidget);
      expect(find.textContaining('Next:'), findsOneWidget);

      // The just-logged set now shows as done (autosaved).
      final midSession = sessions.current.firstWhere((s) => s.status == SessionStatus.active);
      expect(midSession.exercises.single.sets[0].done, isTrue);
      expect(midSession.exercises.single.sets[0].actualWeightKg, 60);

      // Adjust the rest window.
      await tester.tap(find.text('+15s'));
      await tester.pump();
      expect(find.text('1:45'), findsOneWidget);
      await tester.tap(find.text('-15s'));
      await tester.pump();
      expect(find.text('1:30'), findsOneWidget);

      // Skip the rest → set 2 (already the current set — no manual pointer).
      await tester.tap(find.text('Skip rest'));
      await _settle(tester);
      expect(find.text('SET 2 OF 2'), findsOneWidget);
      expect(find.text('Previous 57.5kg × 5'), findsOneWidget);

      // Complete the final set → completed summary.
      await tester.tap(find.text('Done'));
      await _settle(tester);
      expect(find.text('Finish'), findsOneWidget);
      expect(find.textContaining('2 of 2 sets'), findsOneWidget);

      // Finish → history written + cursor advanced + session marked completed,
      // then popped back to the launcher (nothing infinite left mid-transition).
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();

      expect(find.text('go'), findsOneWidget); // popped
      expect(workouts.added, hasLength(1));
      expect(workouts.added.single.title, 'Push');
      expect(plans.saved, hasLength(1));
      expect(plans.saved.single.cycleCursor, 1); // advanced 0 → 1
      final finished = sessions.current.firstWhere((s) => s.id != 'prev1');
      expect(finished.status, SessionStatus.completed);
    },
  );

  testWidgets('discard via the trailing trash button erases autosaved progress and pops', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await tester.tap(find.text('go'));
    await _settle(tester);

    // Log a set, so there is autosaved progress to actually discard.
    await tester.tap(find.text('Done'));
    await _settle(tester);
    expect(sessions.current, hasLength(1));

    // Discard is the explicit destructive action, reached via the top bar's
    // trailing trash control — not the close (X) button, which now leaves.
    await tester.tap(find.byTooltip('Discard workout'));
    await _settle(tester);
    expect(find.text('Discard this workout?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('go'), findsOneWidget); // popped
    expect(workouts.added, isEmpty);
    expect(plans.saved, isEmpty);
    expect(sessions.current, isEmpty); // erased, not just left active
  });

  testWidgets('closing (X) with logged progress leaves the session active for Resume', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await tester.tap(find.text('go'));
    await _settle(tester);

    await tester.tap(find.text('Done'));
    await _settle(tester);
    expect(sessions.current, hasLength(1));

    // Close (X) is now non-destructive: no confirmation dialog, and the
    // autosaved progress (including the plan's un-advanced cursor) stays put.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('go'), findsOneWidget); // popped
    expect(find.text('Discard this workout?'), findsNothing);
    expect(workouts.added, isEmpty); // never finished
    expect(plans.saved, isEmpty); // cursor not advanced
    final left = sessions.current.single;
    expect(left.status, SessionStatus.active);
    expect(left.exercises.single.sets[0].done, isTrue); // the logged set survived

    // Resuming re-opens the exact same in-progress session rather than a
    // fresh one — set 1 already done, straight onto set 2.
    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
        resume: left,
      ),
    );
    await tester.tap(find.text('go'));
    await _settle(tester);
    expect(find.text('SET 2 OF 2'), findsOneWidget);
    expect(sessions.current, hasLength(1)); // no duplicate session created
  });

  testWidgets('closing (X) with zero logged sets is a silent discard', (tester) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await tester.tap(find.text('go'));
    await _settle(tester);
    expect(sessions.current, hasLength(1)); // autosaved as soon as it starts

    // Nothing logged yet — closing must not leave a resumable, empty session.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('go'), findsOneWidget); // popped
    expect(find.text('Discard this workout?'), findsNothing); // no confirmation either
    expect(sessions.current, isEmpty);
  });

  testWidgets('the rest countdown auto-advances to the next set when it reaches zero', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();
    var fakeNow = DateTime(2026, 1, 1, 8);

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
        now: () => fakeNow,
      ),
    );
    await tester.tap(find.text('go'));
    await _settle(tester);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('1:30'), findsOneWidget);

    // Let the countdown run out (driven by wall-clock elapsed time, not tick
    // count — advance the clock alongside the pumped duration).
    fakeNow = fakeNow.add(const Duration(seconds: 91));
    await tester.pump(const Duration(seconds: 91));
    expect(find.text('SET 2 OF 2'), findsOneWidget);
  });

  testWidgets(
    'the rest countdown resyncs from wall-clock time on app resume, surviving '
    "a backgrounded/suspended timer",
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      final plan = _plan();
      var fakeNow = DateTime(2026, 1, 1, 8);

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
          now: () => fakeNow,
        ),
      );
      await tester.tap(find.text('go'));
      await _settle(tester);

      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(find.text('1:30'), findsOneWidget); // 90s rest window

      // Simulate the OS suspending the app's Timer for 40s while backgrounded
      // — no ticks fire, only wall-clock time passes — then resuming.
      fakeNow = fakeNow.add(const Duration(seconds: 40));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // Resyncs to the real elapsed time on resume instead of staying frozen
      // at 1:30 (what a plain tick-counter would show).
      expect(find.text('0:50'), findsOneWidget);

      // And ending naturally still works post-resume.
      fakeNow = fakeNow.add(const Duration(seconds: 50));
      await tester.pump(const Duration(seconds: 50));
      expect(find.text('SET 2 OF 2'), findsOneWidget);
    },
  );

  testWidgets('an empty day settles straight into the completed view', (tester) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();
    final emptyDay = plan.days.last; // 'Pull', no exercises

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: emptyDay,
        plan: plan,
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle(); // no repeating controllers in the completed view

    expect(find.text('WORKOUT COMPLETE'), findsOneWidget); // _Eyebrow uppercases
    expect(find.text('Finish'), findsOneWidget);
  });

  testWidgets('rapid double-tap on Finish only writes history and advances the cursor once', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await tester.tap(find.text('go'));
    await _settle(tester);

    await tester.tap(find.text('Done'));
    await _settle(tester);
    await tester.tap(find.text('Skip rest'));
    await _settle(tester);
    await tester.tap(find.text('Done'));
    await _settle(tester);
    expect(find.text('Finish'), findsOneWidget);

    // Two rapid taps before the first Finish's (artificially delayed) writes
    // resolve — the second must be a no-op, not a duplicate write.
    await tester.tap(find.text('Finish'));
    await tester.pump();
    await tester.tap(find.text('Finish'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();

    expect(workouts.added, hasLength(1));
    expect(plans.saved, hasLength(1));
    expect(plans.saved.single.cycleCursor, 1);
  });

  testWidgets('the system back gesture leaves like the close button (non-destructive)', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await tester.tap(find.text('go'));
    await _settle(tester);
    await tester.tap(find.text('Done'));
    await _settle(tester);

    // Simulate the OS back gesture/button rather than tapping the close icon.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Intercepted like the close button: pops straight through, no discard
    // dialog, and the logged progress survives (Resume-able).
    expect(find.text('Discard this workout?'), findsNothing);
    expect(find.text('go'), findsOneWidget);
    expect(sessions.current.single.status, SessionStatus.active);
  });

  testWidgets(
    'force-kill recovery: a session left active by a killed app never contaminates '
    'previous-performance',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      final plan = _plan();

      // Simulates a force-kill mid-session: autosave captured real progress
      // (a done set with actuals) but the process died before Finish/Discard
      // or even dispose() ran — the doc is still "active", not "completed".
      await sessions.saveSession(
        LiveSession(
          id: 'killed-session',
          planId: 'p1',
          dayId: 'a',
          dayLabel: 'Push',
          startedAt: DateTime(2026, 1, 1, 8),
          status: SessionStatus.active,
          exercises: const [
            SessionExercise(
              id: 'ex1',
              exerciseId: 'ex1',
              name: 'Bench',
              restSeconds: 90,
              sets: [
                LoggedSet(
                  id: 'ex1-s0',
                  target: RepTarget.fixed(5),
                  done: true,
                  actualReps: 5,
                  actualWeightKg: 999, // deliberately extreme — must never surface
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
        ),
      );
      await tester.tap(find.text('go'));
      await _settle(tester);

      // lastPerformanceFor only trusts *completed* sessions — a killed,
      // still-"active" session's actuals must never surface as "previous
      // performance" or feed the progression delta.
      expect(find.textContaining('999'), findsNothing);
      expect(find.textContaining('Previous'), findsNothing);

      // No blind orphan cleanup any more (that would delete the very session
      // Resume is meant to bring back) — the killed session is left as-is
      // alongside the fresh one this screen started.
      expect(sessions.current.any((s) => s.id == 'killed-session'), isTrue);
      expect(sessions.current.where((s) => s.status == SessionStatus.active), hasLength(2));
    },
  );
}
