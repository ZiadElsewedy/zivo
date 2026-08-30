import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/diet/domain/analysis/plan_verdict.dart';
import 'package:zivo/features/diet/domain/body_measures.dart';
import 'package:zivo/features/diet/domain/body_profile.dart';
import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_plan_status.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/meal.dart';
import 'package:zivo/features/diet/domain/nutrition_targets.dart';

final _now = DateTime(2026, 8, 31);

/// 82kg, 178cm, 30, male, moderate → BMR 1788, maintenance 2771. Pinned here
/// because every expectation below is measured against it.
BodyMeasures _measures({
  double weightKg = 82,
  ActivityLevel activity = ActivityLevel.moderate,
  int? stated,
  DateTime? weighedAt,
}) => BodyMeasures(
  weightKg: weightKg,
  weighedAt: weighedAt ?? _now,
  heightCm: 178,
  age: 30,
  sex: TargetSex.male,
  activity: activity,
  statedMaintenanceKcal: stated,
);

/// One day whose meals total [kcal], split over two meals, with [proteinG]
/// spread across them. [supplementKcal] rides in a Supplements block, which
/// must never count toward the day's energy.
DietDay _day({
  required int kcal,
  double? proteinG,
  bool estimated = false,
  int? supplementKcal,
  String label = 'Every day',
}) => DietDay(
  label: label,
  meals: [
    Meal(
      id: 'm1',
      label: 'Breakfast',
      order: 0,
      items: [
        FoodItem(
          name: 'Oats',
          quantity: 100,
          unit: 'g',
          calories: kcal ~/ 2,
          proteinG: proteinG == null ? null : proteinG / 2,
          estimated: estimated,
        ),
      ],
    ),
    Meal(
      id: 'm2',
      label: 'Dinner',
      order: 1,
      items: [
        FoodItem(
          name: 'Chicken and rice',
          quantity: 300,
          unit: 'g',
          calories: kcal - kcal ~/ 2,
          proteinG: proteinG == null ? null : proteinG / 2,
          estimated: estimated,
        ),
      ],
    ),
    if (supplementKcal != null)
      Meal(
        id: 'm3',
        label: 'Supplements',
        order: 2,
        items: [
          FoodItem(
            name: 'Mass gainer',
            quantity: 1,
            unit: 'scoop',
            calories: supplementKcal,
          ),
        ],
      ),
  ],
);

DietPlan _plan(List<DietDay> days) => DietPlan(
  id: 'p1',
  name: 'Plan',
  status: DietPlanStatus.active,
  source: DietSource.pdf,
  createdAt: _now,
  updatedAt: _now,
  days: days,
);

void main() {
  group('analysePlan', () {
    test('a plan well above maintenance reads as gaining, with the maths', () {
      final measures = _measures();
      expect(measures.maintenanceKcal, 2771);

      final verdict = analysePlan(
        plan: _plan([_day(kcal: 3356)]),
        measures: measures,
      )!;

      expect(verdict.planKcalPerDay, 3356);
      expect(verdict.maintenanceKcal, 2771);
      expect(verdict.deltaKcal, 585);
      expect(verdict.direction, EnergyDirection.gaining);
      // 585 × 7 / 7700 ≈ 0.53 kg a week.
      expect(verdict.projectedKgPerWeek, closeTo(0.53, 0.01));
      expect(verdictHeadline(verdict), 'Gaining ~0.53 kg a week');
    });

    test('a plan below maintenance reads as losing, and the kg is signed', () {
      final verdict = analysePlan(
        plan: _plan([_day(kcal: 2000)]),
        measures: _measures(),
      )!;

      expect(verdict.direction, EnergyDirection.losing);
      expect(verdict.deltaKcal, -771);
      expect(verdict.projectedKgPerWeek, lessThan(0));
      expect(verdictHeadline(verdict), 'Losing ~0.7 kg a week');
    });

    test('inside the deadband it holds — the equation is not that precise', () {
      // +99 kcal: a real number, but far inside the error of a population BMR
      // estimate. Calling it "gaining 0.09 kg a week" would be a false claim
      // of precision.
      final verdict = analysePlan(
        plan: _plan([_day(kcal: 2771 + 99)]),
        measures: _measures(),
      )!;

      expect(verdict.direction, EnergyDirection.holding);
      expect(verdict.deltaKcal, 99);
      expect(verdictHeadline(verdict), 'Holds your weight steady');
      // The figure is still reported — the caller decides whether to print it.
      expect(verdict.projectedKgPerWeek, greaterThan(0));
    });

    test('one kcal outside the deadband tips it', () {
      final verdict = analysePlan(
        plan: _plan([_day(kcal: 2771 + 100)]),
        measures: _measures(),
      )!;
      expect(verdict.direction, EnergyDirection.gaining);
    });

    test('a stated maintenance figure replaces the estimate, and says so', () {
      final verdict = analysePlan(
        plan: _plan([_day(kcal: 3000)]),
        measures: _measures(stated: 3100),
      )!;

      expect(verdict.maintenanceKcal, 3100);
      expect(verdict.maintenanceSource, MaintenanceSource.stated);
      expect(verdict.direction, EnergyDirection.losing);
      expect(verdictDetail(verdict), contains('maintenance figure you gave'));
    });

    test('supplements are not energy', () {
      final withSupplements = analysePlan(
        plan: _plan([_day(kcal: 3000, supplementKcal: 400)]),
        measures: _measures(),
      )!;
      expect(withSupplements.planKcalPerDay, 3000);
    });

    test('days average, and days with no calories are counted separately', () {
      final verdict = analysePlan(
        plan: _plan([
          _day(kcal: 3000, label: 'Training day'),
          _day(kcal: 2000, label: 'Rest day'),
          const DietDay(label: 'Free day', meals: []),
        ]),
        measures: _measures(),
      )!;

      expect(verdict.planKcalPerDay, 2500);
      expect(verdict.daysCounted, 2);
      expect(verdict.daysWithoutCalories, 1);
    });

    test('a plan with no calorie figures anywhere has no verdict', () {
      expect(
        analysePlan(
          plan: _plan([const DietDay(label: 'Every day', meals: [])]),
          measures: _measures(),
        ),
        isNull,
      );
    });

    test('the verdict inherits the plan\'s estimated flag', () {
      final estimated = analysePlan(
        plan: _plan([_day(kcal: 3356, estimated: true)]),
        measures: _measures(),
      )!;
      expect(estimated.estimated, isTrue);
      expect(verdictDetail(estimated), startsWith('~3356 kcal a day'));

      final measured = analysePlan(
        plan: _plan([_day(kcal: 3356)]),
        measures: _measures(),
      )!;
      expect(measured.estimated, isFalse);
      expect(verdictDetail(measured), startsWith('3356 kcal a day'));
    });

    test('protein is reported per kg, and absent stays absent', () {
      final withProtein = analysePlan(
        plan: _plan([_day(kcal: 3000, proteinG: 164)]),
        measures: _measures(),
      )!;
      expect(withProtein.proteinGPerKg, closeTo(2.0, 0.001));

      final without = analysePlan(
        plan: _plan([_day(kcal: 3000)]),
        measures: _measures(),
      )!;
      // Not 0.0 — the plan never claimed zero protein, it just doesn't say.
      expect(without.proteinGPerKg, isNull);
    });

    test('a plan under the safety floor is flagged, never clamped', () {
      final verdict = analysePlan(
        plan: _plan([_day(kcal: 1100)]),
        measures: _measures(),
      )!;
      expect(verdict.belowSafetyFloor, isTrue);
      expect(verdict.planKcalPerDay, 1100);
    });

    test('activity level moves maintenance, and so the verdict', () {
      final plan = _plan([_day(kcal: 2900)]);
      expect(
        analysePlan(
          plan: plan,
          measures: _measures(activity: ActivityLevel.sedentary),
        )!.direction,
        EnergyDirection.gaining,
      );
      expect(
        analysePlan(
          plan: plan,
          measures: _measures(activity: ActivityLevel.athlete),
        )!.direction,
        EnergyDirection.losing,
      );
    });

    test('agreesWith compares the plan to a goal without owning one', () {
      final gaining = analysePlan(
        plan: _plan([_day(kcal: 3356)]),
        measures: _measures(),
      )!;
      expect(gaining.agreesWith(DietGoalDirection.up), isTrue);
      expect(gaining.agreesWith(DietGoalDirection.down), isFalse);
      expect(gaining.agreesWith(null), isNull);
    });
  });

  group('formatKgPerWeek', () {
    test('keeps two decimals of meaning and trims the noise', () {
      expect(formatKgPerWeek(0.35), '0.35');
      expect(formatKgPerWeek(-0.5), '0.5');
      expect(formatKgPerWeek(1), '1');
      expect(formatKgPerWeek(0.004), '0');
    });
  });

  group('resolveBodyMeasures', () {
    final profile = BodyProfile(
      heightCm: 178,
      sex: TargetSex.male,
      activity: ActivityLevel.moderate,
      updatedAt: _now,
    );

    test('assembles the three sources into one set of inputs', () {
      final resolved = resolveBodyMeasures(
        profile: profile,
        latestWeightKg: 82,
        weighedAt: DateTime(2026, 8, 20),
        dateOfBirth: DateTime(1996, 5, 1),
        now: _now,
      );

      expect(resolved.isComplete, isTrue);
      final measures = resolved.measures!;
      expect(measures.weightKg, 82);
      expect(measures.age, 30);
      expect(measures.heightCm, 178);
      expect(measures.weighInAgeDays(_now), 11);
    });

    test('names exactly what is missing rather than defaulting it', () {
      final noWeight = resolveBodyMeasures(
        profile: profile,
        latestWeightKg: null,
        weighedAt: null,
        dateOfBirth: DateTime(1996, 5, 1),
        now: _now,
      );
      expect(noWeight.isComplete, isFalse);
      expect(noWeight.measures, isNull);
      expect(noWeight.missing, {MissingBodyData.weight});

      final noProfile = resolveBodyMeasures(
        profile: null,
        latestWeightKg: 82,
        weighedAt: _now,
        dateOfBirth: DateTime(1996, 5, 1),
        now: _now,
      );
      expect(noProfile.missing, {
        MissingBodyData.height,
        MissingBodyData.sex,
        MissingBodyData.activity,
      });
    });

    test('a weight with no timestamp is not a usable weigh-in', () {
      final resolved = resolveBodyMeasures(
        profile: profile,
        latestWeightKg: 82,
        weighedAt: null,
        dateOfBirth: DateTime(1996, 5, 1),
        now: _now,
      );
      expect(resolved.missing, {MissingBodyData.weight});
    });

    test('birthday not yet reached this year still ages correctly', () {
      final resolved = resolveBodyMeasures(
        profile: profile,
        latestWeightKg: 82,
        weighedAt: _now,
        dateOfBirth: DateTime(1996, 12, 1),
        now: _now,
      );
      expect(resolved.measures!.age, 29);
    });
  });

  group('BodyProfile', () {
    test('a stated maintenance figure can be cleared, not just replaced', () {
      final withStated = BodyProfile(
        heightCm: 178,
        sex: TargetSex.male,
        activity: ActivityLevel.moderate,
        statedMaintenanceKcal: 2900,
        updatedAt: _now,
      );
      expect(
        withStated.copyWith(activity: ActivityLevel.high).statedMaintenanceKcal,
        2900,
      );
      expect(
        withStated.copyWith(statedMaintenanceKcal: null).statedMaintenanceKcal,
        isNull,
      );
    });

    test('plausibility guards catch the typos that matter', () {
      expect(heightIsPlausible(178), isTrue);
      expect(heightIsPlausible(1.78), isFalse);
      expect(heightIsPlausible(300), isFalse);
      expect(statedMaintenanceIsPlausible(2900), isTrue);
      expect(statedMaintenanceIsPlausible(100), isFalse);
    });
  });
}
