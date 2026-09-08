import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
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
import 'package:zivo/features/workout/domain/workout_plan_repository.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_session_repository.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/pages/live_session_page.dart';
import 'package:zivo/features/workout/presentation/pages/workout_plan_page.dart';

import '../support/bidi_finders.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';
import '../support/inert_music_controller.dart';

/// A repository whose `watchActivePlan()` stream only emits when [emit]/[emitError]
/// is called, so tests can assert on the "waiting"/error states deterministically.
class _PendingWorkoutPlanRepository implements WorkoutPlanRepository {
  final StreamController<WorkoutPlan?> _controller = StreamController<WorkoutPlan?>.broadcast();
  final List<WorkoutPlan> saved = [];

  @override
  WorkoutPlan? get activePlan => null;

  @override
  Stream<WorkoutPlan?> watchActivePlan() => _controller.stream;

  @override
  Future<void> savePlan(WorkoutPlan plan) async {
    saved.add(plan);
    _controller.add(plan);
  }

  @override
  Future<void> deletePlan(String id) async {}

  @override
  List<WorkoutPlan> get splits =>
      activePlan == null ? const <WorkoutPlan>[] : <WorkoutPlan>[activePlan!];

  @override
  Stream<List<WorkoutPlan>> watchSplits() => Stream.value(splits);

  @override
  String? get activeSplitId => activePlan?.id;

  @override
  Future<void> setActiveSplit(String id) async {}

  @override
  Future<void> saveSplit(WorkoutPlan plan) => savePlan(plan);

  @override
  Future<void> deleteSplit(String id) => deletePlan(id);

  void emit(WorkoutPlan? plan) => _controller.add(plan);

  void emitError(Object error) => _controller.addError(error);

  void dispose() => _controller.close();
}

Widget _wrap({
  required Widget child,
  required WorkoutPlanRepository plansOverride,
  WorkoutSessionRepository? sessionsOverride,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: plansOverride,
    workoutSessions: sessionsOverride ?? InMemoryWorkoutSessionRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    // Music UI mounts in the session player now — the inert controller keeps
    // that wiring satisfied without any live playback.
    music: InertMusicController(),
    child: MaterialApp(home: child),
  );
}

/// A compact 3-day cycle (cursor on Day A) — small enough that every browse card
/// fits the test viewport, and exercising a range target with a weight so the
/// P0 set formatter has something to render.
WorkoutPlan _compactPlan() => WorkoutPlan(
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
          id: 'e1',
          name: 'Bench Press',
          order: 0,
          muscleGroup: 'Chest',
          defaultRestSeconds: 120,
          sets: [
            PlannedSet(
              order: 0,
              repTarget: RepTarget.range(6, 8),
              restSeconds: 120,
              targetWeightKg: 60,
              type: SetType.working,
            ),
          ],
        ),
      ],
    ),
    WorkoutDay(
      id: 'b',
      slot: 'B',
      label: 'Pull',
      order: 1,
      exercises: [
        PlannedExercise(
          id: 'e2',
          name: 'Deadlift',
          order: 0,
          defaultRestSeconds: 180,
          sets: [
            PlannedSet(order: 0, repTarget: RepTarget.fixed(5), restSeconds: 180, type: SetType.working),
          ],
        ),
      ],
    ),
    WorkoutDay(
      id: 'c',
      slot: 'C',
      label: 'Legs',
      order: 2,
      exercises: [
        PlannedExercise(
          id: 'e3',
          name: 'Back Squat',
          order: 0,
          defaultRestSeconds: 150,
          sets: [
            PlannedSet(order: 0, repTarget: RepTarget.fixed(6), restSeconds: 150, type: SetType.working),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets('renders the up-next day with its exercises and set summaries', (tester) async {
    final plans = _PendingWorkoutPlanRepository();
    addTearDown(plans.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutPlanPage(), plansOverride: plans));
    plans.emit(_compactPlan());
    await tester.pump();

    // The cursor points at Day A (order 0) → Push is up next.
    expect(find.text('UP NEXT'), findsOneWidget);
    // Plan and day names are user content, so they render inside directional
    // isolates (see `bidi.dart`); the plan name is the page's mono caption.
    expect(findTextIgnoringBidi('Day A · Push'), findsWidgets); // up next + cycle row
    expect(findTextIgnoringBidi('Bench Press'), findsOneWidget); // only the up-next block is expanded
    expect(findTextIgnoringBidi('TEST SPLIT'), findsOneWidget); // plan name

    // Sets are rendered collapsed — one line per distinct spec, "N ×" prefix
    // (Bench Press has a single set here, so "1 ×").
    expect(find.text('1 × 6–8 · 60kg · rest 2:00'), findsOneWidget);
  });

  testWidgets('browse section lists every day in the cycle and expands on tap', (tester) async {
    final plans = _PendingWorkoutPlanRepository();
    addTearDown(plans.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutPlanPage(), plansOverride: plans));
    plans.emit(_compactPlan());
    await tester.pump();

    // The dark hero card's taller rhythm pushes the browse list further down
    // than the default (short) test viewport shows without scrolling.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();

    // All three cycle days appear in the browse list.
    expect(findTextIgnoringBidi('Day B · Pull'), findsOneWidget);
    expect(findTextIgnoringBidi('Day C · Legs'), findsOneWidget);
    // The up-next day is marked in the cycle list — the house mono caption,
    // not a filled badge.
    expect(find.text('NEXT UP'), findsOneWidget);

    // A collapsed cycle row hides its exercises until tapped.
    expect(findTextIgnoringBidi('Deadlift'), findsNothing);
    await tester.tap(findTextIgnoringBidi('Day B · Pull'));
    await tester.pump();
    expect(findTextIgnoringBidi('Deadlift'), findsOneWidget);

    // And every expanded day is startable — the rotation recommends, it
    // doesn't restrict. Starting a non-"Next up" day opens the live session
    // for THAT day.
    await tester.pump(const Duration(milliseconds: 300)); // let expansion settle
    await tester.ensureVisible(find.text('Start this day'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('Start this day'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('elapsed-timer')), findsOneWidget);
  });

  testWidgets('shows a spinner while the plan stream is waiting', (tester) async {
    final plans = _PendingWorkoutPlanRepository();
    addTearDown(plans.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutPlanPage(), plansOverride: plans));

    expect(find.byType(Lottie), findsOneWidget);
    expect(find.text('No workout plan yet'), findsNothing);
  });

  testWidgets('shows the empty state once the plan stream settles with no data', (tester) async {
    final plans = _PendingWorkoutPlanRepository();
    addTearDown(plans.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutPlanPage(), plansOverride: plans));

    plans.emit(null);
    await tester.pump();

    expect(find.byType(Lottie), findsNothing);
    expect(find.text('No workout plan yet'), findsOneWidget);
  });

  testWidgets('shows the error view when the plan stream errors', (tester) async {
    final plans = _PendingWorkoutPlanRepository();
    addTearDown(plans.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutPlanPage(), plansOverride: plans));

    plans.emitError(Exception('read denied'));
    await tester.pump();

    // A page-local dark error state (not the shared light-mode ErrorStateView).
    expect(find.text("Couldn't load this."), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    expect(find.byType(Lottie), findsNothing);
    expect(find.text('No workout plan yet'), findsNothing);
  });

  testWidgets('the drill-downs the app bar used to hold are labelled rows at '
      'the foot of the page, and they still go where they went', (tester) async {
    final plans = InMemoryWorkoutPlanRepository();
    addTearDown(plans.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutPlanPage(), plansOverride: plans));
    await tester.pump();

    // Three bare icons in an AppBar became three rows that say what they are.
    await tester.dragUntilVisible(
      find.text('History'),
      find.byType(ListView),
      const Offset(0, -220),
    );
    await tester.pump();
    expect(find.text('Splits'), findsOneWidget);
    expect(find.text('Analysis'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    // The history page ("what I did") opens — its own title is unique to it
    // and absent from the read-only plan view.
    expect(find.text('History'), findsOneWidget);
  });

  testWidgets(
    'shows Resume workout (not Start) when an active session exists for the up-next day, '
    'and opens LiveSessionPage seeded from it',
    (tester) async {
      final plans = InMemoryWorkoutPlanRepository();
      addTearDown(plans.dispose);
      final plan = _compactPlan();
      await plans.savePlan(plan);

      final sessions = InMemoryWorkoutSessionRepository();
      await sessions.saveSession(
        LiveSession(
          id: 'active1',
          planId: plan.id,
          dayId: 'a', // matches the up-next day (cursor 0 → Day A)
          dayLabel: 'Push',
          // Started just now: an ACTIVE session, not one left open — a
          // session pinned to a fixed past date is stale by the time the
          // test runs, and the page rightly passes it over.
          startedAt: DateTime.now(),
          status: SessionStatus.active,
          exercises: const [
            SessionExercise(
              id: 'e1',
              exerciseId: 'e1',
              name: 'Bench Press',
              restSeconds: 120,
              sets: [LoggedSet(id: 'e1-s0', target: RepTarget.range(6, 8), outcome: SetOutcome.completed)],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrap(child: const WorkoutPlanPage(), plansOverride: plans, sessionsOverride: sessions),
      );
      await tester.pump();

      expect(find.text('Resume workout'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);

      await tester.tap(find.text('Resume workout'));
      await tester.pumpAndSettle();

      // Seeded from the saved session (its one set already done), not a
      // fresh one — and no second session was created alongside it.
      final page = tester.widget<LiveSessionPage>(find.byType(LiveSessionPage));
      expect(page.resume?.id, 'active1');
      expect(sessions.current, hasLength(1));
    },
  );

  testWidgets(
    'a session left open days ago does NOT hijack Up Next — the due day is offered instead',
    (tester) async {
      final plans = InMemoryWorkoutPlanRepository();
      addTearDown(plans.dispose);
      final plan = _compactPlan();
      await plans.savePlan(plan);

      final sessions = InMemoryWorkoutSessionRepository();
      await sessions.saveSession(
        LiveSession(
          id: 'left-open',
          planId: plan.id,
          dayId: 'a',
          dayLabel: 'Push',
          // Started three days ago and never closed. It used to go on
          // offering itself as "Resume" forever, in place of the day the
          // rotation actually had due.
          startedAt: DateTime.now().subtract(const Duration(days: 3)),
          status: SessionStatus.active,
          exercises: const [
            SessionExercise(
              id: 'e1',
              exerciseId: 'e1',
              name: 'Bench Press',
              restSeconds: 120,
              sets: [
                LoggedSet(
                  id: 'e1-s0',
                  target: RepTarget.range(6, 8),
                  outcome: SetOutcome.completed,
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrap(
          child: const WorkoutPlanPage(),
          plansOverride: plans,
          sessionsOverride: sessions,
        ),
      );
      await tester.pump();

      expect(find.text('Resume workout'), findsNothing);
      expect(find.text('Start workout'), findsOneWidget);
    },
  );

  testWidgets(
    'shows Resume for the active session\'s own day even when it differs from the '
    'rotation\'s next-due day (regression: Home and Workout tab used to drift apart here)',
    (tester) async {
      final plans = InMemoryWorkoutPlanRepository();
      addTearDown(plans.dispose);
      // Cursor still on Day A (order 0), but the running session is on Day C —
      // e.g. the plan was reordered/edited after this session started.
      final plan = _compactPlan();
      await plans.savePlan(plan);

      final sessions = InMemoryWorkoutSessionRepository();
      await sessions.saveSession(
        LiveSession(
          id: 'active-on-c',
          planId: plan.id,
          dayId: 'c',
          dayLabel: 'Legs',
          // Started just now: an ACTIVE session, not one left open — a
          // session pinned to a fixed past date is stale by the time the
          // test runs, and the page rightly passes it over.
          startedAt: DateTime.now(),
          status: SessionStatus.active,
          exercises: const [],
        ),
      );

      await tester.pumpWidget(
        _wrap(child: const WorkoutPlanPage(), plansOverride: plans, sessionsOverride: sessions),
      );
      await tester.pump();

      // The prominent card mirrors the running session's actual day...
      expect(findTextIgnoringBidi('Day C · Legs'), findsWidgets); // up next + cycle row
      expect(find.text('Resume workout'), findsOneWidget);
      expect(find.text('Start workout'), findsNothing);

      // ...while the rotation's own "next up" mark still points at Day A in
      // the cycle list below, since the cursor itself hasn't moved.
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      expect(find.text('NEXT UP'), findsOneWidget);
    },
  );

  testWidgets('shows Start workout when no active session exists for this plan/day', (
    tester,
  ) async {
    final plans = InMemoryWorkoutPlanRepository();
    addTearDown(plans.dispose);
    final plan = _compactPlan();
    await plans.savePlan(plan);

    final sessions = InMemoryWorkoutSessionRepository();
    // An active session for a *different* plan must not trigger Resume here.
    await sessions.saveSession(
      LiveSession(
        id: 'other-plan-session',
        planId: 'some-other-plan',
        dayId: 'a',
        dayLabel: 'Push',
        startedAt: DateTime.now(),
        status: SessionStatus.active,
        exercises: const [],
      ),
    );

    await tester.pumpWidget(
      _wrap(child: const WorkoutPlanPage(), plansOverride: plans, sessionsOverride: sessions),
    );
    await tester.pump();

    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('Resume workout'), findsNothing);
  });
}
