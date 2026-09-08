import 'sleep_metrics.dart';
import 'sleep_night.dart';
import 'sleep_session.dart';

/// **Sleep stages, made presentable — or refused.**
///
/// The pipeline has carried staging since the first commit: the sessionizer
/// normalises Apple's `asleepCore`/`asleepDeep`/`asleepREM` and Health
/// Connect's `LIGHT`/`DEEP`/`REM` onto one [SleepStage] enum, the resolver
/// *ranks on* stage richness, and the codec persists every segment. Nothing
/// ever drew them. This is the missing half: the arithmetic that turns a list
/// of segments into the four figures a screen can show, computed once so the
/// daily card, the night sheet and the weekly page cannot disagree.
///
/// ## What it refuses to produce
///
/// [SleepStageBreakdown.forSession] returns **null** far more readily than a
/// naive sum would, and every one of those refusals is the feature's one rule
/// applied to a new number:
///
/// * **No graded stages, no breakdown.** A night of `asleepUnspecified` is a
///   source saying "asleep, kind unknown" — an Apple Watch before watchOS 9,
///   or a bare Health Connect session. Rendering that as "100% light sleep"
///   would invent the exact detail the source declined to give.
/// * **Segments that do not reconcile with the night are discarded.** If the
///   staged time covers less than [_minCoverage] of the session, the staging
///   is a fragment of the night rather than an account of it, and a pie chart
///   over a fragment is a chart about nothing.
/// * **Overlaps are unioned, never summed.** HealthKit hands back overlapping
///   interval samples as a matter of course; adding their lengths yields a
///   night with nine hours of sleep inside an eight-hour session.
class SleepStageBreakdown {
  const SleepStageBreakdown({
    required this.light,
    required this.deep,
    required this.rem,
    required this.awake,
    required this.unspecified,
    required this.stagedTotal,
  });

  final Duration light;
  final Duration deep;
  final Duration rem;

  /// Awake time inside the night's span. Shown, not hidden: it is what makes
  /// the other three add up to less than the night.
  final Duration awake;

  /// Asleep, kind unknown. Present when a source stages *part* of a night and
  /// leaves the rest undifferentiated — it is the honest remainder rather
  /// than time silently attributed to light sleep.
  final Duration unspecified;

  /// Everything above, unioned — the span the breakdown actually accounts for.
  final Duration stagedTotal;

  /// Staged time excluding awake: the denominator for the three sleep shares.
  Duration get asleepTotal => light + deep + rem + unspecified;

  /// A stage's share of [asleepTotal], `0..1`. Null when there is no asleep
  /// time to take a share of.
  double? shareOf(SleepStage stage) {
    final total = asleepTotal.inSeconds;
    if (total <= 0) return null;
    final part = switch (stage) {
      SleepStage.light => light,
      SleepStage.deep => deep,
      SleepStage.rem => rem,
      SleepStage.awake => awake,
      _ => unspecified,
    };
    return (part.inSeconds / total).clamp(0.0, 1.0);
  }

  /// The three graded stages in the order sleep is conventionally reported —
  /// deep, REM, light — paired with their durations. Stages with no time are
  /// dropped: a night with no recorded REM should not render an empty REM
  /// row, because zero REM is a clinical claim and absence of a segment is not
  /// evidence for it.
  List<(SleepStage, Duration)> get gradedParts => [
    if (deep > Duration.zero) (SleepStage.deep, deep),
    if (rem > Duration.zero) (SleepStage.rem, rem),
    if (light > Duration.zero) (SleepStage.light, light),
    if (unspecified > Duration.zero)
      (SleepStage.asleepUnspecified, unspecified),
  ];

  /// The staged time must cover at least this much of the session before the
  /// breakdown describes the night rather than a slice of it.
  static const double _minCoverage = 0.6;

  /// The breakdown for [session], or **null** when the source did not stage it
  /// well enough to describe. See the class doc for the three refusals.
  static SleepStageBreakdown? forSession(SleepSession session) {
    if (session.stages.isEmpty) return null;

    final spanStart = session.startAt;
    final spanEnd = session.endAt;
    final spanSeconds = spanEnd.difference(spanStart).inSeconds;
    if (spanSeconds <= 0) return null;

    final byStage = <SleepStage, List<(DateTime, DateTime)>>{};
    for (final segment in session.stages) {
      // Bed-occupancy states are not sleep states. `inBed` routinely spans the
      // whole night in parallel with the real stages, and counting it would
      // double every figure here.
      if (segment.stage == SleepStage.inBed ||
          segment.stage == SleepStage.outOfBed) {
        continue;
      }
      final start = segment.startAt.isBefore(spanStart)
          ? spanStart
          : segment.startAt;
      final end = segment.endAt.isAfter(spanEnd) ? spanEnd : segment.endAt;
      if (!end.isAfter(start)) continue;
      byStage.putIfAbsent(segment.stage, () => []).add((start, end));
    }

    final light = _union(byStage[SleepStage.light]);
    final deep = _union(byStage[SleepStage.deep]);
    final rem = _union(byStage[SleepStage.rem]);
    final awake = _union(byStage[SleepStage.awake]);
    final unspecified = _union(byStage[SleepStage.asleepUnspecified]);

    // Graded staging is the whole point. Without light/deep/REM there is
    // nothing here a user could not already read off the duration.
    if (light + deep + rem == Duration.zero) return null;

    final staged = light + deep + rem + awake + unspecified;
    if (staged.inSeconds / spanSeconds < _minCoverage) return null;

    return SleepStageBreakdown(
      light: light,
      deep: deep,
      rem: rem,
      awake: awake,
      unspecified: unspecified,
      stagedTotal: staged,
    );
  }

  /// Total length of [segments] with overlaps counted once. The same
  /// sweep-line the sessionizer uses for coverage, and for the same reason:
  /// overlapping samples are normal input, not a fault to be summed through.
  static Duration _union(List<(DateTime, DateTime)>? segments) {
    if (segments == null || segments.isEmpty) return Duration.zero;
    final sorted = List<(DateTime, DateTime)>.from(segments)
      ..sort((a, b) => a.$1.compareTo(b.$1));

    var covered = 0;
    var runStart = sorted.first.$1;
    var runEnd = sorted.first.$2;
    for (final (start, end) in sorted.skip(1)) {
      if (start.isAfter(runEnd)) {
        covered += runEnd.difference(runStart).inSeconds;
        runStart = start;
        runEnd = end;
        continue;
      }
      if (end.isAfter(runEnd)) runEnd = end;
    }
    covered += runEnd.difference(runStart).inSeconds;
    return Duration(seconds: covered);
  }
}

/// Stage shares averaged over a window, for the weekly view.
///
/// Gated like every other window figure: below
/// [SleepGates.minNightsForAverage] staged nights this is not produced at all,
/// so a single well-staged night in an otherwise bare week cannot present
/// itself as "your sleep composition".
class SleepStageAverages {
  const SleepStageAverages({
    required this.nightsWithStages,
    required this.meanLight,
    required this.meanDeep,
    required this.meanRem,
  });

  /// How many nights in the window carried a usable breakdown. Travels with
  /// the figures because "your deep sleep" over three staged nights out of
  /// seven is a different claim from over seven.
  final int nightsWithStages;

  /// Mean nightly time in each graded stage.
  final Duration meanLight;
  final Duration meanDeep;
  final Duration meanRem;

  Duration get meanAsleep => meanLight + meanDeep + meanRem;

  double? shareOf(SleepStage stage) {
    final total = meanAsleep.inSeconds;
    if (total <= 0) return null;
    final part = switch (stage) {
      SleepStage.deep => meanDeep,
      SleepStage.rem => meanRem,
      _ => meanLight,
    };
    return (part.inSeconds / total).clamp(0.0, 1.0);
  }

  /// Averages across [nights], or null when too few of them are staged.
  static SleepStageAverages? forWindow(List<SleepNight> nights) {
    final breakdowns = <SleepStageBreakdown>[
      for (final night in nights)
        if (night.main != null) ?SleepStageBreakdown.forSession(night.main!),
    ];
    if (breakdowns.length < SleepGates.minNightsForAverage) return null;

    Duration mean(Duration Function(SleepStageBreakdown) pick) => Duration(
      seconds:
          breakdowns.fold<int>(0, (sum, b) => sum + pick(b).inSeconds) ~/
          breakdowns.length,
    );

    return SleepStageAverages(
      nightsWithStages: breakdowns.length,
      meanLight: mean((b) => b.light),
      meanDeep: mean((b) => b.deep),
      meanRem: mean((b) => b.rem),
    );
  }
}
