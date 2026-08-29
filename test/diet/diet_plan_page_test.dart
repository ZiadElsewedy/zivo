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
import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_plan_status.dart';
import 'package:zivo/features/diet/domain/diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/meal.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plan_page.dart';
import 'package:zivo/features/diet/presentation/pages/meal_detail_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A repository whose `watchActivePlan()` stream only emits when [emit] is
/// called, so tests can assert on the in-between "waiting" state
/// deterministically.
class _PendingDietRepository implements DietRepository {
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

  void emit(DietPlan? plan) => _controller.add(plan);

  void emitError(Object error) => _controller.addError(error);

  void dispose() => _controller.close();
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
    // Let the consumed-set stream resolve so the hero states real counts.
    await tester.pump(const Duration(milliseconds: 50));
    // Own section header (mono, uppercase) + own row.
    expect(find.text('SUPPLEMENTS'), findsOneWidget);
    expect(find.text('Supplements'), findsOneWidget);
    expect(find.text('Vitamin D3'), findsNothing,
        reason: 'supplement items live on the detail page too');
    // The hero count excludes supplements: 3 real meals, not 4.
    expect(find.textContaining('of 3 meals eaten'), findsOneWidget);

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
}
