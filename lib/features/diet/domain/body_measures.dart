/// Assembling the scattered pieces of "this person's body" into the exact
/// inputs the energy equations take — and, when a piece is missing, saying
/// which one rather than producing a number from a default.
///
/// The pieces genuinely live in three places, and each of them is right:
/// height/sex/activity are stable ([BodyProfile]), weight is a time series the
/// workout feature already owns, and date of birth is part of the account
/// profile. This module is the one place that knows how to put them together,
/// so no screen has to.
library;

import 'body_profile.dart';
import 'nutrition_targets.dart';
import 'target_calculator.dart';

/// A piece of body data ZIVO needs and doesn't have. The verdict is not built
/// from partial inputs — a maintenance figure computed with a guessed height
/// is not a weaker answer, it's a wrong one — so this is what the UI asks for
/// instead.
enum MissingBodyData {
  /// No weigh-in has ever been logged.
  weight,
  height,
  sex,
  activity,

  /// No account profile (and so no date of birth) — only reachable in tests
  /// and during first-run, since sign-up collects it.
  dateOfBirth,
}

/// What the user is asked for, in their words.
String missingBodyDataLabel(MissingBodyData missing) => switch (missing) {
  MissingBodyData.weight => 'your current weight',
  MissingBodyData.height => 'your height',
  MissingBodyData.sex => 'the BMR formula ZIVO should use',
  MissingBodyData.activity => 'how active your week is',
  MissingBodyData.dateOfBirth => 'your date of birth',
};

/// Where a maintenance figure came from. Carried with the number for the same
/// reason [TargetSource] is carried with a target: "how do you know that" is
/// part of the answer, not a footnote.
enum MaintenanceSource {
  /// Measured from this person's own weigh-ins and logged intake — the only
  /// figure here that is an observation rather than a projection. See
  /// `analysis/maintenance_calibration.dart`.
  measured,

  /// The user told ZIVO their own maintenance figure.
  stated,

  /// Mifflin-St Jeor × an activity factor — a population estimate.
  estimated,
}

String maintenanceSourceLabel(MaintenanceSource source) => switch (source) {
  MaintenanceSource.measured => 'your own weigh-ins and food log',
  MaintenanceSource.stated => 'the maintenance figure you gave',
  MaintenanceSource.estimated => 'an estimate from your body data',
};

/// Everything the energy equations need, all present. Constructing one of
/// these is proof the inputs are complete — there are no nullable equation
/// terms in here, which is what stops a "maintenance" figure from quietly
/// resting on a default.
class BodyMeasures {
  const BodyMeasures({
    required this.weightKg,
    required this.weighedAt,
    required this.heightCm,
    required this.age,
    required this.sex,
    required this.activity,
    this.statedMaintenanceKcal,
    this.measuredMaintenanceKcal,
  });

  final double weightKg;

  /// When [weightKg] was logged. Kept because a four-month-old weigh-in makes
  /// every figure downstream stale, and the screen should be able to say so
  /// rather than presenting it as current.
  final DateTime weighedAt;

  final double heightCm;
  final int age;
  final TargetSex sex;
  final ActivityLevel activity;
  final int? statedMaintenanceKcal;

  /// Maintenance measured from this person's own weigh-ins and food log, when
  /// there is enough data to measure it (`maintenance_calibration.dart`).
  ///
  /// **This outranks the equation, and only the equation.** A population
  /// estimate is a number nobody chose, so an observation of the actual person
  /// replaces it outright. A figure the USER stated is different: overriding
  /// what they explicitly told ZIVO would be the app contradicting them
  /// silently. When a measurement disagrees with a stated figure, the
  /// disagreement is surfaced (see `coaching/rules.dart`) and the stated one
  /// still stands until they change it.
  final int? measuredMaintenanceKcal;

  /// Basal metabolic rate (Mifflin-St Jeor) — the same function the target
  /// calculator uses, so a target and a verdict can never disagree about this
  /// person's BMR.
  int get bmr => basalMetabolicRate(
    weightKg: weightKg,
    heightCm: heightCm,
    age: age,
    sex: sex,
  );

  /// The "eat this to stay the same" figure, from the best source available:
  /// what the user stated, else what their own data measures, else the
  /// equation. See [measuredMaintenanceKcal] for why stated outranks measured.
  int get maintenanceKcal =>
      statedMaintenanceKcal ??
      measuredMaintenanceKcal ??
      (bmr * activityFactor(activity)).round();

  MaintenanceSource get maintenanceSource {
    if (statedMaintenanceKcal != null) return MaintenanceSource.stated;
    if (measuredMaintenanceKcal != null) return MaintenanceSource.measured;
    return MaintenanceSource.estimated;
  }

  /// What Mifflin-St Jeor alone says, ignoring every better source. Kept so a
  /// measurement can be compared against the estimate it replaced.
  int get estimatedMaintenanceKcal => (bmr * activityFactor(activity)).round();

  /// How stale the weigh-in is at [now], in whole days.
  int weighInAgeDays(DateTime now) => DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(weighedAt.year, weighedAt.month, weighedAt.day)).inDays;
}

/// How long a weigh-in stays current enough to build a verdict on without
/// saying anything. Past this the UI prompts for a fresh one — bodyweight is
/// the dominant BMR term, so a stale one moves every number downstream.
const int kWeighInStaleAfterDays = 30;

/// The outcome of assembling body data: either complete measures, or exactly
/// what is missing. Never both, and never a partial set of measures.
class BodyMeasuresResolution {
  const BodyMeasuresResolution._(this.measures, this.missing);

  const BodyMeasuresResolution.complete(BodyMeasures measures)
    : this._(measures, const <MissingBodyData>{});

  const BodyMeasuresResolution.incomplete(Set<MissingBodyData> missing)
    : this._(null, missing);

  /// Non-null exactly when [missing] is empty.
  final BodyMeasures? measures;

  /// What is still needed, in the order the UI should ask for it.
  final Set<MissingBodyData> missing;

  bool get isComplete => measures != null;
}

/// Assembles [BodyMeasures] from the three places its parts live, or reports
/// what's missing. Pure: [now] is injected, nothing is read from a clock or a
/// repository here.
///
/// [latestWeightKg]/[weighedAt] come from the workout feature's bodyweight log
/// (its newest entry), [profile] from the diet repository, [dateOfBirth] from
/// the account profile.
BodyMeasuresResolution resolveBodyMeasures({
  required BodyProfile? profile,
  required double? latestWeightKg,
  required DateTime? weighedAt,
  required DateTime? dateOfBirth,
  required DateTime now,
  int? measuredMaintenanceKcal,
}) {
  final missing = <MissingBodyData>{};
  // A weight with no timestamp is not a usable weigh-in — it can't be aged,
  // so it can't be trusted as "current".
  if (latestWeightKg == null || weighedAt == null) {
    missing.add(MissingBodyData.weight);
  }
  if (profile == null) {
    missing
      ..add(MissingBodyData.height)
      ..add(MissingBodyData.sex)
      ..add(MissingBodyData.activity);
  }
  if (dateOfBirth == null) missing.add(MissingBodyData.dateOfBirth);
  if (missing.isNotEmpty) return BodyMeasuresResolution.incomplete(missing);

  return BodyMeasuresResolution.complete(
    BodyMeasures(
      weightKg: latestWeightKg!,
      weighedAt: weighedAt!,
      heightCm: profile!.heightCm,
      age: ageFrom(dateOfBirth!, now),
      sex: profile.sex,
      activity: profile.activity,
      statedMaintenanceKcal: profile.statedMaintenanceKcal,
      measuredMaintenanceKcal: measuredMaintenanceKcal,
    ),
  );
}
