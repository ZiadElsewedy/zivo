import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_goal.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plan_details_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// **Plan details** — the screen the Diet surface's arithmetic moved to in the
/// simplification pass.
///
/// Every assertion below used to be made against `DietPlanPage`. They are
/// unchanged: the contracts they protect (never imply a goal the user didn't
/// set, a target explains where it came from, the safety floor is called out
/// on a screen and not left to the coach, the coaching read is visible outside
/// the chat, a consumed figure always travels with its basis) are the same
/// contracts — they are just no longer allowed to crowd the meal list.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap({
  required Widget child,
  required InMemoryDietRepository dietOverride,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: InMemoryWorkoutSessionRepository(),
    diet: dietOverride,
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('with no target set it says so, and offers the plan\'s own '
      'figure rather than adopting it silently', (tester) async {
    _tallViewport(tester);
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(
      _wrap(
        child: DietPlanDetailsPage(plan: diet.activePlan!),
        dietOverride: diet,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('no-target-card')), findsOneWidget);
    expect(find.text('No daily target set'), findsOneWidget);
    expect(find.byKey(const Key('target-summary-row')), findsNothing);
  });

  testWidgets('a set target states its goal, its figure and its provenance, '
      'and its macros get bars', (tester) async {
    _tallViewport(tester);
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    await diet.saveTargets(
      NutritionTargets(
        goal: DietGoal.fatLoss,
        calories: 2200,
        proteinG: 160,
        source: TargetSource.manual,
        updatedAt: DateTime(2026, 8, 30),
      ),
    );

    await tester.pumpWidget(
      _wrap(
        child: DietPlanDetailsPage(plan: diet.activePlan!),
        dietOverride: diet,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('no-target-card')), findsNothing);
    expect(find.byKey(const Key('target-summary-row')), findsOneWidget);
    expect(find.textContaining('FAT LOSS · 2200 KCAL/DAY'), findsOneWidget);
    expect(find.textContaining('You set this'), findsOneWidget);

    // Only the macro the user actually set a target for gets a bar.
    expect(find.text('0/160g'), findsOneWidget);
    expect(find.text('PROTEIN'), findsOneWidget);
    expect(find.text('CARBS'), findsNothing);
  });

  testWidgets('the consumed figure never appears without saying what it rests '
      'on: ticking meals is not weighed food', (tester) async {
    _tallViewport(tester);
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    await diet.saveTargets(
      NutritionTargets(
        goal: DietGoal.maintain,
        calories: 2000,
        source: TargetSource.manual,
        updatedAt: DateTime(2026, 8, 30),
      ),
    );

    await tester.pumpWidget(
      _wrap(
        child: DietPlanDetailsPage(plan: diet.activePlan!),
        dietOverride: diet,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('NOTHING LOGGED YET'), findsOneWidget);

    // Ticking a plan meal credits the PLAN's figures. The number moves, and
    // the line beneath it says where the number came from.
    await diet.setMealEaten(
      mealId: 'seed-meal-breakfast',
      day: DateTime.now(),
      eaten: true,
    );
    await tester.pump();
    expect(find.text('FROM TICKED MEALS, NOT WEIGHED'), findsOneWidget);
  });

  testWidgets('a target under the safety floor is called out on the screen '
      'itself, not left to the coach to notice', (tester) async {
    _tallViewport(tester);
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    await diet.saveTargets(
      NutritionTargets(
        goal: DietGoal.fatLoss,
        calories: 900,
        source: TargetSource.manual,
        updatedAt: DateTime(2026, 8, 30),
      ),
    );

    await tester.pumpWidget(
      _wrap(
        child: DietPlanDetailsPage(plan: diet.activePlan!),
        dietOverride: diet,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.textContaining('worth checking with a professional'),
      findsOneWidget,
    );
  });

  testWidgets('the coaching engine\'s read is on the screen, not only in the '
      'chat — and each line opens onto the figures behind it', (tester) async {
    _tallViewport(tester);
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    await diet.saveTargets(
      NutritionTargets(
        goal: DietGoal.fatLoss,
        calories: 2200,
        proteinG: 160,
        source: TargetSource.manual,
        updatedAt: DateTime(2026, 8, 30),
      ),
    );

    await tester.pumpWidget(
      _wrap(
        child: DietPlanDetailsPage(plan: diet.activePlan!),
        dietOverride: diet,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Breakfast is 310 kcal in the seeded plan, leaving 1890.
    await diet.setMealEaten(
      mealId: 'seed-meal-breakfast',
      day: DateTime.now(),
      eaten: true,
    );
    await tester.pump();

    // The card is built from the page's own DietState — the same object the
    // hero draws — so what it says can't disagree with the ring above it.
    expect(find.byKey(const Key('todays-read')), findsOneWidget);
    expect(find.textContaining('1890 kcal left'), findsOneWidget);

    // And the "why" is a real answer: the state fields, with their values.
    final why = find.byKey(const Key('finding-why-calories_remaining'));
    await tester.ensureVisible(why);
    await tester.pump();
    await tester.tap(why);
    await tester.pump();
    expect(find.text('Calories left'), findsOneWidget);
    expect(find.text('1890 kcal'), findsOneWidget);
    expect(find.text('Goal'), findsOneWidget);
    expect(find.text('Fat loss'), findsOneWidget);
  });

  testWidgets('with no target set the read is held back — the empty-state card '
      'already says it, with somewhere to tap', (tester) async {
    _tallViewport(tester);
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(
      _wrap(
        child: DietPlanDetailsPage(plan: diet.activePlan!),
        dietOverride: diet,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('no-target-card')), findsOneWidget);
    expect(find.byKey(const Key('todays-read')), findsNothing);
  });

  testWidgets('a calculated target explains itself — the body data it came '
      'from, not just that a formula ran', (tester) async {
    _tallViewport(tester);
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    await diet.saveTargets(
      NutritionTargets(
        goal: DietGoal.fatLoss,
        calories: 2230,
        source: TargetSource.calculated,
        basis: const TargetBasis(
          weightKg: 82,
          heightCm: 180,
          age: 30,
          sex: TargetSex.male,
          activity: ActivityLevel.moderate,
          bmr: 1800,
          maintenanceCalories: 2790,
        ),
        updatedAt: DateTime(2026, 8, 30),
      ),
    );

    await tester.pumpWidget(
      _wrap(
        child: DietPlanDetailsPage(plan: diet.activePlan!),
        dietOverride: diet,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Calculated from your body data'), findsOneWidget);
    expect(
      find.text('82 kg · moderate · 2790 kcal maintenance'),
      findsOneWidget,
    );
  });
}
