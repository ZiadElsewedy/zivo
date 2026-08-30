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
import 'package:zivo/features/diet/domain/nutrition/food_log_entry.dart';
import 'package:zivo/features/diet/domain/nutrition/food_reference.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plan_edit_page.dart';
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

/// A plan whose days are all weekdays that AREN'T today, so `dayForDate`
/// resolves nothing. Two of them, deliberately: a single-day plan falls
/// back to that day whatever the weekday is.
DietPlan _planWithNoDayForToday(DateTime now) {
  final others = [
    for (var w = 1; w <= 7; w++)
      if (w != now.weekday) w,
  ].take(2);
  return DietPlan(
    id: 'p-elsewhere',
    name: 'Split',
    status: DietPlanStatus.active,
    source: DietSource.manual,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    days: [
      for (final weekday in others)
        DietDay(
          weekday: weekday,
          label: 'Day $weekday',
          meals: const [
            Meal(
              id: 'm-other',
              label: 'Lunch',
              order: 0,
              items: [
                FoodItem(
                  name: 'Rice',
                  quantity: 200,
                  unit: 'g',
                  calories: 500,
                ),
              ],
            ),
          ],
        ),
    ],
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

    // Ticked through the repository rather than by tapping the rows: this is
    // a test about the HERO, and the meal rows now sit below Today's read,
    // off-screen at this viewport. (The tick affordance itself is covered by
    // the first test in this file.) The reactive path is the same either way
    // — the consumption stream is what the hero rebuilds from.
    final today = DateTime.now();

    // Breakfast is 310 kcal in the seeded plan — still under.
    await diet.setMealEaten(
      mealId: 'seed-meal-breakfast',
      day: today,
      eaten: true,
    );
    await tester.pump();
    expect(find.text('90'), findsOneWidget);
    expect(find.text('KCAL LEFT'), findsOneWidget);

    // Lunch (540) pushes it well past the target.
    await diet.setMealEaten(mealId: 'seed-meal-lunch', day: today, eaten: true);
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

  testWidgets('the coaching engine\'s read is on the screen, not only in the '
      'chat — and each line opens onto the figures behind it', (tester) async {
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
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('no-target-card')), findsOneWidget);
    expect(find.byKey(const Key('todays-read')), findsNothing);
  });

  testWidgets('the hero says what its EATEN figure rests on: ticking meals is '
      'never presented as weighed food', (tester) async {
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

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
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

  testWidgets('a calculated target explains itself — the body data it came '
      'from, not just that a formula ran', (tester) async {
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

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Calculated from your body data'), findsOneWidget);
    expect(
      find.text('82 kg · moderate · 2790 kcal maintenance'),
      findsOneWidget,
    );
  });

  testWidgets('a day with no plan day still measures the day: the objective, '
      'what was eaten, and the read all survive the missing plan',
      (tester) async {
    final now = DateTime.now();
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    await diet.savePlan(_planWithNoDayForToday(now));
    await diet.saveTargets(
      NutritionTargets(
        goal: DietGoal.maintain,
        calories: 2000,
        proteinG: 150,
        source: TargetSource.manual,
        updatedAt: DateTime(2026, 8, 30),
      ),
    );
    // Eaten today, with no plan day to have eaten it against.
    await diet.logFood([
      FoodLogEntry(
        id: 'e1',
        day: now,
        loggedAt: now,
        foodId: 'usda:1',
        foodName: 'Chicken breast',
        quantity: 250,
        unit: 'g',
        grams: 250,
        kcal: 600,
        proteinG: 90,
        carbsG: 0,
        fatG: 20,
        source: NutritionSource.usdaFdc,
        sourceRef: '1',
        origin: FoodLogOrigin.logged,
      ),
    ]);

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Still said plainly — and still first.
    expect(find.text('No plan for today.'), findsOneWidget);

    // But the screen no longer stops there. 2000 − 600, measured against the
    // target rather than against a plan that has nothing to say today.
    expect(find.text('1400'), findsOneWidget);
    expect(find.text('KCAL LEFT'), findsOneWidget);
    expect(find.text('LOGGED BY YOU'), findsOneWidget);
    expect(find.byKey(const Key('target-summary-row')), findsOneWidget);
    expect(find.byKey(const Key('todays-read')), findsOneWidget);

    // The meal count would be "0 of 0" — an absence, not a failure, so the
    // hero says neither.
    expect(find.textContaining('meals eaten'), findsNothing);
    // And there is no Meals section, because there are no meals: that part
    // genuinely IS the plan day.
    expect(find.widgetWithText(TrainSectionLabel, 'MEALS'), findsNothing);
  });

  testWidgets('with neither a plan day nor a target there is no yardstick, and '
      'the screen says so instead of drawing an empty ring', (tester) async {
    final now = DateTime.now();
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    await diet.savePlan(_planWithNoDayForToday(now));

    await tester.pumpWidget(_wrap(child: const DietPlanPage(), dietOverride: diet));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No plan for today.'), findsOneWidget);
    // No hero, and no "set a target" card either — its copy points at
    // "the numbers above", and there are none.
    expect(find.byKey(const Key('hero-consumed-basis')), findsNothing);
    expect(find.byKey(const Key('no-target-card')), findsNothing);
    expect(find.byKey(const Key('todays-read')), findsNothing);
    // The log is still reachable: something eaten can always be recorded.
    expect(find.byKey(const Key('log-food-button')), findsOneWidget);
  });

  testWidgets('the plan editor — the review gate for an imported plan — says '
      'when an item\'s calories contradict its own macros', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    final plan = DietPlan(
      id: 'imported',
      name: 'Imported',
      status: DietPlanStatus.active,
      source: DietSource.pdf,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      days: const [
        DietDay(
          label: 'Every day',
          meals: [
            Meal(
              id: 'm1',
              label: 'Lunch',
              order: 0,
              items: [
                // 12/8/3 comes to 107 kcal, not 600 — the model contradicting
                // itself, which is the whole reason this check exists.
                FoodItem(
                  name: 'Mystery bowl',
                  quantity: 1,
                  unit: 'pcs',
                  calories: 600,
                  proteinG: 12,
                  carbsG: 8,
                  fatG: 3,
                  estimated: true,
                ),
                // 31/0/3.6 → 156. Close enough that saying anything would
                // only teach the user to ignore the flag.
                FoodItem(
                  name: 'Chicken breast',
                  quantity: 100,
                  unit: 'g',
                  calories: 165,
                  proteinG: 31,
                  carbsG: 0,
                  fatG: 3.6,
                  estimated: true,
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(child: DietPlanEditPage(initialPlan: plan), dietOverride: diet),
    );
    await tester.pumpAndSettle();

    // Both numbers, so the user can check the arithmetic rather than take a
    // verdict on trust.
    expect(
      find.text('Says 600 kcal; its macros come to 107'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('item-crosscheck-m1-0')), findsOneWidget);
    // And nothing at all on the item that adds up.
    expect(find.byKey(const Key('item-crosscheck-m1-1')), findsNothing);

    // It flags; it never blocks. Save is still there to be pressed.
    expect(find.text('Save plan'), findsOneWidget);
  });
}
