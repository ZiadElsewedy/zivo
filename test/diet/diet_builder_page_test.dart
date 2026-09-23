import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/presentation/pages/diet_builder_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

Widget _wrap(InMemoryDietRepository diet) {
  return AppScope(
    auth: FakeAuthRepository(
      initial: const Authenticated(AuthUser(uid: 'fake-uid')),
    ),
    profiles: FakeProfileRepository(),
    bodyWeight: InMemoryBodyWeightRepository(),
    expenses: InMemoryExpenseRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: InMemoryWorkoutSessionRepository(),
    diet: diet,
    ai: FakeAiRepository(),
    child: const MaterialApp(home: DietBuilderPage()),
  );
}

/// Fills in Goal and About-you, then advances through the optional steps to the
/// Build button — the shared setup for the tests below.
Future<void> _fillToBuild(WidgetTester tester) async {
  // Step 1: goal.
  expect(find.byKey(const Key('builder-build')), findsNothing);
  await tester.tap(find.byKey(const Key('builder-goal-maintain')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('builder-next')));
  await tester.pumpAndSettle();

  // Step 2: about you.
  await tester.enterText(find.byKey(const Key('builder-weight')), '81');
  await tester.enterText(find.byKey(const Key('builder-height')), '178');
  await tester.enterText(find.byKey(const Key('builder-age')), '30');
  await tester.tap(find.byKey(const Key('builder-sex-male')));
  await tester.tap(find.byKey(const Key('builder-activity-moderate')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('builder-next')));
  await tester.pumpAndSettle();

  // Step 3 (how you eat) and step 4 (avoid): optional, just continue.
  await tester.tap(find.byKey(const Key('builder-next')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('builder-next')));
  await tester.pumpAndSettle();
}

/// The "How you eat" step's own scroll view — the PageView keeps every step's
/// list alive, so a bare `scrollUntilVisible` finds several.
Finder _eatStepScrollable() => find
    .descendant(
      of: find.byKey(const Key('builder-eat')),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  testWidgets('gates Continue on goal, then on complete body data', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(InMemoryDietRepository()));
    await tester.pumpAndSettle();

    // No goal yet → Continue is disabled (a disabled PillButton has 0.45
    // opacity and no onTap, so tapping is a no-op and we stay on step 1).
    await tester.tap(find.byKey(const Key('builder-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('builder-goal')), findsOneWidget);

    await tester.tap(find.byKey(const Key('builder-goal-maintain')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('builder-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('builder-about')), findsOneWidget);

    // Body incomplete → can't advance past About you.
    await tester.tap(find.byKey(const Key('builder-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('builder-about')), findsOneWidget);
  });

  testWidgets('builds a plan and, on Save, persists target + active plan', (
    tester,
  ) async {
    final diet = InMemoryDietRepository();
    await tester.pumpWidget(_wrap(diet));
    await tester.pumpAndSettle();

    await _fillToBuild(tester);

    // Step 5: Build.
    expect(find.byKey(const Key('builder-build')), findsOneWidget);
    await tester.tap(find.byKey(const Key('builder-build')));
    await tester.pumpAndSettle();

    // The fake generator returns a plan → we land on the reveal.
    expect(find.byKey(const Key('reveal-list')), findsOneWidget);
    expect(find.byKey(const Key('reveal-target-kcal')), findsOneWidget);

    // Nothing saved before Save.
    expect(diet.currentTargets, isNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('reveal-save')),
      200,
    );
    await tester.tap(find.byKey(const Key('reveal-save')));
    await tester.pumpAndSettle();

    // Target and an active plan are now persisted.
    expect(diet.currentTargets, isNotNull);
    expect(diet.activePlan, isNotNull);
  });

  testWidgets('the country is picked from a list, remembered, and prefilled '
      'on the next build', (tester) async {
    final diet = InMemoryDietRepository();
    await tester.pumpWidget(_wrap(diet));
    await tester.pumpAndSettle();

    // Through goal + about-you to "How you eat".
    await tester.tap(find.byKey(const Key('builder-goal-maintain')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('builder-next')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('builder-weight')), '81');
    await tester.enterText(find.byKey(const Key('builder-height')), '178');
    await tester.enterText(find.byKey(const Key('builder-age')), '30');
    await tester.tap(find.byKey(const Key('builder-sex-male')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('builder-next')));
    await tester.pumpAndSettle();

    // No free-text box — a picker.
    await tester.scrollUntilVisible(
      find.byKey(const Key('builder-country-field')),
      200,
      scrollable: _eatStepScrollable(),
    );
    await tester.tap(find.byKey(const Key('builder-country-field')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('country-search')), 'egy');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('country-EG')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('builder-country-value'))).data,
      'Egypt',
    );
    expect(await diet.fetchHomeCountry(), 'EG');

    // A fresh builder remembers it — no re-entering.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_wrap(diet));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('builder-goal-maintain')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('builder-next')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('builder-weight')), '81');
    await tester.enterText(find.byKey(const Key('builder-height')), '178');
    await tester.enterText(find.byKey(const Key('builder-age')), '30');
    await tester.tap(find.byKey(const Key('builder-sex-male')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('builder-next')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('builder-country-value')),
      200,
      scrollable: _eatStepScrollable(),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('builder-country-value'))).data,
      'Egypt',
    );
  });
}
