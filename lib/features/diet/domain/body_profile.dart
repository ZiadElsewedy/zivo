import 'nutrition_targets.dart';

/// The stable body data ZIVO needs before it can say anything about energy —
/// the parts of a person that don't change week to week.
///
/// **What is deliberately NOT here:**
///
/// - **Weight.** It already exists as a time series in the workout feature's
///   `BodyWeightRepository`, and it is the one figure here that legitimately
///   moves. Copying it would create a second weight that silently disagrees
///   with the log the user is actually keeping. `resolveBodyMeasures` reads
///   the latest weigh-in instead, and reports how old it is.
/// - **Age.** Derived from `UserProfile.dateOfBirth` at the moment of use. A
///   stored integer age is wrong within a year of being written.
///
/// Storing this is **not** the same as deriving a target from it. Nothing
/// writes [NutritionTargets] off the back of a saved profile — the rule stands
/// that a target exists only once the user has approved one (see
/// `nutrition_targets.dart`). What body data buys is the ability to *answer*
/// "what is this plan doing to me", which is arithmetic about a plan, not a
/// number put in the user's mouth.
class BodyProfile {
  const BodyProfile({
    required this.heightCm,
    required this.sex,
    required this.activity,
    required this.updatedAt,
    this.statedMaintenanceKcal,
  });

  final double heightCm;

  /// The BMR equation's sex variable. Mifflin-St Jeor has two forms that sit
  /// ~166 kcal apart, so this is an equation input and nothing else — it is
  /// not shown as an identity field and nothing else in the app reads it.
  final TargetSex sex;

  final ActivityLevel activity;

  /// The user's own maintenance figure, when they already know it — from a
  /// metabolic test, a coach, or their own tracking.
  ///
  /// When present it **replaces** the Mifflin-St Jeor estimate rather than
  /// averaging with it: a measurement of this person beats a population
  /// estimate of people like them, and blending the two would produce a
  /// number neither source stands behind. Null is the normal case.
  final int? statedMaintenanceKcal;

  final DateTime updatedAt;

  BodyProfile copyWith({
    double? heightCm,
    TargetSex? sex,
    ActivityLevel? activity,
    Object? statedMaintenanceKcal = _unset,
    DateTime? updatedAt,
  }) => BodyProfile(
    heightCm: heightCm ?? this.heightCm,
    sex: sex ?? this.sex,
    activity: activity ?? this.activity,
    // Sentinel rather than `??`: clearing a stated maintenance figure back to
    // "I don't know mine" has to be expressible, and `null` already means
    // "leave it alone" for every other field here.
    statedMaintenanceKcal: identical(statedMaintenanceKcal, _unset)
        ? this.statedMaintenanceKcal
        : statedMaintenanceKcal as int?,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

const Object _unset = Object();

/// The height range ZIVO accepts. Outside it the input is a typo (a height in
/// metres, or a weight typed into the wrong field), not a person — and a BMR
/// built on it would be confidently wrong.
const double kMinHeightCm = 100;
const double kMaxHeightCm = 250;

/// The range a stated maintenance figure has to fall in to be believable.
/// Wide on purpose: this is a typo guard, not a judgement about someone's
/// metabolism.
const int kMinStatedMaintenanceKcal = 800;
const int kMaxStatedMaintenanceKcal = 10000;

bool heightIsPlausible(double cm) => cm >= kMinHeightCm && cm <= kMaxHeightCm;

bool statedMaintenanceIsPlausible(int kcal) =>
    kcal >= kMinStatedMaintenanceKcal && kcal <= kMaxStatedMaintenanceKcal;
