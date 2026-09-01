import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/core/widgets/train_surfaces.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
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
import 'package:zivo/features/workout/presentation/pages/bodyweight_history_page.dart';
import 'package:zivo/features/workout/presentation/pages/workout_stats_pages.dart';

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
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: plans,
    workoutSessions: sessions,
    bodyWeight: bodyWeight,
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
    expect(find.text('Import a plan'), findsOneWidget);
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
    expect(find.text('Push'), findsOneWidget); // the up-next card's title
    expect(find.text('Start workout'), findsOneWidget);

    // Stats are all placeholders with nothing logged yet.
    expect(find.text('0'), findsNWidgets(2)); // sessions + day streak
    expect(find.text('—'), findsWidgets); // avg duration / avg start

    expect(find.text('NO WEIGH-INS YET'), findsOneWidget);
    // The recent-activity empty card lives on the Progress screen now, not here.
    expect(find.text("You haven't logged a session yet."), findsNothing);
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

    expect(_tileValue(tester, 'Sessions'), '1');
    expect(_tileValue(tester, 'Streak'), '1'); // trained today
    // The reading and its unit are separate elements now — the unit is always
    // smaller and dimmer than the value it belongs to.
    expect(find.text('82.5'), findsOneWidget);
    expect(find.text('KG'), findsOneWidget);
  });

  testWidgets(
    'the landing keeps only the training card, This week and Bodyweight — split, '
    'progress and recent activity moved to the Progress screen',
    (tester) async {
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

      await tester.pumpWidget(
        _wrap(child: const WorkoutDashboardPage(), plans: plans, sessions: sessions, bodyWeight: bodyWeight),
      );
      await tester.pump();

      // Kept.
      expect(find.text('Start workout'), findsOneWidget);
      expect(find.text('TRAINING'), findsWidgets); // section label + the up-next card's own tag
      expect(find.text('BODYWEIGHT'), findsOneWidget);

      // Moved off the landing entirely.
      expect(find.text('CURRENT SPLIT'), findsNothing);
      expect(find.text('PROGRESS'), findsNothing);
      expect(find.text('RECENT ACTIVITY'), findsNothing);
      expect(find.text('Push Pull Legs'), findsNothing); // split breakdown card
      expect(find.text('Completed'), findsNothing); // recent-activity row

      // One calm AppBar action, and none of the old per-destination icons.
      expect(find.byTooltip('Progress'), findsOneWidget);
      expect(find.byTooltip('Analysis'), findsNothing);
      expect(find.byTooltip('Splits'), findsNothing);
      expect(find.byTooltip('History'), findsNothing);
      expect(find.byTooltip('Plan'), findsNothing);
    },
  );

  testWidgets('the AppBar Progress action opens the Progress screen with the moved sections', (
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

    await tester.pumpWidget(
      _wrap(child: const WorkoutDashboardPage(), plans: plans, sessions: sessions, bodyWeight: bodyWeight),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Progress'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350)); // let the push transition finish

    // Every section that left the landing is here, on the same live data.
    expect(find.text('CURRENT SPLIT'), findsOneWidget);
    expect(find.text('RECENT ACTIVITY'), findsOneWidget);
    expect(find.text('Push Pull Legs'), findsOneWidget);
    // The split breakdown renders each training day as its own row (the
    // label also appears in the recent-activity row and the analysis teaser).
    expect(find.text('Push'), findsWidgets);
    expect(find.text('Completed'), findsOneWidget); // recent-activity row

    // No destination was lost in the move.
    expect(find.text('Full analysis'), findsOneWidget);
    expect(find.text('All history'), findsOneWidget);
    expect(find.text('Splits'), findsOneWidget);
  });

  testWidgets('from the Progress screen, a recent session row opens its Session details', (
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

    await tester.pumpWidget(
      _wrap(child: const WorkoutDashboardPage(), plans: plans, sessions: sessions, bodyWeight: bodyWeight),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Progress'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();

    expect(find.text('Session details'), findsOneWidget); // SessionDetailsPage's own AppBar title
  });

  testWidgets('from the Progress screen, Full analysis opens WorkoutAnalysisPage', (tester) async {
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

    await tester.tap(find.byTooltip('Progress'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('Full analysis'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Analysis'), findsOneWidget); // WorkoutAnalysisPage's own AppBar title
  });

  testWidgets('from the Progress screen, the current split card opens Split Management', (
    tester,
  ) async {
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

    await tester.tap(find.byTooltip('Progress'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('Push Pull Legs'));
    await tester.pumpAndSettle();

    // Split Management's own AppBar title — the "Splits" destination row is
    // gone from the tree now that we've navigated away from Progress.
    expect(find.text('Splits'), findsOneWidget);
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
    await tester.tap(find.text('Log weigh-in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField), '80.5');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(bodyWeight.current, hasLength(1));
    expect(bodyWeight.current.single.weightKg, 80.5);
  });

  Future<void> pumpDashboard(
    WidgetTester tester, {
    InMemoryWorkoutSessionRepository? sessions,
    InMemoryBodyWeightRepository? bodyWeight,
  }) async {
    _useTallViewport(tester);
    final plans = InMemoryWorkoutPlanRepository();
    addTearDown(plans.dispose);
    await plans.savePlan(_plan());
    final sessionRepo =
        sessions ?? InMemoryWorkoutSessionRepository();
    await sessionRepo.saveSession(
      _completedSession(id: 's1', startedAt: DateTime.now().subtract(const Duration(hours: 2))),
    );
    final weightRepo = bodyWeight ?? InMemoryBodyWeightRepository();
    addTearDown(weightRepo.dispose);

    await tester.pumpWidget(
      _wrap(
        child: const WorkoutDashboardPage(),
        plans: plans,
        sessions: sessionRepo,
        bodyWeight: weightRepo,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> expectDrillDown(
    WidgetTester tester,
    String label,
    Type pageType,
  ) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(pageType, skipOffstage: true), findsOneWidget);
  }

  testWidgets('the Sessions tile opens the sessions history page', (tester) async {
    await pumpDashboard(tester);
    await expectDrillDown(tester, 'Sessions', WorkoutSessionsPage);
  });

  testWidgets('the Streak tile opens the streak history page', (tester) async {
    await pumpDashboard(tester);
    await expectDrillDown(tester, 'Streak', WorkoutStreakPage);
  });

  testWidgets('the Duration tile opens the duration stats page', (tester) async {
    await pumpDashboard(tester);
    await expectDrillDown(tester, 'Duration', WorkoutDurationStatsPage);
  });

  testWidgets('the Usual start tile opens the start-times stats page', (tester) async {
    await pumpDashboard(tester);
    await expectDrillDown(tester, 'Usual start', WorkoutStartTimesPage);
  });

  testWidgets('the Bodyweight card opens the weigh-in history page', (tester) async {
    await pumpDashboard(tester);
    await expectDrillDown(tester, 'Log one to start the trend.', BodyweightHistoryPage);
  });
}

/// The value a [TrainStatTile] is showing, found by its label — the tiles
/// render value, unit and label as separate elements, so a bare `find.text`
/// on a digit would sweep up every other tile on the page.
String _tileValue(WidgetTester tester, String label) =>
    tester.widget<TrainStatTile>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(TrainStatTile),
      ),
    ).value;
