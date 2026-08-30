import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_goal.dart';
import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_plan_status.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/meal.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plan_page.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plans_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap({required Widget child, required InMemoryDietRepository diet}) =>
    AppScope(
      auth: FakeAuthRepository(),
      profiles: FakeProfileRepository(),
      expenses: InMemoryExpenseRepository(),
      moments: InMemoryMomentRepository(),
      workouts: InMemoryWorkoutRepository(),
      workoutPlans: InMemoryWorkoutPlanRepository(),
      workoutSessions: InMemoryWorkoutSessionRepository(),
      diet: diet,
      ai: FakeAiRepository(),
      child: MaterialApp(home: child),
    );

DietPlan _plan({
  required String id,
  required String name,
  DietPlanStatus status = DietPlanStatus.archived,
  int kcal = 2400,
  double? proteinG,
  DateTime? createdAt,
}) => DietPlan(
  id: id,
  name: name,
  status: status,
  source: DietSource.pdf,
  createdAt: createdAt ?? DateTime(2026, 1, 1),
  updatedAt: createdAt ?? DateTime(2026, 1, 1),
  days: [
    DietDay(
      label: 'Every day',
      meals: [
        Meal(
          id: '$id-m1',
          label: 'Lunch',
          order: 0,
          items: [
            FoodItem(
              name: 'Rice and chicken',
              quantity: 400,
              unit: 'g',
              calories: kcal,
              proteinG: proteinG,
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  group('the single-active invariant', () {
    test('saving an active plan archives the one that was active', () async {
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final seeded = diet.activePlan!;

      await diet.savePlan(
        _plan(
          id: 'p2',
          name: 'Bulk',
          status: DietPlanStatus.active,
          createdAt: DateTime(2026, 6, 1),
        ),
      );

      expect(diet.activePlan!.id, 'p2');
      expect(diet.plans, hasLength(2));
      expect(
        diet.plans.where((p) => p.status == DietPlanStatus.active),
        hasLength(1),
      );
      expect(
        diet.plans.firstWhere((p) => p.id == seeded.id).status,
        DietPlanStatus.archived,
      );
    });

    test('activating an archived plan swaps which one is in force', () async {
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final seeded = diet.activePlan!;
      await diet.savePlan(_plan(id: 'p2', name: 'Cut'));

      await diet.setActivePlan('p2');
      expect(diet.activePlan!.id, 'p2');
      expect(
        diet.plans.firstWhere((p) => p.id == seeded.id).status,
        DietPlanStatus.archived,
      );

      // And back again — the swap is not one-way.
      await diet.setActivePlan(seeded.id);
      expect(diet.activePlan!.id, seeded.id);
      expect(
        diet.plans.firstWhere((p) => p.id == 'p2').status,
        DietPlanStatus.archived,
      );
    });

    test('activating a plan that does not exist changes nothing', () async {
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final seeded = diet.activePlan!;

      await diet.setActivePlan('nope');

      // Crucially it did NOT leave the user with nothing active.
      expect(diet.activePlan!.id, seeded.id);
    });

    test(
      'archiving the active plan leaves none active, not none at all',
      () async {
        final diet = InMemoryDietRepository();
        addTearDown(diet.dispose);
        final seeded = diet.activePlan!;

        await diet.archivePlan(seeded.id);

        expect(diet.activePlan, isNull);
        expect(diet.plans, hasLength(1));
      },
    );

    test('the active stream follows the library', () async {
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final seen = <String?>[];
      final sub = diet.watchActivePlan().listen((p) => seen.add(p?.id));
      await Future<void>.delayed(Duration.zero);

      await diet.savePlan(_plan(id: 'p2', name: 'Cut'));
      await diet.setActivePlan('p2');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(seen.first, 'seed-diet-1');
      expect(seen.last, 'p2');
    });

    test('deleting removes it from the library', () async {
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      await diet.savePlan(_plan(id: 'p2', name: 'Cut'));

      await diet.deletePlan('p2');

      expect(diet.plans.map((p) => p.id), isNot(contains('p2')));
      expect(diet.activePlan, isNotNull);
    });
  });

  group('the library screen', () {
    testWidgets('lists every plan and says which one is in force', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      await diet.savePlan(_plan(id: 'p2', name: 'Winter bulk'));

      await tester.pumpWidget(_wrap(child: const DietPlansPage(), diet: diet));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('plan-card-seed-diet-1')), findsOneWidget);
      expect(find.byKey(const Key('plan-card-p2')), findsOneWidget);
      expect(find.text('FOLLOWING'), findsOneWidget);
      expect(find.text('ARCHIVED'), findsOneWidget);
    });

    testWidgets('following another plan swaps the active one', (tester) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      await diet.savePlan(_plan(id: 'p2', name: 'Winter bulk'));

      await tester.pumpWidget(_wrap(child: const DietPlansPage(), diet: diet));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('activate-p2')));
      await tester.pumpAndSettle();

      expect(diet.activePlan!.id, 'p2');
      // The badge moved with it.
      expect(find.text('FOLLOWING'), findsOneWidget);
    });

    testWidgets('stopping following archives rather than deletes', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);

      await tester.pumpWidget(_wrap(child: const DietPlansPage(), diet: diet));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('archive-seed-diet-1')));
      await tester.pumpAndSettle();

      expect(diet.activePlan, isNull);
      expect(diet.plans, hasLength(1), reason: 'archived, not deleted');
    });

    testWidgets('deleting asks first, and cancelling keeps the plan', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);

      await tester.pumpWidget(_wrap(child: const DietPlansPage(), diet: diet));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('delete-seed-diet-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(diet.plans, hasLength(1));

      await tester.tap(find.byKey(const Key('delete-seed-diet-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-delete-plan')));
      await tester.pumpAndSettle();
      expect(diet.plans, isEmpty);
    });
  });

  group('the Diet screen with an archived library', () {
    testWidgets('says you are not following a plan, not that you have none', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      await diet.archivePlan(diet.activePlan!.id);

      await tester.pumpWidget(_wrap(child: const DietPlanPage(), diet: diet));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('diet-empty-headline'))).data,
        "You're not following a plan.",
      );
      expect(
        find.text('1 plan is archived — pick one back up, or add another.'),
        findsOneWidget,
      );
    });

    testWidgets('and the way back to the library is on the screen', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      await diet.archivePlan(diet.activePlan!.id);

      await tester.pumpWidget(_wrap(child: const DietPlanPage(), diet: diet));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('empty-open-library')));
      await tester.pumpAndSettle();
      expect(find.byType(DietPlansPage), findsOneWidget);
    });
  });

  group('adopting the plan as a target', () {
    testWidgets('offers the plan\'s own figure and asks what it is for', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);

      await tester.pumpWidget(_wrap(child: const DietPlanPage(), diet: diet));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('no-target-card')), findsOneWidget);
      await tester.tap(find.byKey(const Key('adopt-plan-target')));
      await tester.pumpAndSettle();

      // Nothing is saved yet: a target is a goal plus numbers, and only the
      // user knows the goal.
      expect(diet.currentTargets, isNull);
      expect(find.byKey(const Key('adopt-summary')), findsOneWidget);

      await tester.tap(find.byKey(const Key('adopt-goal-fatLoss')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('adopt-save')));
      await tester.pumpAndSettle();

      final targets = diet.currentTargets!;
      // The seeded plan's single day totals 1270 kcal.
      expect(targets.calories, 1270);
      expect(targets.goal, DietGoal.fatLoss);
      // Provenance says exactly what happened: accepted from the plan.
      expect(targets.source, TargetSource.planDerived);
      expect(targets.basis, isNull);
    });

    testWidgets('the plan\'s macros come along, and absent stays absent', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      await diet.savePlan(
        _plan(
          id: 'p2',
          name: 'Cut',
          status: DietPlanStatus.active,
          kcal: 2000,
          proteinG: 180,
          createdAt: DateTime(2026, 6, 1),
        ),
      );

      await tester.pumpWidget(_wrap(child: const DietPlanPage(), diet: diet));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('adopt-plan-target')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('adopt-goal-muscleGain')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('adopt-save')));
      await tester.pumpAndSettle();

      final targets = diet.currentTargets!;
      expect(targets.calories, 2000);
      expect(targets.proteinG, 180);
      // The plan states no carbs or fat, so neither becomes a zero target.
      expect(targets.carbsG, isNull);
      expect(targets.fatG, isNull);
    });

    testWidgets('a plan under the safety floor says so before you adopt it', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      await diet.savePlan(
        _plan(
          id: 'p2',
          name: 'Crash',
          status: DietPlanStatus.active,
          kcal: 900,
          createdAt: DateTime(2026, 6, 1),
        ),
      );

      await tester.pumpWidget(_wrap(child: const DietPlanPage(), diet: diet));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('adopt-plan-target')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adopt-safety-floor')), findsOneWidget);
    });
  });
}
