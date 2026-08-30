import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/widgets/train_surfaces.dart';
import 'package:lottie/lottie.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/core/widgets/reactive_state_views.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_goal.dart';
import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_plan_status.dart';
import 'package:zivo/features/diet/domain/diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/meal.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plan_page.dart';
import 'package:zivo/features/diet/presentation/pages/meal_detail_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/diet_repository_stub.dart';
import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A repository whose `watchActivePlan()` stream only emits when [emit] is
/// called, so tests can assert on the in-between "waiting" state
/// deterministically.
class _PendingDietRepository extends DietRepositoryStub {
  final StreamController<DietPlan?> _controller = StreamController<DietPlan?>.broadcast();

  @override
  DietPlan? get activePlan => null;

  @override
  Stream<DietPlan?> watchActivePlan() => _controller.stream;

  @override
  Future<void> savePlan(DietPlan plan) async {}

  @override
  Future<void> deletePlan(String id) async {}

  @override
  Stream<Set<String>> watchConsumed(DateTime day) => Stream.value(const <String>{});

  @override
  Future<void> setMealEaten({
    required String mealId,
    required DateTime day,
    required bool eaten,
  }) async {}

  @override
  NutritionTargets? get currentTargets => _targets;

  @override
  Stream<NutritionTargets?> watchTargets() async* {
    yield _targets;
    yield* _targetsController.stream;
  }

  @override
  Future<void> saveTargets(NutritionTargets targets) async {
    _targets = targets;
    _targetsController.add(_targets);
  }

  @override
  Future<void> clearTargets() async {
    _targets = null;
    _targetsController.add(null);
  }



  NutritionTargets? _targets;
  final StreamController<NutritionTargets?> _targetsController =
      StreamController<NutritionTargets?>.broadcast();

  void emit(DietPlan? plan) => _controller.add(plan);

  void emitError(Object error) => _controller.addError(error);

  void dispose() {
    _controller.close();
    _targetsController.close();
  }
}

Widget _wrap({required Widget child, required DietRepository dietOverride}) {
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
  testWidgets('Diet plan page renders the seeded plan and marks a meal eaten', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    await tester.pump();

    // Seeded meals render as CLEAN cards: label + item count, no per-item
    // clutter — the breakdown lives behind View (see the detail-page test).
    expect(find.text('Breakfast'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Rice'), findsNothing,
        reason: 'item names belong to the meal detail page now');

    // Ticking the Lunch row's check marks it eaten reactively. (The row
    // BODY opens the meal now — check ticks, body opens.)
    await tester.tap(find.byKey(const Key('meal-tick-seed-meal-lunch')));
    await tester.pump();

    final consumed = await diet.watchConsumed(DateTime.now()).first;
    expect(consumed, contains('seed-meal-lunch'));
  });

  testWidgets('tapping a meal row opens its dedicated detail page '
      'with the full item breakdown', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    await tester.pump();

    // The row body is the "open" affordance; the check beside it is the tick.
    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();

    // The detail page shows exactly what's in Lunch — items included.
    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('Chicken breast'), findsOneWidget);
    expect(find.byType(MealDetailPage), findsOneWidget);

    // And it can mark the meal done from here.
    await tester.tap(find.text('Done — mark as eaten'));
    await tester.pump();
    final consumed = await diet.watchConsumed(DateTime.now()).first;
    expect(consumed, contains('seed-meal-lunch'));
  });

  testWidgets('supplements are NOT meals: they get their own section and '
      'never count toward meals eaten', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    final plan = diet.activePlan!;
    final today = plan.days.first;
    final withSupplements = DietPlan(
      id: plan.id,
      name: plan.name,
      status: plan.status,
      source: plan.source,
      createdAt: plan.createdAt,
      updatedAt: plan.updatedAt,
      days: [
        DietDay(
          weekday: today.weekday,
          label: today.label,
          meals: [
            ...today.meals,
            const Meal(
              id: 'seed-meal-supps',
              label: 'Supplements',
              order: 99,
              items: [
                FoodItem(name: 'Vitamin D3', quantity: 1, unit: 'pcs'),
              ],
            ),
          ],
        ),
      ],
    );
    await diet.savePlan(withSupplements);
    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    await tester.pump();
    // Let the targets stream and then the consumed-set stream resolve so the
    // hero states real counts (two nested stream builders now: targets, then
    // consumption).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The hero count excludes supplements: 3 real meals, not 4. Asserted
    // BEFORE scrolling, while the hero is still on screen.
    expect(find.textContaining('of 3 meals eaten'), findsOneWidget);

    // The supplements block sits below the meals; scroll it into view.
    await tester.dragUntilVisible(
      find.text('SUPPLEMENTS'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pump();
    // Own section header (mono, uppercase) + own row. Scoped to the section
    // label widget: the full-plan reference card further down lists the block
    // under the same uppercase name.
    expect(
      find.widgetWithText(TrainSectionLabel, 'SUPPLEMENTS'),
      findsOneWidget,
    );
    expect(find.text('Supplements'), findsOneWidget);
    // The tickable supplements row names the block, not its contents — the
    // item breakdown lives on the detail page. (The full-plan reference card
    // further down the same list DOES spell items out, hence the scoping.)
    expect(
      find.descendant(
        of: find.byKey(const Key('supplement-card-seed-meal-supps')),
        matching: find.text('Vitamin D3'),
      ),
      findsNothing,
    );
    // Tapping the supplement ROW marks IT taken without touching meal counts.
    await tester.tap(find.text('Supplements').last);
    await tester.pump();
    expect(
      (await diet.watchConsumed(DateTime.now()).first),
      contains('seed-meal-supps'),
    );
  });

  testWidgets('shows a spinner while the plan stream is waiting, then the plan', (tester) async {
    final diet = _PendingDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));

    expect(find.byType(Lottie), findsOneWidget);
    expect(find.text('No diet plan yet.'), findsNothing);
    // No FAB while the real active plan isn't known yet.
    expect(find.byType(TrainFab), findsNothing);

    diet.emit(
      DietPlan(
        id: 'p1',
        name: 'Cut',
        status: DietPlanStatus.active,
        source: DietSource.manual,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        days: const [],
      ),
    );
    await tester.pump();

    expect(find.byType(Lottie), findsNothing);
    expect(find.text('CUT'), findsOneWidget);
  });

  testWidgets('shows the empty state once the plan stream settles with no data', (tester) async {
    final diet = _PendingDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));

    diet.emit(null);
    await tester.pump();

    expect(find.byType(Lottie), findsNothing);
    expect(find.text('No diet plan yet.'), findsOneWidget);
    expect(find.byType(TrainFab), findsOneWidget);
  });

  testWidgets('shows the error view and hides the FAB when the plan stream errors', (tester) async {
    final diet = _PendingDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));

    diet.emitError(Exception('read denied'));
    await tester.pump();

    expect(find.byType(ErrorStateView), findsOneWidget);
    expect(find.byType(Lottie), findsNothing);
    expect(find.text('No diet plan yet.'), findsNothing);
    // Can't edit a plan that failed to load, so no FAB.
    expect(find.byType(TrainFab), findsNothing);
  });

  testWidgets('deleting the plan from the editor returns to the empty state', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    await tester.pump();

    // Open the editor for the existing (seeded) plan via the FAB.
    await tester.tap(find.byType(TrainFab));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('diet-plan-delete')), findsOneWidget);
    await tester.tap(find.byKey(const Key('diet-plan-delete')));
    await tester.pumpAndSettle();

    // Confirm dialog appears; confirm the delete.
    expect(find.text('Delete this plan?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(diet.activePlan, isNull);
    expect(find.text('No diet plan yet.'), findsOneWidget);
  });

  testWidgets('an AI-estimated plan marks every total it derives as an '
      'estimate — the hero number, its label, the macro bars and the meal row',
      (tester) async {
    // An imported plan's figures were generated by the model at import time.
    // Rendering "700" and "~700" identically is the trust bug: the screen
    // claims a precision the number does not have.
    final diet = _PendingDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    diet.emit(
      DietPlan(
        id: 'p1',
        name: 'Imported',
        status: DietPlanStatus.active,
        source: DietSource.pdf,
        createdAt: DateTime(2026, 8, 30),
        updatedAt: DateTime(2026, 8, 30),
        days: [
          DietDay(
            label: 'Every day',
            meals: [
              Meal(
                id: 'm1',
                label: 'Lunch',
                order: 0,
                items: const [
                  FoodItem(
                    name: 'Rice',
                    quantity: 100,
                    unit: 'g',
                    calories: 700,
                    proteinG: 20,
                    carbsG: 100,
                    fatG: 10,
                    estimated: true,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('~700'), findsWidgets,
        reason: 'the hero number and the meal row both carry the marker');
    expect(find.text('EST. KCAL LEFT OF PLAN'), findsOneWidget,
        reason: 'the ring label says both what it measures and that it is '
            'an estimate');
    expect(find.text('KCAL LEFT OF PLAN'), findsNothing);
    expect(find.textContaining('IMPORTED · PLANNED ~700 KCAL'), findsOneWidget);
    // Macro targets come from the same items, so they are marked too.
    expect(find.text('0/~20g'), findsOneWidget);
  });

  testWidgets('a plan the user typed themselves carries no estimate marker',
      (tester) async {
    // The other half of the contract: "~" must mean something, so it may not
    // appear on figures the user entered.
    final diet = _PendingDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    diet.emit(
      DietPlan(
        id: 'p1',
        name: 'Manual',
        status: DietPlanStatus.active,
        source: DietSource.manual,
        createdAt: DateTime(2026, 8, 30),
        updatedAt: DateTime(2026, 8, 30),
        days: [
          DietDay(
            label: 'Every day',
            meals: [
              Meal(
                id: 'm1',
                label: 'Lunch',
                order: 0,
                items: const [
                  FoodItem(
                    name: 'Rice',
                    quantity: 100,
                    unit: 'g',
                    calories: 700,
                    proteinG: 20,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KCAL LEFT OF PLAN'), findsOneWidget);
    expect(find.text('EST. KCAL LEFT OF PLAN'), findsNothing);
    expect(find.text('~700'), findsNothing);
    expect(find.text('0/20g'), findsOneWidget);
  });

  // ── Targets ──────────────────────────────────────────────────────────────
  // The screen must never imply a goal the user didn't set, and once they do
  // set one, every figure on it has to be measured against that and say so.

  testWidgets('with no target set, the screen says so and measures against '
      'the plan — never passing the plan off as a goal', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('no-target-card')), findsOneWidget);
    expect(find.text('No daily target set'), findsOneWidget);
    // The ring names its yardstick rather than implying an objective.
    expect(find.text('KCAL LEFT OF PLAN'), findsOneWidget);
    expect(find.byKey(const Key('target-summary-row')), findsNothing);
    expect(find.textContaining('TARGET'), findsNothing);
  });

  testWidgets('with a target set, the hero counts down THAT target and the '
      'header labels both numbers', (tester) async {
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

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Nothing ticked yet: the whole target is left.
    expect(find.text('2200'), findsOneWidget);
    expect(find.text('KCAL LEFT'), findsOneWidget);
    expect(find.byKey(const Key('no-target-card')), findsNothing);

    // The goal and where the number came from are both on screen.
    expect(find.byKey(const Key('target-summary-row')), findsOneWidget);
    expect(find.textContaining('FAT LOSS · 2200 KCAL/DAY'), findsOneWidget);
    expect(find.textContaining('You set this'), findsOneWidget);

    // Two figures on the header caption, each labelled — the target the user
    // chose and what today's plan happens to add up to.
    expect(find.textContaining('TARGET 2200 KCAL'), findsOneWidget);
    expect(find.textContaining('PLANNED 1270 KCAL'), findsOneWidget);

    // Only the macro the user actually set a target for gets a bar.
    expect(find.text('0/160g'), findsOneWidget);
    expect(find.text('PROTEIN'), findsOneWidget);
    expect(find.text('CARBS'), findsNothing);
  });

  testWidgets('ticking a meal counts down the target, and going past it reads '
      'as OVER rather than a clamped zero', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    await diet.saveTargets(
      NutritionTargets(
        goal: DietGoal.maintain,
        calories: 400,
        source: TargetSource.manual,
        updatedAt: DateTime(2026, 8, 30),
      ),
    );

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('400'), findsOneWidget);

    // Breakfast is 310 kcal in the seeded plan — still under.
    await tester.tap(find.byKey(const Key('meal-tick-seed-meal-breakfast')));
    await tester.pump();
    expect(find.text('90'), findsOneWidget);
    expect(find.text('KCAL LEFT'), findsOneWidget);

    // Lunch (540) pushes it well past the target.
    await tester.tap(find.byKey(const Key('meal-tick-seed-meal-lunch')));
    await tester.pump();
    expect(find.text('KCAL OVER'), findsOneWidget);
    expect(find.text('450'), findsOneWidget);
  });

  testWidgets('a target under the safety floor is called out on the screen '
      'itself, not left to the coach to notice', (tester) async {
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

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.textContaining('worth checking with a professional'),
      findsOneWidget,
    );
  });
}
