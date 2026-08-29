import 'diet_goal.dart';

/// How a set of targets came to exist. Stored with the numbers themselves,
/// because "where did this come from" is as much a part of a target as its
/// value — the same rule [FoodItem.estimated] follows for food.
///
/// There is deliberately no `appDefault`: ZIVO never invents a target. If the
/// user hasn't set one, [NutritionTargets] is null and every surface says so.
enum TargetSource {
  /// The user typed the numbers in themselves (or their coach/dietitian gave
  /// them the numbers and they entered them). The most trustworthy source.
  manual,

  /// Produced by [calculateTargets] from the user's own body data and
  /// reviewed by them before saving. The inputs are kept in [TargetBasis] so
  /// the figure can always be explained and recomputed.
  calculated,

  /// Adopted from what the active plan's day already adds up to — the user
  /// explicitly accepted the plan's own total as their target.
  planDerived,
}

/// A short, honest description of where a target came from, for the UI and
/// for the coach to quote.
String targetSourceLabel(TargetSource source) => switch (source) {
  TargetSource.manual => 'You set this',
  TargetSource.calculated => 'Calculated from your body data',
  TargetSource.planDerived => "Adopted from your plan's daily total",
};

/// The BMR formula's sex variable. This exists solely because Mifflin-St Jeor
/// has two forms; it is an input to an equation, not a profile field, and it
/// is stored only inside a calculated target's [TargetBasis].
enum TargetSex { male, female }

/// How much the user moves, as the activity multiplier applied to BMR.
enum ActivityLevel { sedentary, light, moderate, high, athlete }

/// The multiplier each level applies to BMR to reach maintenance calories.
/// Conventional Mifflin-St Jeor activity factors.
double activityFactor(ActivityLevel level) => switch (level) {
  ActivityLevel.sedentary => 1.2,
  ActivityLevel.light => 1.375,
  ActivityLevel.moderate => 1.55,
  ActivityLevel.high => 1.725,
  ActivityLevel.athlete => 1.9,
};

/// What the user reads when choosing an activity level — described by what
/// their week looks like, not by a multiplier they can't evaluate.
String activityLabel(ActivityLevel level) => switch (level) {
  ActivityLevel.sedentary => 'Sedentary',
  ActivityLevel.light => 'Light',
  ActivityLevel.moderate => 'Moderate',
  ActivityLevel.high => 'High',
  ActivityLevel.athlete => 'Very high',
};

/// The week each activity level describes, so the choice is answerable.
String activityDescription(ActivityLevel level) => switch (level) {
  ActivityLevel.sedentary => 'Desk job, little deliberate exercise',
  ActivityLevel.light => 'Training 1–3 days a week',
  ActivityLevel.moderate => 'Training 3–5 days a week',
  ActivityLevel.high => 'Training 6–7 days a week',
  ActivityLevel.athlete => 'Hard training daily, or a physical job on top',
};

/// Exactly what produced a [TargetSource.calculated] target — kept so the
/// number can always be explained ("2,180 from your 82kg at moderate
/// activity, minus 20% for fat loss") and recomputed when the inputs change.
/// A calculated target with no basis would be indistinguishable from a
/// guessed one.
class TargetBasis {
  const TargetBasis({
    required this.weightKg,
    required this.heightCm,
    required this.age,
    required this.sex,
    required this.activity,
    required this.bmr,
    required this.maintenanceCalories,
  });

  final double weightKg;
  final double heightCm;
  final int age;
  final TargetSex sex;
  final ActivityLevel activity;

  /// Basal metabolic rate from Mifflin-St Jeor, before activity.
  final int bmr;

  /// BMR × [activityFactor] — the "eat this to stay the same" figure the
  /// goal's adjustment is applied to.
  final int maintenanceCalories;
}

/// The user's daily nutrition objective: a goal plus the numbers that serve
/// it, and a record of where those numbers came from.
///
/// Null (no targets saved) is a first-class state, not an error — see
/// [TargetSource].
class NutritionTargets {
  const NutritionTargets({
    required this.goal,
    required this.calories,
    required this.source,
    required this.updatedAt,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.basis,
  });

  final DietGoal goal;

  /// The daily energy target in kcal. Always present — a target without a
  /// calorie figure isn't a target.
  final int calories;

  /// Macro targets in grams. Nullable independently: a user may care about
  /// protein and leave carbs and fat open, and "absent" must not read as 0
  /// (the same rule the plan totals follow).
  final double? proteinG;
  final double? carbsG;
  final double? fatG;

  final TargetSource source;

  /// Present only when [source] is [TargetSource.calculated].
  final TargetBasis? basis;

  final DateTime updatedAt;

  NutritionTargets copyWith({
    DietGoal? goal,
    int? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    TargetSource? source,
    TargetBasis? basis,
    DateTime? updatedAt,
  }) => NutritionTargets(
    goal: goal ?? this.goal,
    calories: calories ?? this.calories,
    proteinG: proteinG ?? this.proteinG,
    carbsG: carbsG ?? this.carbsG,
    fatG: fatG ?? this.fatG,
    source: source ?? this.source,
    basis: basis ?? this.basis,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// The lowest daily calorie figure ZIVO will accept without saying something.
///
/// A conservative general floor: sustained intake below this is the territory
/// of supervised clinical work, not of a training app's coach. ZIVO is not a
/// doctor and must not quietly help someone set a target down here — see
/// [targetIsBelowSafetyFloor], which the UI surfaces as a warning and the
/// coach is told about rather than left to notice.
const int kMinimumSafeCalories = 1200;

/// Whether [calories] sits below [kMinimumSafeCalories]. Deterministic, so
/// the warning can't depend on the model choosing to mention it.
bool targetIsBelowSafetyFloor(int calories) => calories < kMinimumSafeCalories;

/// Parses a stored [TargetSource] name, falling back to [TargetSource.manual]
/// — the honest reading of a legacy or unknown value is "a person put this
/// here", never "the app calculated it".
TargetSource targetSourceFromName(String? name) {
  for (final source in TargetSource.values) {
    if (source.name == name) return source;
  }
  return TargetSource.manual;
}

/// Parses a stored [TargetSex] name; null when absent or unrecognized.
TargetSex? targetSexFromName(String? name) {
  for (final sex in TargetSex.values) {
    if (sex.name == name) return sex;
  }
  return null;
}

/// Parses a stored [ActivityLevel] name; null when absent or unrecognized.
ActivityLevel? activityLevelFromName(String? name) {
  for (final level in ActivityLevel.values) {
    if (level.name == name) return level;
  }
  return null;
}
