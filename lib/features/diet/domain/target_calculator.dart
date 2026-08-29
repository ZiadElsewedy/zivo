/// Deterministic target arithmetic — Mifflin-St Jeor for BMR, an activity
/// factor for maintenance, and a goal adjustment on top.
///
/// **This is a suggestion engine, not a source of truth.** It runs on device,
/// with no model involved, so the same inputs always produce the same numbers
/// and every figure can be traced back through [TargetBasis]. The user reviews
/// what it proposes and saves it explicitly; nothing here ever writes a target
/// on its own. An unrequested target the user never approved would be the same
/// trust failure as an invented calorie count, just wearing a formula.
///
/// The equations and factors are the conventional published ones; they are
/// population estimates, not measurements of this person, which is why the
/// result is offered as a starting point to adjust from.
library;

import 'diet_goal.dart';
import 'nutrition_targets.dart';

/// Basal metabolic rate in kcal/day (Mifflin-St Jeor).
///
///   male:   10·kg + 6.25·cm − 5·age + 5
///   female: 10·kg + 6.25·cm − 5·age − 161
int basalMetabolicRate({
  required double weightKg,
  required double heightCm,
  required int age,
  required TargetSex sex,
}) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  final adjusted = sex == TargetSex.male ? base + 5 : base - 161;
  return adjusted.round();
}

/// The proportional calorie adjustment each goal applies to maintenance.
/// Percentages rather than flat numbers so the same goal scales sensibly for
/// a 55kg and a 105kg person.
double goalCalorieFactor(DietGoal goal) => switch (goal) {
  // A ~20% deficit: fast enough to show up on the scale, moderate enough to
  // hold on to muscle and to actually be adhered to.
  DietGoal.fatLoss => 0.80,
  DietGoal.maintain => 1.00,
  // A lean bulk. Bigger surpluses mostly add fat.
  DietGoal.muscleGain => 1.10,
  // Recomposition runs at maintenance; the work is done by protein and
  // training, not by the calorie figure.
  DietGoal.recomp => 1.00,
};

/// Protein target in g per kg of bodyweight for each goal. Higher when
/// calories are restricted (protecting muscle in a deficit) or when building.
double proteinPerKg(DietGoal goal) => switch (goal) {
  DietGoal.fatLoss => 2.2,
  DietGoal.muscleGain => 2.0,
  DietGoal.recomp => 2.2,
  DietGoal.maintain => 1.6,
};

/// The share of calories coming from fat. The remainder, after protein, goes
/// to carbohydrate. 25% keeps fat high enough for hormonal health while
/// leaving room for the carbohydrate that fuels training.
const double _fatCalorieShare = 0.25;

/// Energy per gram, for turning calories into macro grams and back.
const int kcalPerGramProtein = 4;
const int kcalPerGramCarb = 4;
const int kcalPerGramFat = 9;

/// A complete, reviewable proposal: the target itself plus every intermediate
/// figure that produced it, so the UI can show its working rather than
/// presenting a number out of nowhere.
class TargetProposal {
  const TargetProposal({
    required this.targets,
    required this.basis,
    required this.belowSafetyFloor,
  });

  /// The proposed targets, already carrying [TargetSource.calculated] and
  /// their [basis]. NOT saved — the caller passes this to the repository only
  /// after the user accepts it.
  final NutritionTargets targets;
  final TargetBasis basis;

  /// True when the calculated calorie figure lands under
  /// [kMinimumSafeCalories]. Surfaced to the user rather than silently
  /// clamped: quietly "fixing" the number would hide the fact that their
  /// inputs and goal don't add up to something ZIVO should be coaching.
  final bool belowSafetyFloor;
}

/// Builds a [TargetProposal] from body data and a goal. Pure: no clock, no
/// repository, no network — [now] is injected so the result is fully
/// deterministic and testable.
TargetProposal calculateTargets({
  required double weightKg,
  required double heightCm,
  required int age,
  required TargetSex sex,
  required ActivityLevel activity,
  required DietGoal goal,
  required DateTime now,
}) {
  final bmr = basalMetabolicRate(
    weightKg: weightKg,
    heightCm: heightCm,
    age: age,
    sex: sex,
  );
  final maintenance = (bmr * activityFactor(activity)).round();
  final calories = (maintenance * goalCalorieFactor(goal)).round();

  // Protein is set from bodyweight first (it's the macro with a real target),
  // fat takes a fixed share of energy, and carbohydrate takes what's left —
  // so the three always add back up to the calorie figure.
  final proteinG = weightKg * proteinPerKg(goal);
  final fatG = (calories * _fatCalorieShare) / kcalPerGramFat;
  final remainingKcal =
      calories - proteinG * kcalPerGramProtein - fatG * kcalPerGramFat;
  // A very low calorie target with a high protein figure can leave nothing
  // for carbohydrate; report zero rather than a negative gram count.
  final carbsG = remainingKcal <= 0 ? 0.0 : remainingKcal / kcalPerGramCarb;

  final basis = TargetBasis(
    weightKg: weightKg,
    heightCm: heightCm,
    age: age,
    sex: sex,
    activity: activity,
    bmr: bmr,
    maintenanceCalories: maintenance,
  );

  return TargetProposal(
    targets: NutritionTargets(
      goal: goal,
      calories: calories,
      proteinG: _round1(proteinG),
      carbsG: _round1(carbsG),
      fatG: _round1(fatG),
      source: TargetSource.calculated,
      basis: basis,
      updatedAt: now,
    ),
    basis: basis,
    belowSafetyFloor: targetIsBelowSafetyFloor(calories),
  );
}

/// Rounds grams to one decimal — the precision the UI shows, fixed here so
/// the stored value and the displayed value can never disagree.
double _round1(double value) => (value * 10).round() / 10;

/// Age in whole years at [now] for someone born on [dateOfBirth]. Used to
/// prefill the calculator from the profile the user already gave us, rather
/// than asking twice.
int ageFrom(DateTime dateOfBirth, DateTime now) {
  var age = now.year - dateOfBirth.year;
  final hadBirthday = now.month > dateOfBirth.month ||
      (now.month == dateOfBirth.month && now.day >= dateOfBirth.day);
  if (!hadBirthday) age -= 1;
  return age;
}
