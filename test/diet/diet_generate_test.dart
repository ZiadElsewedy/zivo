import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_goal.dart';
import 'package:zivo/features/diet/domain/diet_import_outcome.dart';
import 'package:zivo/features/diet/domain/diet_import_result.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/domain/plan_preferences.dart';
import 'package:zivo/features/diet/presentation/pages/diet_import_page.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plan_edit_page.dart';
import 'package:zivo/features/diet/presentation/pages/diet_preferences_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _wrap({
  required Widget child,
  required InMemoryDietRepository diet,
  FakeAiRepository? ai,
}) => AppScope(
  auth: FakeAuthRepository(),
  profiles: FakeProfileRepository(),
  expenses: InMemoryExpenseRepository(),
  moments: InMemoryMomentRepository(),
  workouts: InMemoryWorkoutRepository(),
  workoutPlans: InMemoryWorkoutPlanRepository(),
  workoutSessions: InMemoryWorkoutSessionRepository(),
  diet: diet,
  ai: ai ?? FakeAiRepository(),
  child: MaterialApp(home: child),
);

const _generated = DietImportResult(
  planName: 'Lean bulk, 4 meals',
  days: [
    ImportedDietDay(
      weekday: null,
      label: 'Every day',
      meals: [
        ImportedMeal(
          label: 'Breakfast',
          items: [
            ImportedFoodItem(
              name: 'Oats, whole grain, rolled',
              quantity: 80,
              unit: 'g',
              calories: 303,
              proteinG: 10.6,
              carbsG: 54.4,
              fatG: 5.4,
              estimated: false,
            ),
          ],
        ),
      ],
    ),
  ],
);

NutritionTargets _targets({int calories = 2400}) => NutritionTargets(
  goal: DietGoal.muscleGain,
  calories: calories,
  proteinG: 170,
  source: TargetSource.manual,
  updatedAt: DateTime(2026, 8, 30),
);

void main() {
  group('PlanPreferences', () {
    test('a food list is parsed the way people write one', () {
      expect(parseFoodList('chicken, rice ,eggs'), ['chicken', 'rice', 'eggs']);
      // Blank entries and repeats are noise, not data.
      expect(parseFoodList('rice,,rice , RICE'), ['rice']);
      expect(parseFoodList('   '), isEmpty);
      // Newlines count as separators — people paste lists.
      expect(parseFoodList('eggs\nmilk'), ['eggs', 'milk']);
    });

    test('the payload sends empty lists rather than omitting them', () {
      const prefs = PlanPreferences(mealsPerDay: 3);
      final payload = prefs.toPayload();

      expect(payload['mealsPerDay'], 3);
      expect(payload['allergies'], isEmpty);
      // Absent optionals are omitted, so the server can tell "not given" from
      // "given as blank".
      expect(payload.containsKey('cuisine'), isFalse);
      expect(payload.containsKey('notes'), isFalse);
    });

    test('a meal count outside what a plan can be is not usable', () {
      expect(const PlanPreferences(mealsPerDay: 3).isUsable, isTrue);
      expect(const PlanPreferences(mealsPerDay: 1).isUsable, isFalse);
      expect(const PlanPreferences(mealsPerDay: 20).isUsable, isFalse);
    });
  });

  group('the preferences screen', () {
    testWidgets('collects what only the user knows, and sends it', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      await diet.saveTargets(_targets());
      PlanPreferences? sent;
      NutritionTargets? sentTargets;
      final ai = FakeAiRepository(
        generateDietPlanImpl: (preferences, targets) async {
          sent = preferences;
          sentTargets = targets;
          return const DietImportAccepted(_generated);
        },
      );

      await tester.pumpWidget(
        _wrap(child: const DietPreferencesPage(), diet: diet, ai: ai),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('meals-4')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cuisine-egyptian')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('prefs-likes')),
        'chicken, rice',
      );
      await tester.enterText(find.byKey(const Key('prefs-avoid')), 'liver');
      await tester.enterText(
        find.byKey(const Key('prefs-allergies')),
        'peanuts',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('prefs-build')));
      await tester.pumpAndSettle();

      expect(sent!.mealsPerDay, 4);
      expect(sent!.cuisine, 'Egyptian');
      expect(sent!.likes, ['chicken', 'rice']);
      expect(sent!.avoid, ['liver']);
      expect(sent!.allergies, ['peanuts']);
      // The plan is sized to the target the user has already approved.
      expect(sentTargets!.calories, 2400);
    });

    testWidgets('says up front when there is no target to size the plan to', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);

      await tester.pumpWidget(
        _wrap(child: const DietPreferencesPage(), diet: diet),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('prefs-no-target')), findsOneWidget);
      expect(find.byKey(const Key('prefs-target-note')), findsNothing);
    });

    testWidgets('with a target set, it says what the plan is sized to', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      await diet.saveTargets(_targets(calories: 1900));

      await tester.pumpWidget(
        _wrap(child: const DietPreferencesPage(), diet: diet),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('prefs-target-note'))).data,
        'Sized to your target — 1900 kcal a day.',
      );
    });

    testWidgets('a plan is still buildable without a target', (tester) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      var called = false;
      final ai = FakeAiRepository(
        generateDietPlanImpl: (preferences, targets) async {
          called = true;
          expect(targets, isNull);
          return const DietImportAccepted(_generated);
        },
      );

      await tester.pumpWidget(
        _wrap(child: const DietPreferencesPage(), diet: diet, ai: ai),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prefs-build')));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });
  });

  group('a generated plan', () {
    testWidgets('lands in the same review editor an import does', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final ai = FakeAiRepository(
        generateDietPlanImpl: (_, _) async =>
            const DietImportAccepted(_generated),
      );

      await tester.pumpWidget(
        _wrap(
          child: const DietImportPage(
            generateFrom: PlanPreferences(mealsPerDay: 3),
          ),
          diet: diet,
          ai: ai,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DietPlanEditPage), findsOneWidget);
      // Nothing was saved on the way — the editor is the gate.
      expect(diet.plans.where((p) => p.name == 'Lean bulk, 4 meals'), isEmpty);
    });

    testWidgets('records that ZIVO built it', (tester) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final ai = FakeAiRepository(
        generateDietPlanImpl: (_, _) async =>
            const DietImportAccepted(_generated),
      );

      await tester.pumpWidget(
        _wrap(
          child: const DietImportPage(
            generateFrom: PlanPreferences(mealsPerDay: 3),
          ),
          diet: diet,
          ai: ai,
        ),
      );
      await tester.pumpAndSettle();

      final editor = tester.widget<DietPlanEditPage>(
        find.byType(DietPlanEditPage),
      );
      expect(editor.initialPlan!.source, DietSource.generated);
      expect(dietSourceLabel(DietSource.generated), 'Built by ZIVO');
    });

    testWidgets('a refusal is explained in generation\'s own words', (
      tester,
    ) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final ai = FakeAiRepository(
        generateDietPlanImpl: (_, _) async => const DietImportRejected(
          'Everything you eat is on your avoid list.',
        ),
      );

      await tester.pumpWidget(
        _wrap(
          child: const DietImportPage(
            generateFrom: PlanPreferences(mealsPerDay: 3),
          ),
          diet: diet,
          ai: ai,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("ZIVO couldn't build that plan"), findsOneWidget);
      expect(
        find.text('Everything you eat is on your avoid list.'),
        findsOneWidget,
      );
      // Generation is not deterministic, so a second run is a real attempt.
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('the generator never touches the file picker', (tester) async {
      _tallViewport(tester);
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      var picked = false;
      final ai = FakeAiRepository(
        generateDietPlanImpl: (_, _) async =>
            const DietImportAccepted(_generated),
      );

      await tester.pumpWidget(
        _wrap(
          child: DietImportPage(
            generateFrom: const PlanPreferences(mealsPerDay: 3),
            pickFile: () async {
              picked = true;
              return null;
            },
          ),
          diet: diet,
          ai: ai,
        ),
      );
      await tester.pumpAndSettle();

      expect(picked, isFalse);
    });
  });
}
