/// What a diet plan will do to bodyweight — the question a person actually
/// arrives with, answered by arithmetic.
///
/// **Deterministic on purpose, exactly like `domain/coaching/rules.dart`.**
/// The model phrases findings; it does not decide them. A verdict that
/// depended on a model call would be non-reproducible, unavailable offline,
/// impossible to pin with vectors — and free to announce "you'll gain" about
/// a subtraction it never performed. Everything here is a pure function of a
/// plan and a set of body measures, and every intermediate figure survives on
/// the result so the screen can show its working.
library;

import '../body_measures.dart';
import '../diet_day.dart';
import '../diet_format.dart';
import '../diet_plan.dart';
import '../meal.dart';
import '../nutrition_targets.dart';

/// Which way a plan moves the scale.
enum EnergyDirection { losing, holding, gaining }

/// The band around maintenance inside which a plan is called *holding*
/// rather than a very slow gain or loss.
///
/// Not a rounding convenience — an honesty floor. A population BMR equation
/// plus a five-step activity multiplier carries error far wider than 100
/// kcal/day, so "+40 kcal → gaining 0.04 kg a week" is a claim the inputs
/// cannot support. Inside the band ZIVO says the plan holds and means "I
/// can't tell these apart", which is the truth.
const int kEnergyDeadbandKcal = 100;

/// The energy in a kilogram of bodyweight change, the conventional figure.
/// A linear approximation — real bodies plateau and adapt — which is why the
/// projection is always spoken with a "~".
const int kKcalPerKgBodyweight = 7700;

/// What a plan does to this person, with the working attached.
class PlanVerdict {
  const PlanVerdict({
    required this.planKcalPerDay,
    required this.maintenanceKcal,
    required this.maintenanceSource,
    required this.direction,
    required this.projectedKgPerWeek,
    required this.estimated,
    required this.daysCounted,
    required this.daysWithoutCalories,
    required this.belowSafetyFloor,
    this.proteinGPerKg,
  });

  /// The plan's average daily calories across the days that carry any.
  /// Supplements are excluded, matching [dayCalories] — the vitamins block is
  /// not energy.
  final int planKcalPerDay;

  final int maintenanceKcal;
  final MaintenanceSource maintenanceSource;

  /// Plan minus maintenance. Positive is a surplus.
  int get deltaKcal => planKcalPerDay - maintenanceKcal;

  final EnergyDirection direction;

  /// Signed: negative when losing. Reported even when [direction] is
  /// [EnergyDirection.holding] — the caller decides whether a figure inside
  /// the deadband is worth printing, but it is never silently zeroed.
  final double projectedKgPerWeek;

  /// True when any counted day rests on AI-estimated food figures. An
  /// imported plan's calories were generated, not looked up (see
  /// `diet/FEATURE.md`), and a verdict computed from them inherits that —
  /// so it prints with the same "~" the totals do.
  final bool estimated;

  /// How many of the plan's days had calories to count.
  final int daysCounted;

  /// How many didn't. Non-zero means the average speaks for part of the plan,
  /// and the screen has to say so rather than presenting it as the whole.
  final int daysWithoutCalories;

  /// The plan's protein per kg of bodyweight — the second thing that decides
  /// whether a surplus becomes muscle or just weight. Null when the plan
  /// carries no protein figures at all.
  final double? proteinGPerKg;

  /// True when the plan's own daily calories sit under
  /// [kMinimumSafeCalories]. Surfaced, never clamped.
  final bool belowSafetyFloor;

  /// Whether the plan and [goal] are pulling in the same direction. Null when
  /// there is no goal to compare against — the verdict stands on its own.
  bool? agreesWith(DietGoalDirection? goal) => goal == null
      ? null
      : switch (goal) {
          DietGoalDirection.down => direction == EnergyDirection.losing,
          DietGoalDirection.hold => direction == EnergyDirection.holding,
          DietGoalDirection.up => direction == EnergyDirection.gaining,
        };
}

/// A goal reduced to the direction it wants the scale to move, so a verdict
/// can be compared to it without the analysis module depending on the whole
/// target model.
enum DietGoalDirection { down, hold, up }

/// What a plan asks you to eat on an average day, and how much of the plan
/// that average actually speaks for.
///
/// **The one basis for every "this plan is N kcal a day" figure in the app** —
/// the verdict, the library card and the adopt-as-target action all call this,
/// so they cannot quote different numbers for the same plan. Supplements are
/// excluded (matching [dayCalories]) and days with no calorie figures are
/// counted, not silently averaged in as zero.
({
  int? kcalPerDay,
  double? proteinG,
  double? carbsG,
  double? fatG,
  int daysCounted,
  int daysWithoutCalories,
  bool estimated,
})
planDailyEnergy(DietPlan plan) {
  final counted = <DietDay>[];
  var daysWithoutCalories = 0;
  for (final day in plan.days) {
    if (dayCalories(day) == null) {
      daysWithoutCalories++;
    } else {
      counted.add(day);
    }
  }
  if (counted.isEmpty) {
    return (
      kcalPerDay: null,
      proteinG: null,
      carbsG: null,
      fatG: null,
      daysCounted: 0,
      daysWithoutCalories: daysWithoutCalories,
      estimated: false,
    );
  }
  final total = counted.fold<int>(0, (sum, d) => sum + dayCalories(d)!);
  final macros = counted
      .map((d) => macroTotals(regularMeals(d.meals).expand((m) => m.items)))
      .toList();

  double? averageMacro(
    double? Function(({double? proteinG, double? carbsG, double? fatG}) t) pick,
  ) {
    final values = macros.map(pick).whereType<double>().toList();
    if (values.isEmpty) return null;
    return values.fold<double>(0, (s, v) => s + v) / values.length;
  }

  return (
    // Rounded once, here, so every figure derived from it agrees.
    kcalPerDay: (total / counted.length).round(),
    proteinG: averageMacro((t) => t.proteinG),
    carbsG: averageMacro((t) => t.carbsG),
    fatG: averageMacro((t) => t.fatG),
    daysCounted: counted.length,
    daysWithoutCalories: daysWithoutCalories,
    estimated: counted.any(dayEstimated),
  );
}

/// Measures [plan] against [measures].
///
/// Returns null when the plan carries no calorie figures at all — there is
/// nothing to measure, and an answer built from zero days would be a
/// fabrication rather than a weak reading.
PlanVerdict? analysePlan({
  required DietPlan plan,
  required BodyMeasures measures,
}) {
  final energy = planDailyEnergy(plan);
  final planKcalPerDay = energy.kcalPerDay;
  if (planKcalPerDay == null) return null;

  final maintenance = measures.maintenanceKcal;
  final delta = planKcalPerDay - maintenance;
  final direction = delta.abs() < kEnergyDeadbandKcal
      ? EnergyDirection.holding
      : (delta > 0 ? EnergyDirection.gaining : EnergyDirection.losing);

  return PlanVerdict(
    planKcalPerDay: planKcalPerDay,
    maintenanceKcal: maintenance,
    maintenanceSource: measures.maintenanceSource,
    direction: direction,
    projectedKgPerWeek: (delta * 7) / kKcalPerKgBodyweight,
    estimated: energy.estimated,
    daysCounted: energy.daysCounted,
    daysWithoutCalories: energy.daysWithoutCalories,
    proteinGPerKg: energy.proteinG == null || measures.weightKg <= 0
        ? null
        : energy.proteinG! / measures.weightKg,
    belowSafetyFloor: targetIsBelowSafetyFloor(planKcalPerDay),
  );
}

/// The headline, in plain language. "~0.35 kg a week" and not "+380 kcal":
/// the calorie delta is the working, the weight is the answer.
String verdictHeadline(PlanVerdict verdict) => switch (verdict.direction) {
  EnergyDirection.holding => 'Holds your weight steady',
  EnergyDirection.gaining =>
    'Gaining ~${formatKgPerWeek(verdict.projectedKgPerWeek)} kg a week',
  EnergyDirection.losing =>
    'Losing ~${formatKgPerWeek(verdict.projectedKgPerWeek)} kg a week',
};

/// The working under the headline: the two numbers that produced it and
/// where the second one came from.
String verdictDetail(PlanVerdict verdict) {
  final tilde = approx(verdict.estimated);
  final delta = verdict.deltaKcal.abs();
  final relation = switch (verdict.direction) {
    EnergyDirection.holding => 'within $delta kcal of',
    EnergyDirection.gaining => '$delta kcal above',
    EnergyDirection.losing => '$delta kcal below',
  };
  return '$tilde${verdict.planKcalPerDay} kcal a day · $relation your '
      '${verdict.maintenanceKcal} kcal maintenance, from '
      '${maintenanceSourceLabel(verdict.maintenanceSource)}';
}

/// Kilograms to two decimals with trailing zeros trimmed: 0.35 → "0.35",
/// 0.5 → "0.5", 1 → "1". One decimal (the app's usual [trimNumber]) is too
/// coarse here — half the plausible range of weekly change rounds to the
/// same figure.
String formatKgPerWeek(double kg) {
  final rounded = (kg.abs() * 100).round() / 100;
  return rounded
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
