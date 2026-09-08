import 'sleep_provenance.dart';

/// One continuous sleep episode, from **one** provider.
///
/// This is the normalized unit both platforms are flattened into
/// (`docs/SLEEP_SYSTEM.md` §17). The two stores disagree structurally and the
/// disagreement stops here:
///
/// * **Health Connect** hands us real `SleepSessionRecord`s — a span, stages,
///   zone offsets. One record becomes one [SleepSession] almost verbatim.
/// * **HealthKit has no session type at all.** It stores a cloud of
///   overlapping interval samples, and a single night from an Apple Watch is
///   dozens of adjacent ones. `sleep_sessionizer.dart` stitches them; the
///   result is this.
///
/// Nothing above the data layer may know which of those two it was looking at.
class SleepSession {
  const SleepSession({
    required this.id,
    required this.startAt,
    required this.endAt,
    required this.startOffsetMinutes,
    required this.endOffsetMinutes,
    required this.provenance,
    this.tzId,
    this.inBedStartAt,
    this.inBedEndAt,
    this.stages = const [],
    this.interruptions = const [],
    this.supersedes,
  });

  final String id;

  /// **UTC instants, always.** Duration is computed from these and never from
  /// wall-clock arithmetic — a night spanning a DST change has a real length
  /// that differs from its clock-face difference by an hour, and 23:00→07:00
  /// across a spring-forward is seven hours, not eight. A wrong number that
  /// looks right is the worst kind.
  final DateTime startAt;
  final DateTime endAt;

  /// The local UTC offsets **as they were lived**, in minutes.
  ///
  /// Kept per-end rather than per-session because those two differ across a
  /// DST boundary — which is precisely how [spansDstChange] is detected. Held
  /// so a night slept in Tokyo renders in Tokyo time on a phone that has since
  /// flown home, instead of silently shifting three hours.
  final int startOffsetMinutes;
  final int endOffsetMinutes;

  /// IANA zone id when the platform supplied one (`Africa/Cairo`). Nullable:
  /// HealthKit does not give it, and a guess would be worse than a null.
  final String? tzId;

  /// The in-bed span, when the source distinguishes it from asleep.
  ///
  /// **Null means unknown, and stays null.** Defaulting it to [startAt] would
  /// silently make sleep efficiency 100% for every source that does not track
  /// time in bed, which is a fabricated number wearing a real number's clothes.
  final DateTime? inBedStartAt;
  final DateTime? inBedEndAt;

  /// Empty when the source has no staging. Not an error, and not something to
  /// fill in — an Apple Watch pre-watchOS 9, or a bare `asleepUnspecified`
  /// record, genuinely tells us *when* without telling us *what kind*.
  final List<SleepStageSegment> stages;

  /// Awake bouts inside the span, derived from runs of awake stage data at or
  /// above [minInterruptionMinutes].
  final List<SleepInterruption> interruptions;

  final SleepProvenance provenance;

  /// Set when a user edit replaced a measured record: the id of what it
  /// replaced. The superseded session is kept in the night's alternates —
  /// the user overrode it, we did not delete it.
  final String? supersedes;

  /// Shorter awake runs are normal sleep architecture, not interruptions worth
  /// showing. Five minutes is the threshold consumer trackers converge on.
  static const int minInterruptionMinutes = 5;

  /// Real elapsed time asleep-or-in-bed for this session, from the instants.
  Duration get duration => endAt.difference(startAt);

  /// Time actually asleep: [duration] less the awake bouts inside it.
  ///
  /// With no interruption data this equals [duration] — which is honest, since
  /// a source that reports no wake bouts is telling us it saw none, not that
  /// there were none. [SleepProvenance.completeness] carries that caveat.
  Duration get asleepDuration {
    final awake = interruptions.fold(
      Duration.zero,
      (sum, i) => sum + i.duration,
    );
    final net = duration - awake;
    return net.isNegative ? Duration.zero : net;
  }

  /// Time in bed, or null when the source does not distinguish it.
  Duration? get timeInBed {
    final start = inBedStartAt;
    final end = inBedEndAt;
    if (start == null || end == null) return null;
    final d = end.difference(start);
    return d.isNegative ? null : d;
  }

  /// Asleep ÷ in-bed, `0..1` — or **null when time in bed is unknown**.
  ///
  /// Never 1.0 as a stand-in. "100% efficient" and "we don't know" are
  /// different statements and the UI has to be able to tell them apart.
  double? get efficiency {
    final inBed = timeInBed;
    if (inBed == null || inBed.inSeconds <= 0) return null;
    final ratio = asleepDuration.inSeconds / inBed.inSeconds;
    return ratio.clamp(0.0, 1.0);
  }

  /// The instant halfway through the session — the chronobiological anchor for
  /// consistency. Sleep *midpoint* is the standard phase marker because it is
  /// robust to a night that simply ran long, in a way bedtime alone is not.
  DateTime get midpoint =>
      startAt.add(Duration(seconds: duration.inSeconds ~/ 2));

  /// Whether the local offset changed mid-session — a DST transition, or a
  /// flight. The UI annotates rather than leaving the reader to wonder why
  /// 23:00→07:00 reads as seven hours.
  bool get spansDstChange => startOffsetMinutes != endOffsetMinutes;

  /// Local wall-clock bedtime as minutes since midnight, in the offset that
  /// was in force when the session began.
  int get localBedtimeMinutes => _localMinutes(startAt, startOffsetMinutes);

  /// Local wall-clock wake time as minutes since midnight, in the offset in
  /// force when it ended.
  int get localWakeMinutes => _localMinutes(endAt, endOffsetMinutes);

  /// Local wall-clock midpoint as minutes since midnight. Interpolates the
  /// offset from the two ends so a DST-spanning night lands sensibly.
  int get localMidpointMinutes => _localMinutes(
    midpoint,
    (startOffsetMinutes + endOffsetMinutes) ~/ 2,
  );

  /// [startAt] rendered in its own recorded offset — what a clock on that
  /// wall said. For display only; never do arithmetic on it.
  DateTime get localStart => startAt.add(Duration(minutes: startOffsetMinutes));

  /// [endAt] rendered in its own recorded offset. Display only.
  DateTime get localEnd => endAt.add(Duration(minutes: endOffsetMinutes));

  bool get hasStages => stages.isNotEmpty;

  /// Total time in a given stage, or null when this session has no staging.
  Duration? durationInStage(SleepStage stage) {
    if (stages.isEmpty) return null;
    return stages
        .where((s) => s.stage == stage)
        .fold<Duration>(Duration.zero, (sum, s) => sum + s.duration);
  }

  SleepSession copyWith({
    String? id,
    List<SleepStageSegment>? stages,
    List<SleepInterruption>? interruptions,
    SleepProvenance? provenance,
    String? supersedes,
  }) => SleepSession(
    id: id ?? this.id,
    startAt: startAt,
    endAt: endAt,
    startOffsetMinutes: startOffsetMinutes,
    endOffsetMinutes: endOffsetMinutes,
    tzId: tzId,
    inBedStartAt: inBedStartAt,
    inBedEndAt: inBedEndAt,
    stages: stages ?? this.stages,
    interruptions: interruptions ?? this.interruptions,
    provenance: provenance ?? this.provenance,
    supersedes: supersedes ?? this.supersedes,
  );

  static int _localMinutes(DateTime utc, int offsetMinutes) {
    final local = utc.add(Duration(minutes: offsetMinutes));
    return local.hour * 60 + local.minute;
  }
}

/// A sleep stage, normalized across both platforms.
///
/// HealthKit's `asleepCore`/`asleepDeep`/`asleepREM` (iOS 16+) and Health
/// Connect's `STAGE_TYPE_LIGHT`/`DEEP`/`REM` describe the same thing under
/// different names; Apple's "core" and Google's "light" are the same stage.
/// [asleepUnspecified] is the honest landing place for a source that says
/// "asleep" without saying which kind — including every pre-iOS-16 sample.
///
/// Persisted by `name`; an id, not copy.
enum SleepStage {
  inBed,
  awake,
  asleepUnspecified,
  light,
  deep,
  rem,
  outOfBed;

  /// Whether this stage counts as being asleep. [inBed] and [outOfBed] are
  /// bed-occupancy states, not sleep states, and [awake] is explicitly not.
  bool get isAsleep =>
      this == SleepStage.asleepUnspecified ||
      this == SleepStage.light ||
      this == SleepStage.deep ||
      this == SleepStage.rem;
}

/// One stage run inside a session.
class SleepStageSegment {
  const SleepStageSegment({
    required this.startAt,
    required this.endAt,
    required this.stage,
  });

  /// UTC instants, as everywhere else.
  final DateTime startAt;
  final DateTime endAt;
  final SleepStage stage;

  Duration get duration => endAt.difference(startAt);
}

/// A wake bout inside a night — long enough to be worth showing, per
/// [SleepSession.minInterruptionMinutes].
class SleepInterruption {
  const SleepInterruption({required this.startAt, required this.endAt});

  final DateTime startAt;
  final DateTime endAt;

  Duration get duration => endAt.difference(startAt);
}
