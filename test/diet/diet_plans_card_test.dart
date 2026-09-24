import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/body_profile.dart';
import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_plan_status.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/meal.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plans_page.dart';
import 'package:zivo/features/capture/presentation/widgets/capture_widgets.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/body_weight_entry.dart';

import '../support/bidi_finders.dart';
import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

Widget _wrap(InMemoryDietRepository diet, InMemoryBodyWeightRepository w) =>
    AppScope(
      auth: FakeAuthRepository(
        initial: const Authenticated(AuthUser(uid: 'fake-uid')),
      ),
      profiles: FakeProfileRepository(),
      expenses: InMemoryExpenseRepository(),
      moments: InMemoryMomentRepository(),
      workouts: InMemoryWorkoutRepository(),
      workoutPlans: InMemoryWorkoutPlanRepository(),
      workoutSessions: InMemoryWorkoutSessionRepository(),
      bodyWeight: w,
      diet: diet,
      ai: FakeAiRepository(),
      child: const MaterialApp(home: DietPlansPage()),
    );

/// A generated plan: 4 meals a day, 400 kcal each → 1600 kcal a day, well
/// under the 2400 kcal maintenance the profile states.
DietPlan _generated() => DietPlan(
  id: 'gen',
  name: 'Egyptian High-Protein Fat Loss',
  status: DietPlanStatus.archived,
  source: DietSource.generated,
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 1),
  days: [
    for (var d = 0; d < 7; d++)
      DietDay(
        label: 'Day ${d + 1}',
        meals: [
          for (var m = 0; m < 4; m++)
            Meal(
              id: 'd$d-m$m',
              label: 'Meal ${m + 1}',
              order: m,
              items: const [
                FoodItem(name: 'Chicken', quantity: 200, unit: 'g', calories: 400),
              ],
            ),
        ],
      ),
  ],
);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final diet = InMemoryDietRepository();
  addTearDown(diet.dispose);
  await diet.saveBodyProfile(BodyProfile(
    heightCm: 178,
    sex: TargetSex.male,
    activity: ActivityLevel.moderate,
    statedMaintenanceKcal: 2400,
    updatedAt: DateTime(2026, 8, 30),
  ));
  await diet.savePlan(_generated());
  final weights = InMemoryBodyWeightRepository(
    seed: [
      BodyWeightEntry(
        id: 'w1',
        weightKg: 82,
        loggedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ],
  );
  await tester.pumpWidget(_wrap(diet, weights));
  await tester.pumpAndSettle();
}

double _fontSize(WidgetTester tester, Finder f) {
  final text = tester.widget<Text>(f);
  return (text.style?.fontSize ?? text.textSpan?.style?.fontSize)!;
}

void main() {
  testWidgets('a plan card is a clean summary: name, goal · meals, daily '
      'calories, one outcome line, status', (tester) async {
    await _pump(tester);
    final card = find.byKey(const Key('plan-card-gen'));
    Finder inCard(Finder f) => find.descendant(of: card, matching: f);

    expect(
      inCard(findTextIgnoringBidi('Egyptian High-Protein Fat Loss')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('plan-summary-gen'))).data,
      'Fat loss · 4 meals',
    );
    final kcal = tester.widget<Text>(find.byKey(const Key('plan-kcal-gen')));
    expect(kcal.textSpan!.toPlainText(), '1600 kcal/day');
    expect(
      tester.widget<Text>(find.byKey(const Key('plan-verdict-gen'))).data,
      startsWith('Losing ~'),
    );
    expect(inCard(find.text('ARCHIVED')), findsOneWidget);
  });

  testWidgets('record metadata is gone and the actions stay quiet', (
    tester,
  ) async {
    await _pump(tester);
    final card = find.byKey(const Key('plan-card-gen'));
    Finder inCard(Finder f) => find.descendant(of: card, matching: f);

    // No source badge, no day count, no all-caps metadata run.
    expect(inCard(find.textContaining('BUILT BY ZIVO')), findsNothing);
    expect(inCard(find.textContaining('Built by ZIVO')), findsNothing);
    expect(inCard(find.textContaining('DAYS')), findsNothing);
    expect(inCard(find.textContaining('KCAL/DAY')), findsNothing);

    // The name leads; the summary line sits below it in weight.
    expect(
      _fontSize(tester, find.byKey(const Key('plan-name-gen'))),
      greaterThan(_fontSize(tester, find.byKey(const Key('plan-summary-gen')))),
    );

    // Follow / Delete remain, but as a text action and an icon — no
    // full-width filled button competing with the plan itself.
    expect(find.byKey(const Key('activate-gen')), findsOneWidget);
    expect(find.byKey(const Key('delete-gen')), findsOneWidget);
    expect(inCard(find.byType(PillButton)), findsNothing);
    expect(inCard(find.text('Delete')), findsNothing);

    // Compact: a summary, not a record.
    expect(tester.getSize(card).height, lessThan(200));
  });
}
