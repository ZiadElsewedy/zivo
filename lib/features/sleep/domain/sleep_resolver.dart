import 'sleep_night.dart';
import 'sleep_provenance.dart';
import 'sleep_session.dart';
import 'sleep_targets.dart';

/// Sessions → nights. The conflict-resolution half of the pipeline, and the
/// place ZIVO decides which of several disagreeing sources gets to be "your
/// sleep last night". Pure, no I/O, no clock (`docs/SLEEP_SYSTEM.md` §12).
///
/// ## The rule that shapes everything else
///
/// **Choose, never merge.** Given an Apple Watch night and an Oura night that
/// disagree by half an hour, the tempting move is to average them. That
/// produces a night no device measured and no algorithm validated — a
/// fabricated number with two real numbers' credibility behind it. So one
/// candidate wins, the losers are kept as [SleepNight.alternates], and the UI
/// is able to show the disagreement rather than hide it.
abstract final class SleepResolver {
  /// Episodes at or above this length can be the night's main sleep; anything
  /// shorter is a nap however the window falls.
  static const Duration minMainSleep = Duration(hours: 3);

  /// Groups [sessions] into nights and resolves each one.
  ///
  /// [targets] is snapshotted onto every night produced — see
  /// [SleepNight.targets] for why a night keeps the goal that was live when it
  /// happened rather than pointing at today's.
  static List<SleepNight> resolve(
    List<SleepSession> sessions, {
    SleepTargets? targets,
    DateTime? updatedAt,
  }) {
    if (sessions.isEmpty) return const [];

    final byDay = <DateTime, List<SleepSession>>{};
    for (final session in sessions) {
      byDay.putIfAbsent(sleepDayOf(session), () => []).add(session);
    }

    final nights = <SleepNight>[
      for (final entry in byDay.entries)
        _resolveDay(
          entry.key,
          entry.value,
          targets: targets,
          updatedAt: updatedAt,
        ),
    ]..sort((a, b) => a.sleepDay.compareTo(b.sleepDay));

    return nights;
  }

  /// The **sleep-day** a session belongs to: the local date at the end of the
  /// noon-to-noon window its midpoint falls in.
  ///
  /// Noon-to-noon is the sleep-research convention, and it is what makes "the
  /// night of the 6th" mean the sleep you woke up from on the 6th — which is
  /// how people actually talk about their sleep. A midnight-to-midnight
  /// boundary would split every ordinary night in half and file the two halves
  /// under different dates.
  ///
  /// It has one consequence worth stating because it surprises people: a 3pm
  /// nap falls into *tomorrow's* window. Naps are stored and shown, and are
  /// excluded from v1 metrics, so the surprise is contained.
  ///
  /// The offset used is the one interpolated at the midpoint, so a night slept
  /// abroad is filed by the local date where it was slept.
  static DateTime sleepDayOf(SleepSession session) {
    final offset = Duration(
      minutes: (session.startOffsetMinutes + session.endOffsetMinutes) ~/ 2,
    );
    final localMidpoint = session.midpoint.add(offset);
    // Shift back twelve hours so the window [noon D-1, noon D) collapses onto
    // the date D, then take the calendar date.
    final shifted = localMidpoint.add(const Duration(hours: 12));
    return DateTime(shifted.year, shifted.month, shifted.day);
  }

  static SleepNight _resolveDay(
    DateTime sleepDay,
    List<SleepSession> sessions, {
    SleepTargets? targets,
    DateTime? updatedAt,
  }) {
    // A user edit is not a candidate among candidates — it is the user telling
    // us about their own sleep, which outranks every sensor by construction.
    final overrides = sessions.where((s) => s.supersedes != null).toList();
    if (overrides.isNotEmpty) {
      final chosen = overrides.reduce(
        (a, b) => a.provenance.ingestedAt.isAfter(b.provenance.ingestedAt)
            ? a
            : b,
      );
      return SleepNight(
        sleepDay: sleepDay,
        main: chosen,
        naps: const [],
        alternates: sessions.where((s) => s.id != chosen.id).toList(),
        resolution: SleepResolution.userOverride,
        targets: targets,
        updatedAt: updatedAt,
      );
    }

    // Naps first: an episode too short to be a night cannot be the night, and
    // letting a 40-minute afternoon sleep win an empty window would put "you
    // slept 40 minutes" on the day's hero number.
    final candidates =
        sessions.where((s) => s.duration >= minMainSleep).toList();
    final naps = sessions.where((s) => s.duration < minMainSleep).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));

    if (candidates.isEmpty) {
      return SleepNight(
        sleepDay: sleepDay,
        main: null,
        naps: naps,
        resolution: SleepResolution.none,
        targets: targets,
        updatedAt: updatedAt,
      );
    }

    // Longest first, then the ranking below. Two providers describing the same
    // night are ranked against each other; two genuinely separate episodes in
    // one window are ranked by which is the main sleep.
    final ranked = List<SleepSession>.from(candidates)..sort(_compare);
    final chosen = ranked.first;
    final alternates = ranked.skip(1).toList();

    return SleepNight(
      sleepDay: sleepDay,
      main: chosen,
      naps: naps,
      alternates: alternates,
      resolution: _explain(chosen, alternates),
      targets: targets,
      updatedAt: updatedAt,
    );
  }

  /// The ranking, in priority order (`docs/SLEEP_SYSTEM.md` §12.3):
  ///
  /// 1. **Method tier** — a measurement beats a typed entry beats an estimate.
  ///    [SleepMethod]'s declaration order *is* this ranking.
  /// 2. **Coverage** — of two wearable nights, the one actually backed by
  ///    samples across its span.
  /// 3. **Stage richness** — graded sleep beats an undifferentiated block.
  /// 4. **Duration** — the longer episode is the main sleep.
  /// 5. **Ingest recency** — a stable tiebreak so resolution is deterministic
  ///    and a re-sync cannot silently reshuffle a settled night.
  static int _compare(SleepSession a, SleepSession b) {
    final byMethod = a.provenance.method.index.compareTo(
      b.provenance.method.index,
    );
    if (byMethod != 0) return byMethod;

    final byCoverage = b.provenance.completeness.compareTo(
      a.provenance.completeness,
    );
    if (byCoverage != 0) return byCoverage;

    final byDetail = _gradedStageCount(b).compareTo(_gradedStageCount(a));
    if (byDetail != 0) return byDetail;

    final byLength = b.duration.compareTo(a.duration);
    if (byLength != 0) return byLength;

    return b.provenance.ingestedAt.compareTo(a.provenance.ingestedAt);
  }

  /// Why [chosen] won, for the "why this number?" sheet. Answers the question
  /// the user would actually ask, which is never "what was your sort key".
  static SleepResolution _explain(
    SleepSession chosen,
    List<SleepSession> alternates,
  ) {
    if (alternates.isEmpty) return SleepResolution.soleSource;

    final runnerUp = alternates.first;
    if (chosen.provenance.method != runnerUp.provenance.method) {
      return SleepResolution.bestMethod;
    }
    if (chosen.provenance.completeness != runnerUp.provenance.completeness) {
      return SleepResolution.bestCoverage;
    }
    if (_gradedStageCount(chosen) != _gradedStageCount(runnerUp)) {
      return SleepResolution.richestDetail;
    }
    return SleepResolution.bestCoverage;
  }

  /// Count of *graded* stage segments — light/deep/REM. `asleepUnspecified`
  /// deliberately does not count: a source saying "asleep, kind unknown" is
  /// not offering detail, and counting it would let a pre-watchOS-9 night
  /// outrank a properly staged one.
  static int _gradedStageCount(SleepSession session) => session.stages
      .where(
        (s) =>
            s.stage == SleepStage.light ||
            s.stage == SleepStage.deep ||
            s.stage == SleepStage.rem,
      )
      .length;
}
