import 'live_session.dart';
import 'session_status.dart';

/// Tonnage — total load moved — and how this week compares to last.
///
/// This is the number Today's third ring reports (`7.2 T`, `+12% WoW`). It's
/// the honest whole-training answer to "am I doing more work than I was":
/// reps × weight summed over every completed set, which no single "top set"
/// or streak count captures.

/// One week's tonnage plus its week-over-week movement.
class VolumeTrend {
  const VolumeTrend({
    required this.thisWeekKg,
    required this.lastWeekKg,
    required this.changePercent,
  });

  /// Kilograms moved in the trailing 7 days (today included).
  final double thisWeekKg;

  /// The 7 days before that.
  final double lastWeekKg;

  /// Percent change vs [lastWeekKg] — null when last week had no volume at
  /// all, since "+∞%" is not a number worth showing.
  final double? changePercent;

  bool get isEmpty => thisWeekKg <= 0 && lastWeekKg <= 0;
}

/// Load moved in one session: reps × weight over every DONE set. Sets with no
/// recorded weight (bodyweight, or simply not entered) contribute nothing —
/// tonnage isn't meaningful without a load, and guessing one would quietly
/// inflate the number.
double sessionVolumeKg(LiveSession session) {
  var total = 0.0;
  for (final set in session.allSets) {
    if (!set.done) continue;
    final reps = set.actualReps;
    final weight = set.actualWeightKg;
    if (reps == null || weight == null) continue;
    total += reps * weight;
  }
  return total;
}

/// Tonnage over the trailing 7 days vs the 7 before, from COMPLETED sessions
/// only — an abandoned session's sets were logged but the workout wasn't
/// finished, and counting them would let quitting inflate the trend.
VolumeTrend weeklyVolume(List<LiveSession> sessions, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final thisWeekStart = today.subtract(const Duration(days: 6));
  final lastWeekStart = today.subtract(const Duration(days: 13));

  var thisWeek = 0.0;
  var lastWeek = 0.0;
  for (final session in sessions) {
    if (session.status != SessionStatus.completed) continue;
    final done = session.completedAt ?? session.startedAt;
    final day = DateTime(done.year, done.month, done.day);
    if (day.isAfter(today)) continue;
    final volume = sessionVolumeKg(session);
    if (volume <= 0) continue;
    if (!day.isBefore(thisWeekStart)) {
      thisWeek += volume;
    } else if (!day.isBefore(lastWeekStart)) {
      lastWeek += volume;
    }
  }

  return VolumeTrend(
    thisWeekKg: thisWeek,
    lastWeekKg: lastWeek,
    changePercent: lastWeek <= 0 ? null : (thisWeek - lastWeek) / lastWeek * 100,
  );
}

/// Splits tonnage into the ring's value + unit pair, keeping the unit
/// smaller and dimmer than the value it belongs to (the handoff's rule):
/// 7240kg → ("7.2", "T"), 840kg → ("840", "KG").
({String value, String unit}) formatVolume(double kg) {
  if (kg >= 1000) {
    final tonnes = kg / 1000;
    return (
      value: tonnes >= 100
          ? tonnes.round().toString()
          : tonnes.toStringAsFixed(1),
      unit: 'T',
    );
  }
  return (value: kg.round().toString(), unit: 'KG');
}

/// Every kilogram ever moved, over COMPLETED sessions only — the `412t`
/// lifetime figure on the You screen. Same exclusion as [weeklyVolume]: a
/// quit session's sets were logged but the workout wasn't finished, and
/// counting them would let quitting inflate a lifetime total.
double lifetimeVolumeKg(List<LiveSession> sessions) {
  var total = 0.0;
  for (final session in sessions) {
    if (session.status != SessionStatus.completed) continue;
    total += sessionVolumeKg(session);
  }
  return total;
}
