import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/auth/domain/profile_repository.dart';
import 'package:zivo/features/auth/domain/user_profile.dart';
import 'package:zivo/features/diet/domain/body_profile.dart';
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';
import 'package:zivo/features/workout/domain/body_weight_entry.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_goal.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/presentation/pages/body_profile_page.dart';
import 'package:zivo/features/diet/presentation/pages/diet_targets_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// Body data now comes from where the user already entered it — the body
/// profile, the weigh-in log and the account's date of birth — instead of
/// being typed into the calculator a second time. [bodyWeight] is what lets a
/// test supply the weigh-in half of that.
Widget _wrap({
  required Widget child,
  required InMemoryDietRepository diet,
  InMemoryBodyWeightRepository? bodyWeight,
  ProfileRepository? profiles,
}) {
  return AppScope(
    auth: FakeAuthRepository(
      initial: const Authenticated(AuthUser(uid: 'fake-uid')),
    ),
    profiles: profiles ?? FakeProfileRepository(),
    bodyWeight: bodyWeight,
    expenses: InMemoryExpenseRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: InMemoryWorkoutSessionRepository(),
    diet: diet,
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

/// Taps [finder] after scrolling it into view.
///
/// `tester.tap` does NOT fail when its target is below the fold — it warns and
/// hits nothing, and the test then fails somewhere unrelated. Worse here: the
/// page is a lazy `ListView`, so a control far down the form isn't merely
/// off-screen, it hasn't been built at all and no finder can see it. Every tap
/// goes through this helper (the same rule `live_session_page_test`'s `_tap`
/// follows), scrolling the named list until the target exists.
Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  Key list = const Key('targets-list'),
}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      140,
      // `.first` is load-bearing: every TextField on the form contains its
      // own Scrollable, so the descendant finder matches many. The outermost
      // one is the list itself.
      scrollable: find
          .descendant(of: find.byKey(list), matching: find.byType(Scrollable))
          .first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('nothing is saved until the user taps Save — the page proposes, '
      'it never decides', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(
      _wrap(child: const DietTargetsPage(), diet: diet),
    );
    await tester.pump();

    // Filling everything in still writes nothing.
    await _tap(tester, find.byKey(const Key('goal-fatLoss')));
    await tester.enterText(find.byKey(const Key('target-calories')), '2200');
    await tester.enterText(find.byKey(const Key('target-protein')), '160');
    await tester.pump();
    expect(diet.currentTargets, isNull);

    await _tap(tester, find.byKey(const Key('save-targets')));

    expect(diet.currentTargets, isNotNull);
    expect(diet.currentTargets!.goal, DietGoal.fatLoss);
    expect(diet.currentTargets!.calories, 2200);
    expect(diet.currentTargets!.proteinG, 160);
    // Typed by hand, so recorded as such — provenance is part of the target.
    expect(diet.currentTargets!.source, TargetSource.manual);
    expect(diet.currentTargets!.basis, isNull);
  });

  testWidgets('a blank macro saves as null, not zero', (tester) async {
    // "I'm not tracking carbs" and "my carb target is 0g" are different
    // statements, and the coach behaves differently for each.
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(
      _wrap(child: const DietTargetsPage(), diet: diet),
    );
    await tester.pump();
    await _tap(tester, find.byKey(const Key('goal-maintain')));
    await tester.enterText(find.byKey(const Key('target-calories')), '2000');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('save-targets')));

    expect(diet.currentTargets!.calories, 2000);
    expect(diet.currentTargets!.proteinG, isNull);
    expect(diet.currentTargets!.carbsG, isNull);
    expect(diet.currentTargets!.fatG, isNull);
  });

  testWidgets('Save stays disabled until there is a goal AND a calorie figure',
      (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(
      _wrap(child: const DietTargetsPage(), diet: diet),
    );
    await tester.pump();

    // A goal with no number saves nothing.
    await _tap(tester, find.byKey(const Key('goal-fatLoss')));
    await _tap(tester, find.byKey(const Key('save-targets')));
    expect(diet.currentTargets, isNull);

    // A number with no goal saves nothing either.
    await tester.enterText(find.byKey(const Key('target-calories')), '0');
    await tester.pump();
    await _tap(tester, find.byKey(const Key('save-targets')));
    expect(diet.currentTargets, isNull);
  });

  testWidgets('the low-calorie warning appears as soon as the number does',
      (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(
      _wrap(child: const DietTargetsPage(), diet: diet),
    );
    await tester.pump();
    expect(find.byKey(const Key('target-safety-note')), findsNothing);

    await tester.enterText(find.byKey(const Key('target-calories')), '900');
    await tester.pump();
    expect(find.byKey(const Key('target-safety-note')), findsOneWidget);
    expect(find.textContaining('registered dietitian'), findsOneWidget);

    // ...and clears once the figure is back above the floor.
    await tester.enterText(find.byKey(const Key('target-calories')), '2200');
    await tester.pump();
    expect(find.byKey(const Key('target-safety-note')), findsNothing);
  });

  testWidgets('the calculator uses the body data already stored — it never '
      'asks for it a second time', (tester) async {
    // The stored provenance has to stay true: once a person edits the number,
    // it is no longer the one the formula produced, and keeping the basis
    // would make the explanation a lie.
    //
    // And the inputs are READ, not asked: this sheet used to render weight,
    // height, age, sex and activity as editable fields, so a weight typed
    // here never reached the weigh-in log and ZIVO ended up holding two.
    final now = DateTime.now();
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    await diet.saveBodyProfile(
      BodyProfile(
        heightCm: 180,
        sex: TargetSex.male,
        activity: ActivityLevel.sedentary,
        updatedAt: now,
      ),
    );
    final weights = InMemoryBodyWeightRepository(
      seed: [
        BodyWeightEntry(id: 'w1', weightKg: 80, loggedAt: now),
      ],
    );
    // Exactly 30 on any day of any year — the BMR below depends on the age.
    final profiles = FakeProfileRepository(
      initial: UserProfile(
        uid: 'fake-uid',
        name: 'Ziad',
        dateOfBirth: DateTime(now.year - 30, 1, 1),
      ),
    );

    await tester.pumpWidget(
      _wrap(
        child: const DietTargetsPage(),
        diet: diet,
        bodyWeight: weights,
        profiles: profiles,
      ),
    );
    await tester.pump();
    await _tap(tester, find.byKey(const Key('goal-fatLoss')));

    await _tap(tester, find.text('Work it out from my body data'));
    await tester.pumpAndSettle();

    // The sheet states what it will use, and offers no way to retype it.
    expect(find.text('80 kg'), findsOneWidget);
    expect(find.text('180 cm'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    // Scoped to the sheet: the target form behind it still has its fields.
    expect(
      find.descendant(
        of: find.byKey(const Key('calculator-scroll')),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );

    await _tap(tester, find.byKey(const Key('run-calculator')),
        list: const Key('calculator-scroll'));
    await tester.pumpAndSettle();

    // BMR 1780 → ×1.2 = 2136 → ×0.8 = 1709.
    expect(find.text('CALCULATED'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('target-calories'))).controller!.text,
      '1709',
    );
    // It shows its working rather than presenting a bare number.
    expect(find.textContaining('2136 kcal to maintain'), findsOneWidget);

    await _tap(tester, find.byKey(const Key('save-targets')));
    expect(diet.currentTargets!.source, TargetSource.calculated);
    expect(diet.currentTargets!.basis!.bmr, 1780);
    // The basis records the STORED body data, so the explanation on screen
    // and the weigh-in log can't drift apart.
    expect(diet.currentTargets!.basis!.weightKg, 80);
    expect(diet.currentTargets!.basis!.heightCm, 180);
  });

  testWidgets('with body data missing, the calculator sends you to the one '
      'screen that collects it instead of growing a second form', (
    tester,
  ) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    // No body profile, no weigh-ins.

    await tester.pumpWidget(
      _wrap(child: const DietTargetsPage(), diet: diet),
    );
    await tester.pump();
    await _tap(tester, find.byKey(const Key('goal-fatLoss')));
    await _tap(tester, find.text('Work it out from my body data'));
    await tester.pumpAndSettle();

    expect(find.byType(BodyProfilePage), findsOneWidget);
    expect(find.byKey(const Key('calculator-scroll')), findsNothing);
  });

  testWidgets('editing a calculated figure by hand drops the calculated claim',
      (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);
    await diet.saveTargets(
      NutritionTargets(
        goal: DietGoal.fatLoss,
        calories: 1709,
        source: TargetSource.calculated,
        basis: const TargetBasis(
          weightKg: 80,
          heightCm: 180,
          age: 30,
          sex: TargetSex.male,
          activity: ActivityLevel.sedentary,
          bmr: 1780,
          maintenanceCalories: 2136,
        ),
        updatedAt: DateTime(2026, 8, 30),
      ),
    );

    await tester.pumpWidget(
      _wrap(
        child: DietTargetsPage(initial: diet.currentTargets),
        diet: diet,
      ),
    );
    await tester.pump();
    expect(find.text('CALCULATED'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('target-calories')), '1900');
    await tester.pump();
    expect(find.text('CALCULATED'), findsNothing);

    await _tap(tester, find.byKey(const Key('save-targets')));
    expect(diet.currentTargets!.calories, 1900);
    expect(diet.currentTargets!.source, TargetSource.manual);
    expect(diet.currentTargets!.basis, isNull);
  });

  testWidgets('an existing target can be removed, back to the honest unset '
      'state', (tester) async {
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
        child: DietTargetsPage(initial: diet.currentTargets),
        diet: diet,
      ),
    );
    await tester.pump();

    await _tap(tester, find.byKey(const Key('remove-targets')));
    expect(diet.currentTargets, isNull);
  });
}
