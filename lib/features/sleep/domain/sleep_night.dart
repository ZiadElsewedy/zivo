import 'sleep_provenance.dart';
import 'sleep_session.dart';
import 'sleep_targets.dart';

/// One **sleep-day**: everything we know about the sleep the user woke up from
/// on a given local date. The unit the UI renders and the unit Firestore
/// stores, one document per day keyed `yyyy-MM-dd`.
///
/// A night is not simply "the session we found". Several providers can each
/// have an opinion about the same hours — an Apple Watch, Oura, and a time the
/// user typed into Health last Tuesday — and `sleep_resolver.dart` picks one
/// ([main]) while keeping the rest ([alternates]). It never averages them:
/// two providers' intervals spliced together produce a night that no device
/// measured and no algorithm validated, which is fabrication with extra steps.
class SleepNight {
  const SleepNight({
    required this.sleepDay,
    required this.main,
    this.naps = const [],
    this.alternates = const [],
    this.resolution = SleepResolution.none,
    this.targets,
    this.createdAt,
    this.updatedAt,
  });

  /// The local calendar date the user woke up on — the document id.
  ///
  /// A date, not an instant: it is a label for a window, and the window's own
  /// definition lives in `sleep_sessionizer.dart` (noon-to-noon local).
  /// Deterministic ids are also how two of the user's phones syncing the same
  /// night converge on one document instead of racing to create two.
  final DateTime sleepDay;

  /// The chosen main sleep period. **Null means we have nothing** — which is a
  /// state the UI renders in words, never as a zero.
  final SleepSession? main;

  /// Shorter episodes in the same window. Stored and shown; excluded from v1
  /// metrics (`docs/SLEEP_SYSTEM.md` §12).
  final List<SleepSession> naps;

  /// Candidates that lost to [main], kept rather than discarded. They are what
  /// lets the night's detail sheet say "Oura and Apple Watch disagree by
  /// 34 min — showing Oura", and what a user edit falls back to.
  final List<SleepSession> alternates;

  /// Why [main] won. Rendered in the "why this number?" sheet, which is what
  /// turns "trust us" into a receipt.
  final SleepResolution resolution;

  /// The targets **as they stood on this day**, snapshotted.
  ///
  /// Not a live reference to the user's current targets: changing your goal in
  /// March should not retroactively rewrite whether you hit it in January.
  final SleepTargets? targets;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// An empty night — no data, and honest about it.
  factory SleepNight.empty(DateTime sleepDay, {SleepTargets? targets}) =>
      SleepNight(sleepDay: sleepDay, main: null, targets: targets);

  bool get hasData => main != null;

  Duration? get duration => main?.asleepDuration;

  SleepMethod? get method => main?.provenance.method;

  SleepConfidence? get confidence => main?.provenance.confidence;

  /// Whether another provider also covered this night. Drives the disagreement
  /// row in the detail sheet.
  bool get hasAlternates => alternates.isNotEmpty;

  /// The largest gap between [main]'s bedtime and any alternate's, or null
  /// when nothing disagrees. Reported in the UI so the user can see the size
  /// of the uncertainty rather than being told to ignore it.
  Duration? get largestDisagreement {
    final chosen = main;
    if (chosen == null || alternates.isEmpty) return null;
    var worst = Duration.zero;
    for (final other in alternates) {
      final delta = (other.startAt.difference(chosen.startAt)).abs();
      if (delta > worst) worst = delta;
    }
    return worst == Duration.zero ? null : worst;
  }

  /// Minutes [main] began after its target bedtime — negative for early.
  /// Null when we have no night or no target.
  ///
  /// Wraps across midnight: a target of 23:00 and a bedtime of 00:30 is 90
  /// minutes late, not 1350 minutes early. Without the wrap every night that
  /// crosses midnight reports a nonsense figure, which is the single most
  /// common bug in this class of feature.
  int? get bedtimeDeltaMinutes {
    final chosen = main;
    final t = targets;
    if (chosen == null || t == null) return null;
    return signedClockDelta(chosen.localBedtimeMinutes, t.bedtimeMinutes);
  }

  /// Minutes [main] ended after its target wake time — negative for early.
  int? get wakeDeltaMinutes {
    final chosen = main;
    final t = targets;
    if (chosen == null || t == null) return null;
    return signedClockDelta(chosen.localWakeMinutes, t.wakeMinutes);
  }

  /// Minutes slept beyond the target duration — negative for short.
  int? get durationDeltaMinutes {
    final chosen = main;
    final t = targets;
    if (chosen == null || t == null) return null;
    return chosen.asleepDuration.inMinutes - t.durationMinutes;
  }

  /// Whether bedtime landed inside [SleepTargets.adherenceToleranceMinutes].
  /// Null — not false — when there is nothing to judge.
  bool? get metBedtimeTarget {
    final delta = bedtimeDeltaMinutes;
    if (delta == null) return null;
    return delta.abs() <= SleepTargets.adherenceToleranceMinutes;
  }

  SleepNight copyWith({
    SleepSession? main,
    List<SleepSession>? naps,
    List<SleepSession>? alternates,
    SleepResolution? resolution,
    SleepTargets? targets,
    DateTime? updatedAt,
    bool clearMain = false,
  }) => SleepNight(
    sleepDay: sleepDay,
    main: clearMain ? null : (main ?? this.main),
    naps: naps ?? this.naps,
    alternates: alternates ?? this.alternates,
    resolution: resolution ?? this.resolution,
    targets: targets ?? this.targets,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Why the resolver chose the session it chose.
///
/// Persisted by `name`; an id, not copy — the sentences live in
/// `presentation/sleep_labels.dart`.
enum SleepResolution {
  /// Nothing at all for this night.
  none,

  /// Exactly one candidate — no contest to explain.
  soleSource,

  /// Several candidates; this one had the better method tier.
  bestMethod,

  /// Same tier, but this one covered more of its own span.
  bestCoverage,

  /// Same tier and coverage; this one carried stage detail.
  richestDetail,

  /// The user edited or logged this night, and a user's own statement about
  /// their own sleep outranks everything.
  userOverride,
}

/// Signed difference between two clock times, in minutes, taking the **short
/// way round** a 24-hour dial: the result is always in `(-720, 720]`.
///
/// Positive means [actual] is later than [target]. Shared by bedtime and wake
/// comparisons, both of which straddle midnight routinely.
int signedClockDelta(int actualMinutes, int targetMinutes) {
  const day = 24 * 60;
  var delta = (actualMinutes - targetMinutes) % day;
  if (delta > day ~/ 2) delta -= day;
  if (delta <= -day ~/ 2) delta += day;
  return delta;
}
