import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/nutrition/food_reference.dart';
import 'package:zivo/features/diet/domain/nutrition/food_resolver.dart';
import 'package:zivo/features/diet/domain/nutrition/resolved_food.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plan_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A tiny stand-in catalog, so these tests exercise the sheet rather than the
/// real 1 MB asset (which `food_resolver_test.dart` covers directly).
class _StubCatalog implements FoodResolver {
  _StubCatalog(this.foods);

  final List<FoodReference> foods;

  List<FoodReference> _matches(String query) {
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length > 1);
    return foods
        .where((f) => tokens.every((t) => f.name.toLowerCase().contains(t)))
        .toList();
  }

  @override
  Future<FoodReference?> byId(String id) async =>
      foods.where((f) => f.id == id).firstOrNull;

  @override
  Future<List<FoodReference>> search(String query, {int limit = 20}) async =>
      _matches(query).take(limit).toList();

  @override
  Future<FoodMatch> resolve(String query, {FoodPreparation? preparation}) async {
    final matches = _matches(query);
    if (matches.isEmpty) return FoodNotFound(query: query);
    return FoodResolved(food: matches.first, alternatives: matches.skip(1).toList());
  }
}

const _chicken = FoodReference(
  id: 'usda:171477',
  name: 'Chicken, breast, cooked, roasted',
  preparation: FoodPreparation.cooked,
  kcalPer100g: 165,
  proteinPer100g: 31,
  carbsPer100g: 0,
  fatPer100g: 3.6,
  source: NutritionSource.usdaFdc,
  sourceRef: '171477',
  portions: [FoodPortion(label: 'cup', grams: 140)],
);

Widget _wrap({
  required InMemoryDietRepository diet,
  required FoodResolver foods,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: InMemoryWorkoutSessionRepository(),
    diet: diet,
    foods: foods,
    ai: FakeAiRepository(),
    child: const MaterialApp(home: DietPlanPage()),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  // The Diet page is a lazy ListView and the log section sits below the meals,
  // so the button isn't merely off-screen — it hasn't been built yet.
  await tester.scrollUntilVisible(
    find.byKey(const Key('log-food-button')),
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('log-food-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('search, pick, measure, log — the figure is computed from the '
      'catalog, never estimated', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(
      _wrap(diet: diet, foods: _StubCatalog(const [_chicken])),
    );
    await _openSheet(tester);

    await tester.enterText(find.byKey(const Key('food-search')), 'chicken');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chicken, breast, cooked, roasted'));
    await tester.pumpAndSettle();

    // 100g of a 165 kcal/100g food. Exact, not "about".
    expect(find.text('165 kcal'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('log-quantity')), '200');
    await tester.pumpAndSettle();
    expect(find.text('330 kcal'), findsOneWidget);
    expect(find.textContaining('P 62.0g'), findsOneWidget);

    await tester.tap(find.byKey(const Key('log-food-confirm')));
    await tester.pumpAndSettle();

    final log = await diet.watchFoodLog(DateTime.now()).first;
    expect(log.length, 1);
    expect(log.single.kcal, 330);
    expect(log.single.foodId, 'usda:171477');
    expect(log.single.sourceRef, '171477');
    expect(log.single.source, NutritionSource.usdaFdc);
  });

  testWidgets('a unit the source never measured is refused, with the ones that '
      'would work', (tester) async {
    // Converting ml to grams would mean assuming a density. The sheet says so
    // rather than quietly producing a number.
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(
      _wrap(diet: diet, foods: _StubCatalog(const [_chicken])),
    );
    await _openSheet(tester);
    await tester.enterText(find.byKey(const Key('food-search')), 'chicken');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chicken, breast, cooked, roasted'));
    await tester.pumpAndSettle();

    // Only the measures this food actually has are offered.
    expect(find.byKey(const Key('unit-g')), findsOneWidget);
    expect(find.byKey(const Key('unit-cup')), findsOneWidget);
    expect(find.byKey(const Key('unit-ml')), findsNothing);

    // And the one it does have computes exactly: 1 cup = 140g.
    await tester.tap(find.byKey(const Key('unit-cup')));
    await tester.enterText(find.byKey(const Key('log-quantity')), '1');
    await tester.pumpAndSettle();
    expect(find.text('231 kcal'), findsOneWidget);
  });

  testWidgets('a food the catalog does not have offers to define it, and never '
      'approximates', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(
      _wrap(diet: diet, foods: _StubCatalog(const [_chicken])),
    );
    await _openSheet(tester);

    await tester.enterText(find.byKey(const Key('food-search')), 'koshari');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing in the catalog matches'), findsOneWidget);
    expect(find.byKey(const Key('define-custom-food')), findsOneWidget);
    // No number is offered anywhere on this state.
    expect(find.byKey(const Key('log-preview')), findsNothing);

    await tester.tap(find.byKey(const Key('define-custom-food')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('custom-kcal')), '150');
    await tester.enterText(find.byKey(const Key('custom-protein')), '5');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-custom-food')));
    await tester.pumpAndSettle();

    // Saved as the user's own, and immediately usable.
    final saved = await diet.listCustomFoods();
    expect(saved.single.name, 'koshari');
    expect(saved.single.kcalPer100g, 150);

    await tester.enterText(find.byKey(const Key('log-quantity')), '300');
    await tester.pumpAndSettle();
    expect(find.text('450 kcal'), findsOneWidget);
    expect(find.textContaining('Your own food'), findsWidgets);
  });

  testWidgets('a logged entry appears on the Diet screen with its provenance, '
      'and can be removed', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(
      _wrap(diet: diet, foods: _StubCatalog(const [_chicken])),
    );
    await _openSheet(tester);
    await tester.enterText(find.byKey(const Key('food-search')), 'chicken');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chicken, breast, cooked, roasted'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('log-food-confirm')));
    await tester.pumpAndSettle();

    final entry = (await diet.watchFoodLog(DateTime.now()).first).single;
    await tester.ensureVisible(find.byKey(Key('log-entry-${entry.id}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('USDA FoodData Central'), findsOneWidget);

    await tester.tap(find.byKey(Key('remove-log-${entry.id}')));
    await tester.pumpAndSettle();
    expect(await diet.watchFoodLog(DateTime.now()).first, isEmpty);
  });
}
