import 'dart:math' as math;

import 'sleep_night.dart';
import 'sleep_targets.dart';

/// The deterministic statistics layer. Pure functions, no clock, no I/O.
///
/// Two things happen here that the rest of the feature depends on.
///
/// **Clock times are averaged on a circle.** The arithmetic mean of 23:40 and
/// 00:20 is 12:00 — noon — and that single line is the most common bug in
/// sleep apps. Bedtimes, wake times and midpoints are angles on a 24-hour
/// dial: average the unit vectors and take the resultant angle.
/// [circularMeanMinutes] is the only sanctioned way to average a clock time in
/// this codebase.
///
/// **Every output is gated by n.** A "trend" over two nights is decoration.
/// The thresholds in [SleepGates] are checked before a figure is produced at
/// all, so an ungated number cannot reach the UI or the AI — the type system
/// carries the gate as a nullable, not a convention someone has to remember
/// (`docs/SLEEP_SYSTEM.md` §16).
abstract final class SleepGates {
  /// Below this, an average is a rumour.
  static const int minNightsForAverage = 3;

  /// Variability needs enough points for the spread to mean anything.
  static const int minNightsForVariability = 5;

  /// Week-over-week needs a real week on both sides.
  static const int minNightsPerWeekForComparison = 5;

  /// A trend needs a fortnight, spread over at least three calendar weeks so
  /// it is not two dense clusters pretending to be a line.
  static const int minNightsForTrend = 14;
  static const int minDaysSpanForTrend = 21;

  /// The minimum week-over-week difference we are willing to call a change.
  ///
  /// With ~6 nights a week and a nightly SD around 45 minutes, the standard
  /// error of a weekly mean is roughly 18 minutes — so a 10-minute
  /// "improvement" is noise wearing a number's clothes. Below this floor the
  /// honest output is "about the same as last week", which is a real finding
  /// rather than a failure to find one.
  static const int minMeaningfulDeltaMinutes = 15;

  /// Weekday/weekend splits need both halves represented.
  static const int minWeekdayNights = 3;
  static const int minWeekendNights = 2;
}

/// Everything computable about one window of nights. Fields are nullable
/// exactly where their gate can fail — a null here means "not enough data",
/// which the UI renders as words and the AI is forbidden from discussing.
class SleepWindowMetrics {
  const SleepWindowMetrics({
    required this.nightCount,
    required this.windowNights,
    this.meanDurationMinutes,
    this.medianDurationMinutes,
    this.meanBedtimeMinutes,
    this.meanWakeMinutes,
    this.meanMidpointMinutes,
    this.bedtimeSdMinutes,
    this.wakeSdMinutes,
    this.midpointSdMinutes,
    this.durationSdMinutes,
    this.nightsOnTargetBedtime,
    this.nightsMeetingDuration,
  });

  /// Nights with actual data. Every figure below is over exactly these.
  final int nightCount;

  /// Length of the window asked about — so the UI can say "6 of 7 nights"
  /// rather than implying a full week was measured.
  final int windowNights;

  final double? meanDurationMinutes;

  /// Reported alongside the mean because they answer different questions: one
  /// all-nighter drags the mean and leaves the median where the typical night
  /// actually is. Where they disagree, the week was irregular — which is
  /// itself the finding.
  final double? medianDurationMinutes;

  /// Circular means. See the class doc for why these are not arithmetic.
  final double? meanBedtimeMinutes;
  final double? meanWakeMinutes;
  final double? meanMidpointMinutes;

  /// Circular standard deviations, in minutes.
  final double? bedtimeSdMinutes;
  final double? wakeSdMinutes;

  /// The headline consistency figure. Sleep midpoint is the standard
  /// chronobiological phase marker: robust to a night that simply ran long, in
  /// a way bedtime alone is not.
  final double? midpointSdMinutes;

  final double? durationSdMinutes;

  /// Nights inside [SleepTargets.adherenceToleranceMinutes] of target bedtime.
  final int? nightsOnTargetBedtime;

  /// Nights that reached the target sleep duration.
  final int? nightsMeetingDuration;

  bool get hasAverage => meanDurationMinutes != null;
  bool get hasVariability => midpointSdMinutes != null;
}

/// Result of comparing two windows. Deliberately a small closed vocabulary
/// rather than a raw delta: the *interpretation* is where a number becomes a
/// claim, and that decision belongs here, once, not in each widget.
class SleepComparison {
  const SleepComparison({
    required this.verdict,
    this.deltaMinutes,
    required this.currentNights,
    required this.previousNights,
  });

  final SleepComparisonVerdict verdict;

  /// Signed change in mean duration, minutes. Present whenever both windows
  /// passed their gate — even when the verdict is [unchanged], so the UI can
  /// show the figure while refusing to call it a change.
  final int? deltaMinutes;

  final int currentNights;
  final int previousNights;
}

enum SleepComparisonVerdict {
  /// One or both windows failed [SleepGates.minNightsPerWeekForComparison].
  insufficientData,

  /// Both windows qualified; the difference is below
  /// [SleepGates.minMeaningfulDeltaMinutes] and we will not call it a change.
  unchanged,
  improved,
  declined,
}

/// A direction over a longer run, from a robust slope.
class SleepTrend {
  const SleepTrend({
    required this.direction,
    this.minutesPerNight,
    required this.nightCount,
    required this.daySpan,
  });

  final SleepTrendDirection direction;

  /// Theil–Sen slope in minutes of sleep gained per night. Null when the trend
  /// gate failed.
  final double? minutesPerNight;

  final int nightCount;
  final int daySpan;
}

enum SleepTrendDirection { insufficientData, rising, falling, flat }

/// The statistics themselves.
abstract final class SleepMetrics {
  /// Mean of a set of clock times, as minutes since midnight in `[0, 1440)`.
  ///
  /// Treats each time as an angle, averages the unit vectors, and converts the
  /// resultant back. Returns null for an empty input, and for the degenerate
  /// case where the vectors cancel (times spread evenly round the dial) — a
  /// resultant of zero length has no defined direction, and inventing one
  /// would be exactly the sort of confident nonsense this file exists to
  /// prevent.
  static double? circularMeanMinutes(Iterable<int> minutes) {
    if (minutes.isEmpty) return null;
    var sumSin = 0.0;
    var sumCos = 0.0;
    var n = 0;
    for (final m in minutes) {
      final angle = _toAngle(m);
      sumSin += math.sin(angle);
      sumCos += math.cos(angle);
      n++;
    }
    final meanSin = sumSin / n;
    final meanCos = sumCos / n;
    if (_resultantLength(meanSin, meanCos) < 1e-9) return null;
    var angle = math.atan2(meanSin, meanCos);
    if (angle < 0) angle += 2 * math.pi;
    return angle / (2 * math.pi) * _minutesPerDay;
  }

  /// Circular standard deviation of clock times, in minutes.
  ///
  /// `sd = sqrt(-2 ln R)` on the unit circle, scaled to minutes. Small R means
  /// widely scattered times; R near 1 means tightly clustered. Reported to the
  /// user as "your midpoint varied by ±48 min", which is a sentence a person
  /// can act on.
  static double? circularSdMinutes(Iterable<int> minutes) {
    final values = minutes.toList();
    if (values.length < 2) return null;
    var sumSin = 0.0;
    var sumCos = 0.0;
    for (final m in values) {
      final angle = _toAngle(m);
      sumSin += math.sin(angle);
      sumCos += math.cos(angle);
    }
    final r = _resultantLength(sumSin / values.length, sumCos / values.length);
    if (r <= 1e-9) return null;
    if (r >= 1) return 0;
    final sdRadians = math.sqrt(-2 * math.log(r));
    return sdRadians / (2 * math.pi) * _minutesPerDay;
  }

  /// Computes everything for [nights], applying every gate in [SleepGates].
  ///
  /// [windowNights] is the length of the period asked about, carried through
  /// so the UI can report "6 of 7" instead of implying a complete week.
  static SleepWindowMetrics forWindow(
    List<SleepNight> nights, {
    required int windowNights,
    SleepTargets? targets,
  }) {
    final withData = nights.where((n) => n.hasData).toList();
    final n = withData.length;

    if (n < SleepGates.minNightsForAverage) {
      return SleepWindowMetrics(nightCount: n, windowNights: windowNights);
    }

    final durations = [
      for (final night in withData) night.main!.asleepDuration.inMinutes,
    ];
    final bedtimes = [
      for (final night in withData) night.main!.localBedtimeMinutes,
    ];
    final wakes = [for (final night in withData) night.main!.localWakeMinutes];
    final midpoints = [
      for (final night in withData) night.main!.localMidpointMinutes,
    ];

    final hasVariability = n >= SleepGates.minNightsForVariability;

    int? onTargetBedtime;
    int? meetingDuration;
    if (targets != null) {
      onTargetBedtime = withData
          .where(
            (night) =>
                signedClockDelta(
                  night.main!.localBedtimeMinutes,
                  targets.bedtimeMinutes,
                ).abs() <=
                SleepTargets.adherenceToleranceMinutes,
          )
          .length;
      meetingDuration = withData
          .where(
            (night) =>
                night.main!.asleepDuration.inMinutes >= targets.durationMinutes,
          )
          .length;
    }

    return SleepWindowMetrics(
      nightCount: n,
      windowNights: windowNights,
      meanDurationMinutes: _mean(durations),
      medianDurationMinutes: _median(durations),
      meanBedtimeMinutes: circularMeanMinutes(bedtimes),
      meanWakeMinutes: circularMeanMinutes(wakes),
      meanMidpointMinutes: circularMeanMinutes(midpoints),
      bedtimeSdMinutes: hasVariability ? circularSdMinutes(bedtimes) : null,
      wakeSdMinutes: hasVariability ? circularSdMinutes(wakes) : null,
      midpointSdMinutes: hasVariability ? circularSdMinutes(midpoints) : null,
      durationSdMinutes: hasVariability ? _sd(durations) : null,
      nightsOnTargetBedtime: onTargetBedtime,
      nightsMeetingDuration: meetingDuration,
    );
  }

  /// Week over week, with the minimum-detectable-difference floor applied.
  ///
  /// Returns [SleepComparisonVerdict.unchanged] — carrying the delta — rather
  /// than a direction, whenever the difference is inside the noise floor.
  static SleepComparison compare({
    required SleepWindowMetrics current,
    required SleepWindowMetrics previous,
  }) {
    final a = current.meanDurationMinutes;
    final b = previous.meanDurationMinutes;
    if (a == null ||
        b == null ||
        current.nightCount < SleepGates.minNightsPerWeekForComparison ||
        previous.nightCount < SleepGates.minNightsPerWeekForComparison) {
      return SleepComparison(
        verdict: SleepComparisonVerdict.insufficientData,
        currentNights: current.nightCount,
        previousNights: previous.nightCount,
      );
    }

    final delta = (a - b).round();
    final verdict = delta.abs() < SleepGates.minMeaningfulDeltaMinutes
        ? SleepComparisonVerdict.unchanged
        : (delta > 0
              ? SleepComparisonVerdict.improved
              : SleepComparisonVerdict.declined);

    return SleepComparison(
      verdict: verdict,
      deltaMinutes: delta,
      currentNights: current.nightCount,
      previousNights: previous.nightCount,
    );
  }

  /// Direction of sleep duration over a longer run, as a **Theil–Sen** slope:
  /// the median of the pairwise slopes between every pair of nights.
  ///
  /// Least squares would let one all-nighter flip a fortnight's direction;
  /// Theil–Sen tolerates up to ~29% outliers before it does. In a domain where
  /// a single terrible night is completely normal, that robustness is the
  /// difference between a trend and a mood.
  static SleepTrend trend(List<SleepNight> nights) {
    final withData = nights.where((n) => n.hasData).toList()
      ..sort((a, b) => a.sleepDay.compareTo(b.sleepDay));

    final span = withData.length < 2
        ? 0
        : withData.last.sleepDay.difference(withData.first.sleepDay).inDays;

    if (withData.length < SleepGates.minNightsForTrend ||
        span < SleepGates.minDaysSpanForTrend) {
      return SleepTrend(
        direction: SleepTrendDirection.insufficientData,
        nightCount: withData.length,
        daySpan: span,
      );
    }

    final points = <(double, double)>[
      for (final night in withData)
        (
          night.sleepDay.difference(withData.first.sleepDay).inDays.toDouble(),
          night.main!.asleepDuration.inMinutes.toDouble(),
        ),
    ];

    final slopes = <double>[];
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final dx = points[j].$1 - points[i].$1;
        if (dx == 0) continue;
        slopes.add((points[j].$2 - points[i].$2) / dx);
      }
    }
    if (slopes.isEmpty) {
      return SleepTrend(
        direction: SleepTrendDirection.insufficientData,
        nightCount: withData.length,
        daySpan: span,
      );
    }

    final slope = _median(slopes)!;
    // Under a minute a night is half an hour a month — real, but not something
    // to announce as a direction.
    const flatBand = 1.0;
    final direction = slope.abs() < flatBand
        ? SleepTrendDirection.flat
        : (slope > 0
              ? SleepTrendDirection.rising
              : SleepTrendDirection.falling);

    return SleepTrend(
      direction: direction,
      minutesPerNight: slope,
      nightCount: withData.length,
      daySpan: span,
    );
  }

  static const double _minutesPerDay = 24 * 60;

  static double _toAngle(int minutes) =>
      (minutes % _minutesPerDay) / _minutesPerDay * 2 * math.pi;

  static double _resultantLength(double meanSin, double meanCos) =>
      math.sqrt(meanSin * meanSin + meanCos * meanCos);

  static double? _mean(List<num> values) => values.isEmpty
      ? null
      : values.fold<double>(0, (sum, v) => sum + v) / values.length;

  static double? _median(List<num> values) {
    if (values.isEmpty) return null;
    final sorted = List<num>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Sample standard deviation (n−1). The nights we have are a sample of the
  /// user's sleep, not the population of it.
  static double? _sd(List<num> values) {
    if (values.length < 2) return null;
    final mean = _mean(values)!;
    final variance =
        values.fold<double>(0, (sum, v) => sum + math.pow(v - mean, 2)) /
        (values.length - 1);
    return math.sqrt(variance);
  }
}
