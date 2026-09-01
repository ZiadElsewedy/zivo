import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/body_profile.dart';
import 'package:zivo/features/diet/domain/diet_goal.dart';
import 'package:zivo/features/diet/domain/nutrition/food_log_entry.dart';
import 'package:zivo/features/diet/domain/nutrition/food_reference.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/domain/target_calculator.dart';
import 'package:zivo/features/diet/presentation/pages/body_profile_page.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plan_details_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/body_weight_entry.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// Plan details is a lazy list; the verdict sits above the fold but the tests
/// below also reach further down it, so give them the room.
///
/// The verdict used to live on the Diet screen and these tests pumped that.
/// It moved down a level in the simplification pass — the assertions are
/// unchanged, only the screen they're made against.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap({
  required Widget child,
  required InMemoryDietRepository diet,
  InMemoryBodyWeightRepository? bodyWeight,
}) => AppScope(
  auth: FakeAuthRepository(
    initial: const Authenticated(AuthUser(uid: 'fake-uid')),
  ),
  profiles: FakeProfileRepository(),
  expenses: InMemoryExpenseRepository(),
  moments: InMemoryMomentRepository(),
  workouts: InMemoryWorkoutRepository(),
  workoutPlans: InMemoryWorkoutPlanRepository(),
  workoutSessions: InMemoryWorkoutSessionRepository(),
  bodyWeight: bodyWeight,
  diet: diet,
  ai: FakeAiRepository(),
  child: MaterialApp(home: child),
);

BodyProfile _profile({int? statedMaintenance}) => BodyProfile(
  heightCm: 178,
  sex: TargetSex.male,
  activity: ActivityLevel.moderate,
  statedMaintenanceKcal: statedMaintenance,
  updatedAt: DateTime(2026, 8, 30),
);

void main() {
  testWidgets('with no body data the screen asks for exactly what it needs, '
      'and never guesses a verdict', (tester) async {
    _tallViewport(tester);
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: DietPlanDetailsPage(plan: diet.activePlan!), diet: diet));
    await tester.pump();

    expect(find.byKey(const Key('body-data-prompt')), findsOneWidget);
    expect(find.byKey(const Key('plan-verdict-card')), findsNothing);

    final missing = tester
        .widget<Text>(find.byKey(const Key('body-data-missing')))
        .data!;
    // Named, not "complete your profile" — and the weight is missing here
    // because no weigh-in log was provided at all.
    expect(missing, contains('your current weight'));
    expect(missing, contains('your height'));
  });

  testWidgets('the prompt opens the body data screen', (tester) async {
    _tallViewport(tester);
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: DietPlanDetailsPage(plan: diet.activePlan!), diet: diet));
    await tester.pump();

    await tester.tap(find.byKey(const Key('body-data-prompt')));
    await tester.pumpAndSettle();

    expect(find.byType(BodyProfilePage), findsOneWidget);
  });

  testWidgets('with body data the plan gets a verdict, with its working', (
    tester,
  ) async {
    _tallViewport(tester);
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    await diet.saveBodyProfile(_profile());
    final weights = InMemoryBodyWeightRepository(
      seed: [
        BodyWeightEntry(
          id: 'w1',
          weightKg: 82,
          loggedAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(child: DietPlanDetailsPage(plan: diet.activePlan!), diet: diet, bodyWeight: weights),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('body-data-prompt')), findsNothing);
    expect(find.byKey(const Key('plan-verdict-card')), findsOneWidget);

    // The seeded demo plan is a moderate day, well under this person's
    // maintenance — so it reads as losing, and the detail line shows both
    // figures rather than just the conclusion.
    final headline = tester
        .widget<Text>(find.byKey(const Key('verdict-headline')))
        .data!;
    expect(headline, contains('Losing'));
    final detail = tester
        .widget<Text>(find.byKey(const Key('verdict-detail')))
        .data!;
    expect(detail, contains('kcal a day'));
    expect(detail, contains('maintenance'));
    expect(detail, contains('an estimate from your body data'));
  });

  testWidgets('a stated maintenance figure is used as given, and named', (
    tester,
  ) async {
    _tallViewport(tester);
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    await diet.saveBodyProfile(_profile(statedMaintenance: 1500));
    final weights = InMemoryBodyWeightRepository(
      seed: [BodyWeightEntry(id: 'w1', weightKg: 82, loggedAt: DateTime.now())],
    );

    await tester.pumpWidget(
      _wrap(child: DietPlanDetailsPage(plan: diet.activePlan!), diet: diet, bodyWeight: weights),
    );
    await tester.pump();
    await tester.pump();

    final detail = tester
        .widget<Text>(find.byKey(const Key('verdict-detail')))
        .data!;
    expect(detail, contains('1500 kcal maintenance'));
    expect(detail, contains('the maintenance figure you gave'));
  });

  testWidgets('the body data screen saves the profile and logs a weigh-in', (
    tester,
  ) async {
    _tallViewport(tester);
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    final weights = InMemoryBodyWeightRepository();

    await tester.pumpWidget(
      _wrap(child: const BodyProfilePage(), diet: diet, bodyWeight: weights),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('body-weight')), '82');
    await tester.enterText(find.byKey(const Key('body-height')), '178');
    await tester.tap(find.byKey(const Key('sex-male')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('activity-moderate')));
    await tester.pump();

    // The maintenance the answers add up to is shown BEFORE saving, so the
    // consequence of "moderate" is visible rather than discovered later.
    // Derived here rather than hard-coded: the age comes from the fake
    // profile's date of birth, so a literal would rot on a birthday.
    final expected =
        (basalMetabolicRate(
                  weightKg: 82,
                  heightCm: 178,
                  age: ageFrom(DateTime(1990, 1, 1), DateTime.now()),
                  sex: TargetSex.male,
                ) *
                activityFactor(ActivityLevel.moderate))
            .round();
    expect(
      tester.widget<Text>(find.byKey(const Key('maintenance-preview'))).data,
      '$expected kcal a day',
    );

    await tester.tap(find.byKey(const Key('save-body-profile')));
    await tester.pumpAndSettle();

    expect(diet.currentBodyProfile, isNotNull);
    expect(diet.currentBodyProfile!.heightCm, 178);
    expect(diet.currentBodyProfile!.activity, ActivityLevel.moderate);
    // Weight went to the weigh-in log, not onto the profile.
    expect(weights.current.single.weightKg, 82);
  });

  testWidgets('reopening and re-saving does not plant a duplicate weigh-in', (
    tester,
  ) async {
    _tallViewport(tester);
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    await diet.saveBodyProfile(_profile());
    final weights = InMemoryBodyWeightRepository(
      seed: [BodyWeightEntry(id: 'w1', weightKg: 82, loggedAt: DateTime.now())],
    );

    await tester.pumpWidget(
      _wrap(child: const BodyProfilePage(), diet: diet, bodyWeight: weights),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save-body-profile')));
    await tester.pumpAndSettle();

    expect(weights.current, hasLength(1));
  });

  testWidgets('an implausible height is refused rather than stored', (
    tester,
  ) async {
    _tallViewport(tester);
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(
      _wrap(
        child: const BodyProfilePage(),
        diet: diet,
        bodyWeight: InMemoryBodyWeightRepository(),
      ),
    );
    await tester.pumpAndSettle();

    // Metres, not centimetres — the classic entry mistake.
    await tester.enterText(find.byKey(const Key('body-height')), '1.78');
    await tester.tap(find.byKey(const Key('sex-male')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('activity-moderate')));
    await tester.pump();

    expect(find.byKey(const Key('height-range-note')), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-body-profile')));
    await tester.pumpAndSettle();
    expect(diet.currentBodyProfile, isNull);
  });

  group('what this person actually burns', () {
    testWidgets('with too little data, the card says what would be needed', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      await diet.saveBodyProfile(_profile());
      final weights = InMemoryBodyWeightRepository(
        seed: [
          BodyWeightEntry(id: 'w1', weightKg: 82, loggedAt: DateTime.now()),
        ],
      );

      await tester.pumpWidget(
        _wrap(child: DietPlanDetailsPage(plan: diet.activePlan!), diet: diet, bodyWeight: weights),
      );
      await tester.pumpAndSettle();

      // One weigh-in measures nothing — and the prompt names the gap rather
      // than the screen quietly falling back to the equation.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('verdict-calibration-gap')))
            .data,
        contains('two weigh-ins'),
      );
      expect(find.byKey(const Key('verdict-calibration')), findsNothing);
    });

    testWidgets('with a month of weigh-ins and logs, it measures and says so', (
      tester,
    ) async {
      _tallViewport(tester);
      final now = DateTime.now();
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      await diet.saveBodyProfile(_profile());
      // 28 days at 2,600 kcal with weight up 0.8 kg → maintenance ~2,380,
      // well below the ~2,725 the equation would have estimated.
      for (var i = 0; i < 28; i++) {
        await diet.logFood([
          FoodLogEntry(
            id: 'e$i',
            day: now.subtract(Duration(days: 28 - i)),
            loggedAt: now.subtract(Duration(days: 28 - i)),
            foodId: 'usda:1',
            foodName: 'Food',
            quantity: 100,
            unit: 'g',
            grams: 100,
            kcal: 2600,
            proteinG: 100,
            carbsG: 300,
            fatG: 80,
            source: NutritionSource.usdaFdc,
            sourceRef: '1',
            origin: FoodLogOrigin.logged,
            estimated: false,
          ),
        ]);
      }
      final weights = InMemoryBodyWeightRepository(
        seed: [
          BodyWeightEntry(
            id: 'w1',
            weightKg: 82,
            loggedAt: now.subtract(const Duration(days: 28)),
          ),
          BodyWeightEntry(id: 'w2', weightKg: 82.8, loggedAt: now),
        ],
      );

      await tester.pumpWidget(
        _wrap(child: DietPlanDetailsPage(plan: diet.activePlan!), diet: diet, bodyWeight: weights),
      );
      await tester.pumpAndSettle();

      final line = tester
          .widget<Text>(find.byKey(const Key('verdict-calibration')))
          .data!;
      expect(line, contains('Measured from your last 28 days'));
      expect(line, contains('2600 kcal a day eaten'));

      // And the verdict itself now rests on the measurement, not the equation.
      final detail = tester
          .widget<Text>(find.byKey(const Key('verdict-detail')))
          .data!;
      expect(detail, contains('2380 kcal maintenance'));
      expect(detail, contains('your own weigh-ins and food log'));
    });

    testWidgets('a target that fights its goal is called out on the screen', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      await diet.saveBodyProfile(_profile());
      // Maintenance ~2,725 for this fake profile; a 3,200 kcal target with a
      // fat-loss goal is a plan to gain weight, and no amount of daily
      // logging would ever reveal it.
      await diet.saveTargets(
        NutritionTargets(
          goal: DietGoal.fatLoss,
          calories: 3200,
          source: TargetSource.manual,
          updatedAt: DateTime(2026, 8, 30),
        ),
      );
      final weights = InMemoryBodyWeightRepository(
        seed: [
          BodyWeightEntry(id: 'w1', weightKg: 82, loggedAt: DateTime.now()),
        ],
      );

      await tester.pumpWidget(
        _wrap(child: DietPlanDetailsPage(plan: diet.activePlan!), diet: diet, bodyWeight: weights),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('but the goal is set to fat loss'),
        findsOneWidget,
      );
    });
  });
}
