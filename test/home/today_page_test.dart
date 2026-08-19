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
import 'package:zivo/features/diet/domain/diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/home/presentation/header_builder.dart';
import 'package:zivo/features/home/presentation/pages/today_page.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
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

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

Widget _wrap({
  required Widget child,
  required DietRepository diet,
  WorkoutRepository? workouts,
  WorkoutPlanRepository? workoutPlans,
  WorkoutSessionRepository? workoutSessions,
}) {
  return AppScope(
    auth: FakeAuthRepository(
      initial: const Authenticated(AuthUser(uid: 'test-uid')),
    ),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: workouts ?? InMemoryWorkoutRepository(),
    workoutPlans: workoutPlans ?? InMemoryWorkoutPlanRepository(),
    workoutSessions: workoutSessions ?? InMemoryWorkoutSessionRepository(),
    university: InMemoryUniversityRepository(),
    diet: diet,
    ai: FakeAiRepository(),
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

void main() {
  Future<void> tallView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('header shows the profile name and a real date', (
    tester,
  ) async {
    await tallView(tester);

    await tester.pumpWidget(
      _wrap(child: const TodayPage(), diet: InMemoryDietRepository()),
    );
    await tester.pumpAndSettle();

    // FakeProfileRepository defaults to the name 'Ziad'.
    expect(find.textContaining('Ziad'), findsOneWidget);
    expect(
      find.text(formatTodayDate(DateTime.now()).toUpperCase()),
      findsOneWidget,
    );
  });

  testWidgets('Training reflects an injected workout logged today', (
    tester,
  ) async {
    await tallView(tester);

    final workouts = InMemoryWorkoutRepository();
    await workouts.add(
      Workout(
        id: 'today-w1',
        title: 'Pull',
        performedAt: DateTime.now(),
        durationMinutes: 45,
        exercises: const [
          Exercise(name: 'Lat Pulldown', sets: 4, reps: 10),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrap(
        child: const TodayPage(),
        diet: InMemoryDietRepository(),
        workouts: workouts,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pull'), findsOneWidget);
    expect(find.text('Lat Pulldown'), findsOneWidget);
    expect(find.text('No training logged yet today.'), findsNothing);
  });

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
      await tester.pumpAndSettle();

      expect(find.text('No training logged yet today.'), findsOneWidget);
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
      await tester.pumpAndSettle();

      expect(find.text('Day D · Full Arm'), findsOneWidget);
      expect(find.text('1 exercise'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('No training logged yet today.'), findsNothing);
    },
  );

  testWidgets(
    'tapping Start shows a dark confirm sheet; Cancel dismisses without navigating',
    (tester) async {
      await tallView(tester);

      await tester.pumpWidget(
        _wrap(
          child: const TodayPage(),
          diet: InMemoryDietRepository(),
          workoutPlans: _FixedPlanRepository(_planWithNextDay()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.text('Ready to start Full Arm?'), findsOneWidget);
      expect(find.text('1 exercise today.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byType(LiveSessionPage), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Ready to start Full Arm?'), findsNothing);
      expect(find.byType(LiveSessionPage), findsNothing);
      expect(find.text('Day D · Full Arm'), findsOneWidget); // still on Today
    },
  );

  testWidgets(
    'confirming Start navigates directly into a fresh LiveSessionPage, bypassing Hub → Workout',
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
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      // Two "Start"s on screen now (the sheet's own CTA) — the second/last
      // one is the confirm action.
      await tester.tap(find.text('Start').last);
      await _settle(tester);

      expect(find.byType(LiveSessionPage), findsOneWidget);
      // A fresh (non-resume) session opens on the pre-workout warm-up phase.
      expect(find.text('PRE-WORKOUT'), findsOneWidget);
    },
  );

  testWidgets(
    'an active session for the up-next day shows Resume and skips the warm-up phase on confirm',
    (tester) async {
      await tallView(tester);
      final plan = _planWithNextDay();
      final sessions = InMemoryWorkoutSessionRepository();
      final active = LiveSession.start(
        plan.days.first,
        id: 'active1',
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
      await tester.pumpAndSettle();

      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Start'), findsNothing);

      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(find.text('Ready to jump back in?'), findsOneWidget);

      await tester.tap(find.text('Resume').last);
      await _settle(tester);

      expect(find.byType(LiveSessionPage), findsOneWidget);
      // A resumed session never re-opens on the warm-up phase.
      expect(find.text('PRE-WORKOUT'), findsNothing);
    },
  );

  testWidgets('Diet glance shows the summary when an active plan exists', (
    tester,
  ) async {
    await tallView(tester);

    await tester.pumpWidget(
      _wrap(child: const TodayPage(), diet: InMemoryDietRepository()),
    );
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    expect(find.text('DIET'), findsNothing);
    expect(find.textContaining('meals eaten'), findsNothing);
  });
}

/// [LiveSessionPage] carries repeating animation controllers (the current-
/// set pulse, the rest/warm-up ring's stroke glow) that never settle on
/// their own — `pumpAndSettle` would hang once it's on screen, so any step
/// past navigating into it advances by a fixed, generous duration instead
/// (same convention as `live_session_page_test.dart`).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
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
}
