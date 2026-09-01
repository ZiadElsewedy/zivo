/// Measuring maintenance from what actually happened, instead of estimating
/// it from an equation.
///
/// **This is the only figure in the app that is a measurement of this person.**
/// Mifflin-St Jeor is a population average with a standard error of several
/// hundred kcal; it tells you what people of a given size usually burn, not
/// what you burn. But a month of logged intake and two weigh-ins is a direct
/// observation: energy in, minus energy stored or released, is energy out.
///
///     maintenance = average intake − (weight change × 7700 kcal/kg ÷ days)
///
/// So a person eating 2,600 kcal a day who gained 0.8 kg over 28 days is
/// maintaining at about 2,380, whatever the equation says.
///
/// The arithmetic is trivial; the honesty is not. This module refuses far more
/// often than it answers, because a calibration built on a fortnight of
/// half-logged days is worse than no calibration — it carries the authority of
/// a measurement with none of the substance. Every refusal names its reason so
/// the UI can say what is missing rather than staying silent.
///
/// Pure: no clock, no repository. [now] is injected.
library;

import '../../../workout/domain/body_weight_entry.dart';
import 'plan_verdict.dart' show kKcalPerKgBodyweight;

/// One day's recorded intake. Days with nothing logged are simply absent —
/// an absent day is unknown, never a measured zero, and treating it as zero
/// would drag every average down and manufacture a deficit.
class DailyIntake {
  const DailyIntake({required this.dayKey, required this.kcal});

  /// 'yyyy-MM-dd', the same day identity the rest of the diet feature uses.
  final String dayKey;
  final int kcal;
}

/// Why a calibration couldn't be made. Each one is something the user can
/// actually do something about, which is why they are named rather than
/// collapsed into a single null.
enum CalibrationGap {
  /// Fewer than two weigh-ins — there is no change to measure.
  needsWeighIns,

  /// The weigh-ins are too close together in time. Day-to-day bodyweight
  /// swings by a kilo on water alone, so a short window measures hydration,
  /// not energy balance.
  needsLongerWindow,

  /// Too few of the days in the window have any food logged. The intake
  /// average would be speaking for days it never saw.
  needsMoreLoggedDays,
}

/// What the user is asked for, in their words.
String calibrationGapLabel(CalibrationGap gap) => switch (gap) {
  CalibrationGap.needsWeighIns => 'two weigh-ins',
  CalibrationGap.needsLongerWindow =>
    'weigh-ins at least $kMinCalibrationDays days apart',
  CalibrationGap.needsMoreLoggedDays => 'more days of food logged',
};

/// The shortest window a calibration may rest on.
///
/// Two weeks. Bodyweight moves a kilogram or more on water, glycogen and gut
/// contents within a single day; over ten days that noise can be the whole
/// signal. Fourteen days is where the trend starts to outweigh it — and even
/// then the result is spoken with a "~".
const int kMinCalibrationDays = 14;

/// The share of days in the window that must have food logged.
///
/// Two thirds. The intake average is the load-bearing input, and an average
/// over half a month of a two-month window is a guess wearing a mean. Below
/// this the answer is "log more", not a number.
const double kMinLoggedCoverage = 2 / 3;

/// The fewest logged days that can support an average, whatever the coverage
/// fraction says. Guards a short window where a handful of days would clear
/// the percentage bar on arithmetic alone.
const int kMinLoggedDays = 10;

/// A maintenance figure measured from this person's own data.
class MeasuredMaintenance {
  const MeasuredMaintenance({
    required this.maintenanceKcal,
    required this.averageIntakeKcal,
    required this.weightChangeKg,
    required this.days,
    required this.loggedDays,
    required this.from,
    required this.to,
  });

  /// The measured figure: what they ate, adjusted for what the scale did.
  final int maintenanceKcal;

  /// Mean daily intake across the logged days in the window.
  final int averageIntakeKcal;

  /// Signed: negative when they lost weight over the window.
  final double weightChangeKg;

  /// Calendar days between the first and last weigh-in.
  final int days;

  /// How many of those days had food logged. Carried so the figure can always
  /// say how much of the window it actually saw.
  final int loggedDays;

  final DateTime from;
  final DateTime to;

  /// The share of the window that was logged, 0..1.
  double get coverage => days <= 0 ? 0 : loggedDays / days;

  /// Kilograms a week, signed — the same unit the plan verdict projects in,
  /// so a projection and an observation can be compared directly.
  double get observedKgPerWeek => days <= 0 ? 0 : weightChangeKg * 7 / days;
}

/// The outcome: a measurement, or exactly what it is short of.
class CalibrationResult {
  const CalibrationResult._(this.measured, this.gap);

  const CalibrationResult.measured(MeasuredMaintenance value)
    : this._(value, null);

  const CalibrationResult.needs(CalibrationGap gap) : this._(null, gap);

  /// Non-null exactly when [gap] is null.
  final MeasuredMaintenance? measured;
  final CalibrationGap? gap;

  bool get isMeasured => measured != null;
}

/// Measures maintenance from weigh-ins and logged intake, or says what's
/// missing.
///
/// [weighIns] may be in any order; [intake] holds only days that had
/// something logged. Days outside the window between the first and last
/// weigh-in are ignored — the measurement is of that window and nothing else.
CalibrationResult calibrateMaintenance({
  required List<BodyWeightEntry> weighIns,
  required List<DailyIntake> intake,
  required DateTime now,
}) {
  if (weighIns.length < 2) {
    return const CalibrationResult.needs(CalibrationGap.needsWeighIns);
  }

  final sorted = [...weighIns]
    ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
  final first = sorted.first;
  final last = sorted.last;
  final from = _dateOf(first.loggedAt);
  final to = _dateOf(last.loggedAt);
  final days = to.difference(from).inDays;
  if (days < kMinCalibrationDays) {
    return const CalibrationResult.needs(CalibrationGap.needsLongerWindow);
  }

  // Only the days the window actually covers. An intake entry from before the
  // first weigh-in describes a period the weight change says nothing about.
  final fromKey = _dayKeyOf(from);
  final toKey = _dayKeyOf(to);
  final inWindow = intake
      .where((d) => d.dayKey.compareTo(fromKey) >= 0)
      .where((d) => d.dayKey.compareTo(toKey) <= 0)
      .toList();

  if (inWindow.length < kMinLoggedDays ||
      inWindow.length / days < kMinLoggedCoverage) {
    return const CalibrationResult.needs(CalibrationGap.needsMoreLoggedDays);
  }

  final averageIntake =
      inWindow.fold<int>(0, (sum, d) => sum + d.kcal) / inWindow.length;
  final weightChangeKg = last.weightKg - first.weightKg;
  // The energy that change represents, spread back over the window. Gaining
  // means some of what they ate went into storage, so their true maintenance
  // is BELOW what they ate — hence the subtraction.
  final storedPerDay = weightChangeKg * kKcalPerKgBodyweight / days;

  return CalibrationResult.measured(
    MeasuredMaintenance(
      maintenanceKcal: (averageIntake - storedPerDay).round(),
      averageIntakeKcal: averageIntake.round(),
      weightChangeKg: weightChangeKg,
      days: days,
      loggedDays: inWindow.length,
      from: from,
      to: to,
    ),
  );
}

/// How far a measured figure sits from an estimated one before the difference
/// is worth telling the user about.
///
/// 150 kcal a day. Below that the two agree as well as either can claim to,
/// and reporting a 40 kcal "disagreement" between a population equation and a
/// noisy measurement would be theatre.
const int kMaintenanceDisagreementKcal = 150;

/// Whether [measured] and [other] differ by enough to be worth saying.
bool maintenanceDisagrees(int measured, int other) =>
    (measured - other).abs() >= kMaintenanceDisagreementKcal;

DateTime _dateOf(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _dayKeyOf(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
