import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_goal.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/meal.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';
import 'package:zivo/features/diet/domain/target_calculator.dart';
import 'package:zivo/features/diet/domain/diet_state.dart';
import 'package:zivo/features/diet/domain/diet_state_builder.dart';

NutritionTargets _targets({
  DietGoal goal = DietGoal.fatLoss,
  int calories = 2200,
  double? proteinG = 160,
  double? carbsG = 250,
  double? fatG = 73,
  TargetSource source = TargetSource.manual,
}) => NutritionTargets(
  goal: goal,
  calories: calories,
  proteinG: proteinG,
  carbsG: carbsG,
  fatG: fatG,
  source: source,
  updatedAt: DateTime(2026, 8, 30),
);

DietDay _day() => const DietDay(
  label: 'Every day',
  meals: [
    Meal(
      id: 'm1',
      label: 'Breakfast',
      order: 0,
      items: [
        FoodItem(
          name: 'Oats',
          quantity: 60,
          unit: 'g',
          calories: 400,
          proteinG: 20,
          carbsG: 60,
          fatG: 10,
        ),
      ],
    ),
    Meal(
      id: 'm2',
      label: 'Lunch',
      order: 1,
      items: [
        FoodItem(
          name: 'Chicken',
          quantity: 200,
          unit: 'g',
          calories: 500,
          proteinG: 60,
          carbsG: 0,
          fatG: 12,
        ),
      ],
    ),
    Meal(
      id: 'supps',
      label: 'Supplements',
      order: 2,
      items: [
        FoodItem(name: 'Creatine', quantity: 5, unit: 'g', calories: 20),
      ],
    ),
  ],
);

void main() {
  group('goal + target parsing', () {
    test('an unknown or missing goal parses to null, never a default', () {
      // A goal the app picked would be exactly as untrue as a calorie figure
      // it invented — "unset" has to survive a round-trip.
      expect(dietGoalFromName(null), isNull);
      expect(dietGoalFromName('shredded'), isNull);
      expect(dietGoalFromName('fatLoss'), DietGoal.fatLoss);
    });

    test('an unknown source reads as manual — "a person put this here"', () {
      expect(targetSourceFromName(null), TargetSource.manual);
      expect(targetSourceFromName('vibes'), TargetSource.manual);
      expect(targetSourceFromName('calculated'), TargetSource.calculated);
    });

    test('the safety floor is a fixed number, not a model opinion', () {
      expect(targetIsBelowSafetyFloor(kMinimumSafeCalories - 1), isTrue);
      expect(targetIsBelowSafetyFloor(kMinimumSafeCalories), isFalse);
      expect(targetIsBelowSafetyFloor(2200), isFalse);
    });
  });

  group('calculateTargets', () {
    test('Mifflin-St Jeor, both forms, to the published values', () {
      // 10·80 + 6.25·180 − 5·30 + 5 = 1780
      expect(
        basalMetabolicRate(
          weightKg: 80,
          heightCm: 180,
          age: 30,
          sex: TargetSex.male,
        ),
        1780,
      );
      // 10·65 + 6.25·165 − 5·30 − 161 = 1370.25 → 1370
      expect(
        basalMetabolicRate(
          weightKg: 65,
          heightCm: 165,
          age: 30,
          sex: TargetSex.female,
        ),
        1370,
      );
    });

    test('is deterministic: the same inputs always give the same target', () {
      TargetProposal run() => calculateTargets(
        weightKg: 82,
        heightCm: 178,
        age: 27,
        sex: TargetSex.male,
        activity: ActivityLevel.moderate,
        goal: DietGoal.fatLoss,
        now: DateTime(2026, 8, 30),
      );
      final a = run();
      final b = run();
      expect(a.targets.calories, b.targets.calories);
      expect(a.targets.proteinG, b.targets.proteinG);
      expect(a.targets.carbsG, b.targets.carbsG);
      expect(a.targets.fatG, b.targets.fatG);
    });

    test('shows its working: every figure traces back through the basis', () {
      final proposal = calculateTargets(
        weightKg: 80,
        heightCm: 180,
        age: 30,
        sex: TargetSex.male,
        activity: ActivityLevel.sedentary,
        goal: DietGoal.fatLoss,
        now: DateTime(2026, 8, 30),
      );

      expect(proposal.basis.bmr, 1780);
      // 1780 × 1.2 = 2136
      expect(proposal.basis.maintenanceCalories, 2136);
      // 2136 × 0.80 = 1708.8 → 1709
      expect(proposal.targets.calories, 1709);
      expect(proposal.targets.source, TargetSource.calculated);
      expect(proposal.targets.basis, isNotNull);
      // 2.2 g/kg for fat loss.
      expect(proposal.targets.proteinG, 176);
    });

    test('the macros add back up to the calorie figure', () {
      // If they didn't, the app would be showing a target that contradicts
      // itself — four numbers that can't all be true at once.
      final p = calculateTargets(
        weightKg: 75,
        heightCm: 175,
        age: 32,
        sex: TargetSex.female,
        activity: ActivityLevel.moderate,
        goal: DietGoal.maintain,
        now: DateTime(2026, 8, 30),
      ).targets;

      final fromMacros = p.proteinG! * kcalPerGramProtein +
          p.carbsG! * kcalPerGramCarb +
          p.fatG! * kcalPerGramFat;
      expect((fromMacros - p.calories).abs(), lessThan(6));
    });

    test('flags a proposal that lands under the safety floor', () {
      // A small, sedentary person on an aggressive deficit can compute below
      // the floor. It is reported, not silently clamped — clamping would hide
      // that the inputs and the goal do not add up to something ZIVO should
      // be coaching.
      final proposal = calculateTargets(
        weightKg: 45,
        heightCm: 150,
        age: 60,
        sex: TargetSex.female,
        activity: ActivityLevel.sedentary,
        goal: DietGoal.fatLoss,
        now: DateTime(2026, 8, 30),
      );
      expect(proposal.belowSafetyFloor, isTrue);
      expect(proposal.targets.calories, lessThan(kMinimumSafeCalories));
    });

    test('never proposes negative carbs', () {
      final p = calculateTargets(
        weightKg: 120,
        heightCm: 165,
        age: 65,
        sex: TargetSex.female,
        activity: ActivityLevel.sedentary,
        goal: DietGoal.fatLoss,
        now: DateTime(2026, 8, 30),
      ).targets;
      expect(p.carbsG, greaterThanOrEqualTo(0));
    });

    test('ageFrom counts whole years, before and after the birthday', () {
      final dob = DateTime(1998, 6, 15);
      expect(ageFrom(dob, DateTime(2026, 6, 14)), 27);
      expect(ageFrom(dob, DateTime(2026, 6, 15)), 28);
      expect(ageFrom(dob, DateTime(2026, 8, 30)), 28);
    });
  });

  group('buildTargetProgress', () {
    test('measures the target against what was ticked, ignoring supplements',
        () {
      final progress = buildDietState(
        dayKey: '2026-08-30',
        weekday: 7,
        planName: null,
        targets: _targets(),
        day: _day(),
        consumedMealIds: {'m1', 'supps'},
        log: const [],
      );

      // Breakfast counts (400); the supplement's 20 kcal never does.
      expect(progress.consumed.kcal, 400);
      expect(progress.remainingKcal, 1800);
      expect(progress.overTarget, isFalse);
      expect(progress.mealsEaten, 1);
      expect(progress.mealsTotal, 2);
      expect(progress.protein.consumed, 20);
      expect(progress.protein.remaining, 140);
    });

    test('goes over rather than clamping — "over" is a state a coach names',
        () {
      final progress = buildDietState(
        dayKey: '2026-08-30',
        weekday: 7,
        planName: null,
        targets: _targets(calories: 700),
        day: _day(),
        consumedMealIds: {'m1', 'm2'},
        log: const [],
      );
      expect(progress.consumed.kcal, 900);
      expect(progress.remainingKcal, -200);
      expect(progress.overTarget, isTrue);
      expect(progress.calorieFraction, greaterThan(1));
    });

    test('a macro with no target has no remaining — never zero', () {
      // "You didn't set a carb target" and "you have 0g left" are opposite
      // statements.
      final progress = buildDietState(
        dayKey: '2026-08-30',
        weekday: 7,
        planName: null,
        targets: _targets(carbsG: null, fatG: null),
        day: _day(),
        consumedMealIds: {'m1'},
        log: const [],
      );
      expect(progress.carbs.target, isNull);
      expect(progress.carbs.remaining, isNull);
      expect(progress.carbs.fraction, isNull);
      // Consumed is still a real running total.
      expect(progress.carbs.consumed, 60);
    });

    test('carries the estimate flag from whatever was ticked', () {
      const estimatedDay = DietDay(
        label: 'Every day',
        meals: [
          Meal(
            id: 'm1',
            label: 'Lunch',
            order: 0,
            items: [
              FoodItem(
                name: 'Rice',
                quantity: 100,
                unit: 'g',
                calories: 300,
                proteinG: 6,
                estimated: true,
              ),
            ],
          ),
        ],
      );

      expect(
        buildDietState(
          dayKey: '2026-08-30',
          weekday: 7,
          planName: null,
          targets: _targets(),
          day: estimatedDay,
          consumedMealIds: const <String>{},
        log: const [],
        ).consumed.estimated,
        isFalse,
        reason: 'nothing ticked yet, so nothing estimated has been counted',
      );
      expect(
        buildDietState(
          dayKey: '2026-08-30',
          weekday: 7,
          planName: null,
          targets: _targets(),
          day: estimatedDay,
          consumedMealIds: {'m1'},
          log: const [],
        ).consumed.estimated,
        isTrue,
      );
    });

    test('a day with no plan still reports the target honestly', () {
      final progress = buildDietState(
        dayKey: '2026-08-30',
        weekday: 7,
        planName: null,
        targets: _targets(),
        day: null,
        consumedMealIds: const <String>{},
        log: const [],
      );
      expect(progress.consumed.kcal, 0);
      expect(progress.remainingKcal, 2200);
      expect(progress.mealsTotal, 0);
    });

    test('consumed is still sourced from ticked meals, and says so', () {
      // The honest caveat until a real food log exists (Phase 3).
      final progress = buildDietState(
        dayKey: '2026-08-30',
        weekday: 7,
        planName: null,
        targets: _targets(),
        day: _day(),
        consumedMealIds: {'m1'},
        log: const [],
      );
      expect(progress.consumed.basis, ConsumedBasis.tickedPlanMeals);
    });
  });

  group('repository', () {
    test('starts with NO targets — the demo plan never implies a goal', () async {
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      expect(diet.currentTargets, isNull);
      expect(await diet.watchTargets().first, isNull);
    });

    test('saving and clearing targets round-trips through the stream', () async {
      final diet = InMemoryDietRepository();
      addTearDown(diet.dispose);
      final seen = <NutritionTargets?>[];
      final sub = diet.watchTargets().listen(seen.add);
      // Let the stream deliver its initial value and reach the broadcast
      // controller before writing — it's a broadcast stream, so an event
      // published before then would simply have no listener.
      await Future<void>.delayed(Duration.zero);

      await diet.saveTargets(_targets(goal: DietGoal.muscleGain));
      await Future<void>.delayed(Duration.zero);
      expect(diet.currentTargets?.goal, DietGoal.muscleGain);
      expect(diet.currentTargets?.calories, 2200);

      await diet.clearTargets();
      await Future<void>.delayed(Duration.zero);
      expect(diet.currentTargets, isNull);

      await sub.cancel();
      expect(seen.first, isNull);
      expect(seen.last, isNull);
      expect(seen.any((t) => t?.goal == DietGoal.muscleGain), isTrue);
    });
  });
}
