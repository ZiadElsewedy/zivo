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
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/body_weight_entry.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/pages/workout_dashboard_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

Widget _wrap({
  required Widget child,
  required InMemoryWorkoutPlanRepository plans,
  required InMemoryWorkoutSessionRepository sessions,
  required InMemoryBodyWeightRepository bodyWeight,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: plans,
    workoutSessions: sessions,
    bodyWeight: bodyWeight,
    university: InMemoryUniversityRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

WorkoutPlan _plan() => WorkoutPlan(
  id: 'p1',
  name: 'Push Pull Legs',
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
          defaultRestSeconds: 90,
          sets: [PlannedSet(order: 0, repTarget: RepTarget.fixed(5), restSeconds: 90, type: SetType.working)],
        ),
      ],
    ),
  ],
);

LiveSession _completedSession({required String id, required DateTime startedAt}) => LiveSession(
  id: id,
  planId: 'p1',
  dayId: 'a',
  dayLabel: 'Push',
  startedAt: startedAt,
  completedAt: startedAt.add(const Duration(minutes: 45)),
  status: SessionStatus.completed,
  exercises: const [],
);

/// The dashboard is a tall multi-section ListView (Today card, stats, weight,
/// split breakdown, recent activity) — same trick `today_page_test.dart` uses
/// for its own long dashboard: a tall viewport so every section actually
/// gets built and is findable, instead of drag-scrolling section by section.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('with no plan, shows the empty state and a way to create one', (tester) async {
    _useTallViewport(tester);
    // InMemoryWorkoutPlanRepository always seeds a real active plan — clear
    // it so this test actually exercises the no-plan path.
    final plans = InMemoryWorkoutPlanRepository();
    addTearDown(plans.dispose);
    await plans.deleteSplit(plans.splits.single.id);
    final sessions = InMemoryWorkoutSessionRepository();
    final bodyWeight = InMemoryBodyWeightRepository();
    addTearDown(bodyWeight.dispose);

    await tester.pumpWidget(
      _wrap(child: const WorkoutDashboardPage(), plans: plans, sessions: sessions, bodyWeight: bodyWeight),
    );
    await tester.pump();

    expect(find.text('No workout plan yet'), findsOneWidget);
    expect(find.text('Import from PDF'), findsOneWidget);
    expect(find.text('Build manually instead'), findsOneWidget);
  });

  testWidgets('with a plan and no history, shows the Start card and empty stats', (tester) async {
    _useTallViewport(tester);
    final plans = InMemoryWorkoutPlanRepository();
    addTearDown(plans.dispose);
    await plans.savePlan(_plan());
    final sessions = InMemoryWorkoutSessionRepository();
    final bodyWeight = InMemoryBodyWeightRepository();
    addTearDown(bodyWeight.dispose);

    await tester.pumpWidget(
      _wrap(child: const WorkoutDashboardPage(), plans: plans, sessions: sessions, bodyWeight: bodyWeight),
    );
    await tester.pump();

    // The up-next card for the rotation's first day.
    expect(find.text('Push'), findsWidgets); // card title + split chip label context
    expect(find.text('Start Workout'), findsOneWidget);

    // Stats are all placeholders with nothing logged yet.
    expect(find.text('0'), findsOneWidget); // sessions this week
    expect(find.text('—'), findsWidgets); // streak / avg duration / avg start

    expect(find.text('No weigh-ins logged yet.'), findsOneWidget);
    expect(find.text("You haven't logged a session yet."), findsOneWidget);
  });

  testWidgets('with a completed session and a weigh-in, stats and recent activity reflect them', (
    tester,
  ) async {
    _useTallViewport(tester);
    final plans = InMemoryWorkoutPlanRepository();
    addTearDown(plans.dispose);
    await plans.savePlan(_plan());

    final sessions = InMemoryWorkoutSessionRepository();
    await sessions.saveSession(
      _completedSession(id: 's1', startedAt: DateTime.now().subtract(const Duration(hours: 2))),
    );

    final bodyWeight = InMemoryBodyWeightRepository();
    addTearDown(bodyWeight.dispose);
    await bodyWeight.save(
      BodyWeightEntry(id: 'w1', weightKg: 82.5, loggedAt: DateTime.now()),
    );

    await tester.pumpWidget(
      _wrap(child: const WorkoutDashboardPage(), plans: plans, sessions: sessions, bodyWeight: bodyWeight),
    );
    await tester.pump();

    expect(find.text('1'), findsOneWidget); // sessions this week
    expect(find.text('82.5 kg'), findsOneWidget);
    expect(find.textContaining('Push · 1'), findsOneWidget); // split breakdown chip
    // The recent-activity row for the completed session.
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('logging a weight from the sheet persists it through the repository', (tester) async {
    _useTallViewport(tester);
    final plans = InMemoryWorkoutPlanRepository();
    addTearDown(plans.dispose);
    await plans.savePlan(_plan());
    final sessions = InMemoryWorkoutSessionRepository();
    final bodyWeight = InMemoryBodyWeightRepository();
    addTearDown(bodyWeight.dispose);

    await tester.pumpWidget(
      _wrap(child: const WorkoutDashboardPage(), plans: plans, sessions: sessions, bodyWeight: bodyWeight),
    );
    await tester.pump();

    // Not pumpAndSettle — the up-next card's `AliveColorDrift` wash is a
    // continuous, always-on repeating animation that never settles on its
    // own (see `up_next_workout_card.dart`). Bounded pumps instead.
    await tester.tap(find.text('Log weight'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField), '80.5');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(bodyWeight.current, hasLength(1));
    expect(bodyWeight.current.single.weightKg, 80.5);
  });
}
