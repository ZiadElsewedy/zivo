import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/diet/data/firestore_diet_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_plan_status.dart';
import 'package:zivo/features/diet/domain/diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/expenses/domain/expense.dart';
import 'package:zivo/features/expenses/domain/expense_repository.dart';
import 'package:zivo/features/home/presentation/header_builder.dart';
import 'package:zivo/features/home/presentation/pages/today_page.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/domain/exercise.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
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
import 'package:zivo/features/workout/presentation/pages/live_session_page.dart';
import 'package:zivo/features/workout/presentation/pages/workout_day_details_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';
import '../support/inert_music_controller.dart';

Widget _wrap({
  required Widget child,
  required DietRepository diet,
  WorkoutRepository? workouts,
  WorkoutPlanRepository? workoutPlans,
  WorkoutSessionRepository? workoutSessions,
  ExpenseRepository? expenses,
}) {
  return AppScope(
    auth: FakeAuthRepository(
      initial: const Authenticated(AuthUser(uid: 'test-uid')),
    ),
    profiles: FakeProfileRepository(),
    expenses: expenses ?? InMemoryExpenseRepository(),
    moments: InMemoryMomentRepository(),
    workouts: workouts ?? InMemoryWorkoutRepository(),
    workoutPlans: workoutPlans ?? InMemoryWorkoutPlanRepository(),
    workoutSessions: workoutSessions ?? InMemoryWorkoutSessionRepository(),
    diet: diet,
    ai: FakeAiRepository(),
    music: InertMusicController(),
    child: MaterialApp(home: child),
  );
}

WorkoutPlan _planWithNextDay() => WorkoutPlan(
  id: 'p1',
  name: 'Test Split',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  cycleCursor: 0,
  days: const [
    WorkoutDay(
      id: 'd',
      slot: 'D',
      label: 'Full Arm',
      order: 0,
      exercises: [
        PlannedExercise(
          id: 'ex1',
          name: 'Preacher Curl',
          order: 0,
          defaultRestSeconds: 60,
          sets: [
            PlannedSet(
              order: 0,
              repTarget: RepTarget.fixed(10),
              restSeconds: 60,
              type: SetType.working,
            ),
          ],
        ),
      ],
    ),
  ],
);

/// A two-day plan whose next-due day (cursor 0) is "Full Arm" (id `d`), with a
/// second day "Legs" (id `d2`) that is NOT next-due — used to prove Home
/// mirrors an active session on any day, not just `nextDay`.
WorkoutPlan _planWithTwoDays() {
  final base = _planWithNextDay();
  return WorkoutPlan(
    id: base.id,
    name: base.name,
    status: base.status,
    source: base.source,
    createdAt: base.createdAt,
    updatedAt: base.updatedAt,
    cycleCursor: 0,
    days: [
      base.days.first,
      const WorkoutDay(
        id: 'd2',
        slot: 'E',
        label: 'Legs',
        order: 1,
        exercises: [
          PlannedExercise(
            id: 'ex2',
            name: 'Back Squat',
            order: 0,
            defaultRestSeconds: 120,
            sets: [
              PlannedSet(
                order: 0,
                repTarget: RepTarget.fixed(5),
                restSeconds: 120,
                type: SetType.working,
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

void main() {
  Future<void> tallView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('header shows the profile name and a real date', (tester) async {
    await tallView(tester);

    await tester.pumpWidget(
      _wrap(child: const TodayPage(), diet: InMemoryDietRepository()),
    );
    await _settle(tester);

    // FakeProfileRepository defaults to the name 'Ziad'.
    expect(find.textContaining('Ziad'), findsOneWidget);
    expect(
      find.text(formatTodayDate(DateTime.now()).toUpperCase()),
      findsOneWidget,
    );
  });

  testWidgets(
    'Training always shows the active plan\'s up-next day — even once something was logged '
    'today — so it can never drift from what the Workout tab shows (same watchActivePlan source)',
    (tester) async {
      await tallView(tester);

      // A workout ("Pull") was already logged today, but the active plan's
      // up-next day is "Full Arm" — Home must show "Full Arm" (matching the
      // Workout page's own `plan.nextDay`), NOT roll back to reflect what
      // was just logged. This is the owner-reported inconsistency, fixed.
      final workouts = InMemoryWorkoutRepository();
      await workouts.add(
        Workout(
          id: 'today-w1',
          title: 'Pull',
          performedAt: DateTime.now(),
          durationMinutes: 45,
          exercises: const [Exercise(name: 'Lat Pulldown', sets: 4, reps: 10)],
        ),
      );

      await tester.pumpWidget(
        _wrap(
          child: const TodayPage(),
          diet: InMemoryDietRepository(),
          workouts: workouts,
          workoutPlans: _FixedPlanRepository(_planWithNextDay()),
        ),
      );
      await _settle(tester);

      expect(find.text('Full Arm'), findsOneWidget);
      expect(find.text('Start Workout'), findsOneWidget);
      expect(find.text('Pull'), findsNothing);
      expect(find.text('Lat Pulldown'), findsNothing);
      expect(find.text('No training plan yet'), findsNothing);
    },
  );

  testWidgets(
    'Training shows the empty state when nothing was logged today and there is no active plan',
    (tester) async {
      await tallView(tester);

      // The default InMemoryWorkoutRepository seeds a workout from
      // yesterday; the plan repo here is deliberately empty (no active
      // plan) — see the sibling "Up next" tests below for the case where
      // there IS one.
      await tester.pumpWidget(
        _wrap(
          child: const TodayPage(),
          diet: InMemoryDietRepository(),
          workoutPlans: _NoActivePlanRepository(),
        ),
      );
      await _settle(tester);

      expect(find.text('No training plan yet'), findsOneWidget);
    },
  );

  testWidgets(
    'Training shows an Up next Start card when an active plan has a day due and nothing was logged today',
    (tester) async {
      await tallView(tester);

      await tester.pumpWidget(
        _wrap(
          child: const TodayPage(),
          diet: InMemoryDietRepository(),
          workoutPlans: _FixedPlanRepository(_planWithNextDay()),
        ),
      );
      await _settle(tester);

      expect(find.text('Full Arm'), findsOneWidget);
      expect(find.text('1 exercise'), findsOneWidget);
      expect(find.text('Start Workout'), findsOneWidget);
      expect(find.text('No training plan yet'), findsNothing);
    },
  );

  testWidgets(
    'tapping Start opens the live session DIRECTLY — the split already '
    'decided today\'s workout, so there is no confirm/re-selection step',
    (tester) async {
      await tallView(tester);

      await tester.pumpWidget(
        _wrap(
          child: const TodayPage(),
          diet: InMemoryDietRepository(),
          workoutPlans: _FixedPlanRepository(_planWithNextDay()),
        ),
      );
      await _settle(tester);

      expect(find.text('Ready to start Full Arm?'), findsNothing);
      await tester.tap(find.text('Start Workout'));
      await _settle(tester);

      expect(find.byType(LiveSessionPage), findsOneWidget);
    },
  );

  testWidgets(
    'the Change chip opens the day picker and picking another day starts it directly',
    (tester) async {
      await tallView(tester);
      final plan = _planWithTwoDays(); // next-due "Full Arm", also has d2

      await tester.pumpWidget(
        _wrap(
          child: const TodayPage(),
          diet: InMemoryDietRepository(),
          workoutPlans: _FixedPlanRepository(plan),
        ),
      );
      await _settle(tester);

      await tester.tap(find.byKey(const Key('training-change')));
      await _settle(tester);

      // The sheet lists every day of the split; pick a different one.
      final otherDay = plan.days.firstWhere((d) => d.id != plan.nextDay!.id);
      await tester.tap(find.text(otherDay.label).last);
      await _settle(tester);

      // Picking starts that workout directly — no further confirm.
      expect(find.byType(LiveSessionPage), findsOneWidget);
    },
  );

  testWidgets(
    'tapping the card body (outside the CTA) opens the day details page',
    (tester) async {
      await tallView(tester);
      final plan = _planWithNextDay();

      await tester.pumpWidget(
        _wrap(
          child: const TodayPage(),
          diet: InMemoryDietRepository(),
          workoutPlans: _FixedPlanRepository(plan),
        ),
      );
      await _settle(tester);

      // Tap the card's title text — outside the Start button.
      await tester.tap(find.text('Full Arm'));
      await _settle(tester);

      expect(
        find.byType(WorkoutDayDetailsPage),
        findsOneWidget,
        reason: 'The card body should open today\'s workout details',
      );
    },
  );

  testWidgets(
    'an active session on a NON-next day mirrors that day with Resume — the '
    'source-of-truth fix, so Home never reads "not active" while a workout runs',
    (tester) async {
      await tallView(tester);
      final plan =
          _planWithTwoDays(); // next-due is "Full Arm"; session is "Legs"
      final sessions = InMemoryWorkoutSessionRepository();
      await sessions.saveSession(
        LiveSession.start(
          plan.days.firstWhere((d) => d.id == 'd2'),
          id: 'active-legs',
          planId: plan.id,
          now: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        _wrap(
          child: const TodayPage(),
          diet: InMemoryDietRepository(),
          workoutPlans: _FixedPlanRepository(plan),
          workoutSessions: sessions,
        ),
      );
      await _settle(tester);

      // Home follows the running session's day, not the next-due day.
      expect(find.text('Legs'), findsOneWidget);
      expect(find.text('Resume Workout'), findsOneWidget);
      expect(find.text('Full Arm'), findsNothing);
      expect(find.text('Start Workout'), findsNothing);
    },
  );

  testWidgets(
    'ending the active session (it clears) returns Home to the next-due day with Start',
    (tester) async {
      await tallView(tester);
      final plan = _planWithTwoDays();
      final sessions = InMemoryWorkoutSessionRepository();
      final active = LiveSession.start(
        plan.days.firstWhere((d) => d.id == 'd2'),
        id: 'active-legs',
        planId: plan.id,
        now: DateTime.now(),
      );
      await sessions.saveSession(active);

      await tester.pumpWidget(
        _wrap(
          child: const TodayPage(),
          diet: InMemoryDietRepository(),
          workoutPlans: _FixedPlanRepository(plan),
          workoutSessions: sessions,
        ),
      );
      await _settle(tester);
      expect(find.text('Resume Workout'), findsOneWidget);

      // Completing the session clears "active" — Home reactively falls back to
      // the next-due day (no rebuild/navigation needed).
      await sessions.saveSession(active.complete(now: DateTime.now()));
      await _settle(tester);

      expect(find.text('Full Arm'), findsOneWidget);
      expect(find.text('Start Workout'), findsOneWidget);
      expect(find.text('Resume Workout'), findsNothing);
    },
  );

  testWidgets('Diet glance shows the summary when an active plan exists', (
    tester,
  ) async {
    await tallView(tester);

    await tester.pumpWidget(
      _wrap(child: const TodayPage(), diet: InMemoryDietRepository()),
    );
    await _settle(tester);

    // Seeded plan: 3 meals (Breakfast/Lunch/Dinner), none eaten yet.
    expect(find.textContaining('of 3 meals eaten'), findsOneWidget);
  });

  testWidgets('Diet glance is hidden when there is no active plan', (
    tester,
  ) async {
    await tallView(tester);

    final diet = FirestoreDietRepository(
      firestore: FakeFirebaseFirestore(),
      uidSource: UidSource(
        currentUid: () => 'test-uid',
        uidChanges: Stream.value('test-uid'),
      ),
    );

    await tester.pumpWidget(_wrap(child: const TodayPage(), diet: diet));
    await _settle(tester);

    expect(find.text('DIET'), findsNothing);
    expect(find.textContaining('meals eaten'), findsNothing);
  });

  testWidgets(
    'Training shows a Get Started card when there is no workout plan, diet plan, or expenses',
    (tester) async {
      await tallView(tester);

      await tester.pumpWidget(
        _wrap(
          child: const TodayPage(),
          diet: _TestDietRepository(),
          workoutPlans: _NoActivePlanRepository(),
          expenses: _TestExpenseRepository(),
        ),
      );
      await _settle(tester);

      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Import a\nworkout plan'), findsOneWidget);
      expect(find.text('Add an\nexpense'), findsOneWidget);
      expect(find.text('No training plan yet'), findsNothing);
    },
  );

  testWidgets(
    'the Get Started card collapses to the plain empty line once a diet plan arrives',
    (tester) async {
      await tallView(tester);
      final diet = _TestDietRepository();
      addTearDown(diet.dispose);

      await tester.pumpWidget(
        _wrap(
          child: const TodayPage(),
          diet: diet,
          workoutPlans: _NoActivePlanRepository(),
          expenses: _TestExpenseRepository(),
        ),
      );
      await _settle(tester);
      expect(find.text('Get started'), findsOneWidget);

      await diet.savePlan(
        DietPlan(
          id: 'p1',
          name: 'Test Plan',
          status: DietPlanStatus.active,
          source: DietSource.manual,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          days: const [],
        ),
      );
      await _settle(tester);

      expect(find.text('Get started'), findsNothing);
      expect(find.text('No training plan yet'), findsOneWidget);
    },
  );

  testWidgets(
    'the Get Started card collapses to the plain empty line once an expense is logged',
    (tester) async {
      await tallView(tester);
      final expenses = _TestExpenseRepository();
      addTearDown(expenses.dispose);

      await tester.pumpWidget(
        _wrap(
          child: const TodayPage(),
          diet: _TestDietRepository(),
          workoutPlans: _NoActivePlanRepository(),
          expenses: expenses,
        ),
      );
      await _settle(tester);
      expect(find.text('Get started'), findsOneWidget);

      await expenses.add(
        Expense(
          id: 'e1',
          amountMinor: 500,
          currency: 'EGP',
          categoryId: 'coffee',
          spentAt: DateTime.now(),
        ),
      );
      await _settle(tester);

      expect(find.text('Get started'), findsNothing);
      expect(find.text('No training plan yet'), findsOneWidget);
    },
  );
}

/// Used everywhere in this file instead of `pumpAndSettle` — the up-next
/// card's `AliveColorDrift` (`up_next_workout_card.dart`) is a continuous,
/// always-on repeating animation the moment there's an active plan (which
/// the default `_wrap` always seeds), so `pumpAndSettle` would hang on
/// almost every test here. [LiveSessionPage] adds its own repeating
/// controllers too (the current-set pulse, the rest ring's stroke glow) —
/// same reasoning, same convention as `live_session_page_test.dart`. Also
/// long enough to cover the confirm sheet's own symmetric exit spring (critically damped,
/// ~0.35s response — see `up_next_workout_card.dart`'s `_resolve`), which
/// the Start/Resume confirm tap awaits before popping. The trailing bare
/// `pump()` matters too: `Navigator.push` fired from inside that awaited
/// async chain doesn't materialize the new route's widget tree within the
/// same timed pump that triggers it — it needs one more frame.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1000));
  await tester.pump();
}

/// A [DietRepository] that starts with (or without) a plan and rebroadcasts
/// reactively on [savePlan]/[deletePlan] — used to prove the Get Started
/// card collapses the moment a diet plan shows up.
class _TestDietRepository implements DietRepository {
  _TestDietRepository([DietPlan? initial]) : _plan = initial;

  DietPlan? _plan;
  final StreamController<DietPlan?> _controller =
      StreamController<DietPlan?>.broadcast();

  @override
  DietPlan? get activePlan => _plan;

  @override
  Stream<DietPlan?> watchActivePlan() => _controller.stream;

  @override
  Future<void> savePlan(DietPlan plan) async {
    _plan = plan;
    _controller.add(_plan);
  }

  @override
  Future<void> deletePlan(String id) async {
    _plan = null;
    _controller.add(_plan);
  }

  @override
  Stream<Set<String>> watchConsumed(DateTime day) =>
      Stream.value(const <String>{});

  @override
  Future<void> setMealEaten({
    required String mealId,
    required DateTime day,
    required bool eaten,
  }) async {}

  void dispose() => _controller.close();
}

/// An [ExpenseRepository] that starts with (or without) items and
/// rebroadcasts reactively on [add] — used to prove the Get Started card
/// collapses the moment an expense is logged.
class _TestExpenseRepository implements ExpenseRepository {
  _TestExpenseRepository([List<Expense>? initial])
    : _items = List.of(initial ?? const <Expense>[]);

  final List<Expense> _items;
  final StreamController<List<Expense>> _controller =
      StreamController<List<Expense>>.broadcast();

  @override
  List<Expense> get current => List.unmodifiable(_items);

  @override
  Stream<List<Expense>> watchAll() => _controller.stream;

  @override
  Future<void> add(Expense expense) async {
    _items.add(expense);
    _controller.add(current);
  }

  @override
  Future<void> update(Expense expense) async {
    final i = _items.indexWhere((e) => e.id == expense.id);
    if (i != -1) _items[i] = expense;
    _controller.add(current);
  }

  @override
  Future<void> remove(String id) async {
    _items.removeWhere((e) => e.id == id);
    _controller.add(current);
  }

  void dispose() => _controller.close();
}

class _NoActivePlanRepository implements WorkoutPlanRepository {
  @override
  WorkoutPlan? get activePlan => null;

  @override
  Stream<WorkoutPlan?> watchActivePlan() => Stream.value(null);

  @override
  Future<void> savePlan(WorkoutPlan plan) async {}

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
}

class _FixedPlanRepository implements WorkoutPlanRepository {
  _FixedPlanRepository(this._plan);

  WorkoutPlan? _plan;

  @override
  WorkoutPlan? get activePlan => _plan;

  @override
  Stream<WorkoutPlan?> watchActivePlan() => Stream.value(_plan);

  @override
  Future<void> savePlan(WorkoutPlan plan) async {
    _plan = plan;
  }

  @override
  Future<void> deletePlan(String id) async {
    _plan = null;
  }

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
}
