import 'package:flutter/widgets.dart';

import '../../../l10n/l10n.dart';
import '../domain/analysis/maintenance_calibration.dart';
import '../domain/body_measures.dart';
import '../domain/diet_format.dart';
import '../domain/diet_goal.dart';
import '../domain/diet_source.dart';
import '../domain/diet_state.dart';
import '../domain/nutrition/food_reference.dart';
import '../domain/nutrition_targets.dart';

/// The words the diet domain's enums wear on screen.
///
/// The `domain/` layer is Flutter-free by design, so `dietGoalLabel` and its
/// siblings could only ever return English — and they were doing exactly that,
/// straight onto the Targets page and the plan verdict. The same split that
/// `progress_status_style.dart` uses in the workout feature applies here: the
/// enum stays the value, and its *word* is chosen at the presentation layer
/// where a [BuildContext] exists.
///
/// `dietGoalDescription`, `targetSourceLabel` and `calibrationGapLabel` are
/// **gone** from `domain/` rather than kept as a second source — nothing outside
/// `presentation/` called them, and two ways to name a thing is how the two
/// drift apart.
///
/// `dietGoalLabel` is the exception and stays: the coaching engine splices it
/// into generated English prose (`coaching/rules.dart`, `coaching/evidence.dart`),
/// which cannot be half-translated. So the goal has two names on purpose — the
/// engine's, and [dietGoalText]'s. That split is documented on both sides.

/// "Fat loss" — the goal as the user reads it.
String dietGoalText(BuildContext context, DietGoal goal) => switch (goal) {
  DietGoal.fatLoss => l(context).dietGoalFatLoss,
  DietGoal.maintain => l(context).dietGoalMaintain,
  DietGoal.muscleGain => l(context).dietGoalMuscleGain,
  DietGoal.recomp => l(context).dietGoalRecomp,
};

/// One line explaining what choosing [goal] means for the numbers — shown
/// under each option so the user is picking an outcome, not a jargon word.
String dietGoalDetailText(BuildContext context, DietGoal goal) =>
    switch (goal) {
      DietGoal.fatLoss => l(context).dietGoalFatLossDetail,
      DietGoal.maintain => l(context).dietGoalMaintainDetail,
      DietGoal.muscleGain => l(context).dietGoalMuscleGainDetail,
      DietGoal.recomp => l(context).dietGoalRecompDetail,
    };

/// A short, honest description of where a calorie target came from.
String targetSourceText(BuildContext context, TargetSource source) =>
    switch (source) {
      TargetSource.manual => l(context).dietTargetSourceManual,
      TargetSource.calculated => l(context).dietTargetSourceCalculated,
      TargetSource.planDerived => l(context).dietTargetSourcePlan,
    };

/// What the user is still missing before ZIVO can measure — rather than
/// estimate — what they actually burn, phrased to drop into a sentence.
String calibrationGapText(BuildContext context, CalibrationGap gap) =>
    switch (gap) {
      CalibrationGap.needsWeighIns => l(context).dietCalibrationNeedsWeighIns,
      CalibrationGap.needsLongerWindow => l(
        context,
      ).dietCalibrationNeedsLongerWindow(kMinCalibrationDays),
      CalibrationGap.needsMoreLoggedDays =>
        l(context).dietCalibrationNeedsMoreDays,
    };

/// "Protein" — the macro as the user reads it.
///
/// Takes the [MacroKind], never the English `label`: the label is the coaching
/// engine's word, and switching on it is how a translated string quietly stops
/// matching.
String macroText(BuildContext context, MacroKind kind) => switch (kind) {
  MacroKind.protein => l(context).dietMacroProtein,
  MacroKind.carbs => l(context).dietMacroCarbs,
  MacroKind.fat => l(context).dietMacroFat,
};

/// What the user is still asked for, phrased to drop into a sentence
/// ("ZIVO needs *your height and how active your week is* to work it out.").
String missingBodyDataText(BuildContext context, MissingBodyData missing) =>
    switch (missing) {
      MissingBodyData.weight => l(context).dietMissingWeight,
      MissingBodyData.height => l(context).dietMissingHeight,
      MissingBodyData.sex => l(context).dietMissingSex,
      MissingBodyData.activity => l(context).dietMissingActivity,
      MissingBodyData.dateOfBirth => l(context).dietMissingDateOfBirth,
    };

/// Where a food's nutrition figures came from — shown beside a logged entry so
/// a reference figure and a plan figure are never mistaken for each other.
String nutritionSourceText(BuildContext context, NutritionSource source) =>
    switch (source) {
      NutritionSource.usdaFdc => l(context).dietSourceUsda,
      NutritionSource.userCustom => l(context).dietSourceUserCustom,
      NutritionSource.dietPlan => l(context).dietSourcePlan,
    };

/// "Moderate" — the activity level as the user reads it.
String activityText(BuildContext context, ActivityLevel level) =>
    switch (level) {
      ActivityLevel.sedentary => l(context).dietActivitySedentary,
      ActivityLevel.light => l(context).dietActivityLight,
      ActivityLevel.moderate => l(context).dietActivityModerate,
      ActivityLevel.high => l(context).dietActivityHigh,
      ActivityLevel.athlete => l(context).dietActivityAthlete,
    };

/// The week each activity level describes, so the choice is answerable.
String activityDetailText(BuildContext context, ActivityLevel level) =>
    switch (level) {
      ActivityLevel.sedentary => l(context).dietActivitySedentaryDetail,
      ActivityLevel.light => l(context).dietActivityLightDetail,
      ActivityLevel.moderate => l(context).dietActivityModerateDetail,
      ActivityLevel.high => l(context).dietActivityHighDetail,
      ActivityLevel.athlete => l(context).dietActivityAthleteDetail,
    };

/// The one-line explanation of a calculated target — the body data it came
/// from and the maintenance figure the goal's adjustment was applied to.
///
/// Shown under the target itself, because `TargetSource.calculated` on its own
/// only says a formula was involved; this says which numbers went into it, so
/// a user who has since changed weight can see that the target hasn't.
String targetBasisText(BuildContext context, TargetBasis basis) =>
    l(context).dietTargetBasisSummary(
      trimNumber(basis.weightKg),
      activityText(context, basis.activity).toLowerCase(),
      basis.maintenanceCalories,
    );

/// How a plan came to exist, as shown on its card.
///
/// `dietSourceLabel` stays in `domain/` — two tests assert on it as a proxy for
/// the enum, and it reads as the same kind of stable vocabulary as
/// [dietGoalLabel]. This is the screen's half.
String dietSourceText(BuildContext context, DietSource source) =>
    switch (source) {
      DietSource.manual => l(context).dietSourceManual,
      DietSource.pdf => l(context).dietSourcePdf,
      DietSource.photo => l(context).dietSourcePhoto,
      DietSource.dictated => l(context).dietSourceDictated,
      DietSource.generated => l(context).dietSourceGenerated,
    };
