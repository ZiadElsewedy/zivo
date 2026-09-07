import 'sleep_provenance.dart';
import 'sleep_session.dart';
import 'sleep_source.dart';

/// Raw platform records → [SleepSession]s. Pure, no I/O, no clock.
///
/// This is the algorithm HealthKit forces on us. Apple stores sleep as a cloud
/// of overlapping interval samples with no session type, so one night from an
/// Apple Watch arrives as dozens of adjacent fragments — and if the user also
/// has Oura, and once typed a night in by hand, three clouds overlap in the
/// same hours (`docs/SLEEP_SYSTEM.md` §3, §12). Health Connect has no such
/// problem; its records arrive [RawSleepRecord.preSessionized] and pass
/// through untouched.
///
/// Everything here is deterministic and side-effect free so it can be tested
/// against fixtures rather than against a phone.
abstract final class SleepSessionizer {
  /// Fragments from the same provider join into one session when the gap
  /// between them is at most this long.
  ///
  /// Sixty minutes is the sleep-research convention for a wake bout that ends
  /// a sleep period rather than interrupting it. Shorter, and a normal 3am
  /// bathroom trip splits one night into two; longer, and an evening nap gets
  /// welded onto the night that follows it.
  static const Duration maxFragmentGap = Duration(minutes: 60);

  /// Sessions shorter than this are dropped outright — a stray four-minute
  /// `inBed` sample is noise, not a nap, and letting it become a session gives
  /// the resolver a candidate that can only mislead.
  static const Duration minSessionLength = Duration(minutes: 20);

  /// Groups [records] into sessions, one provider at a time.
  ///
  /// Providers are never mixed: a session is one source's account of one
  /// period. Reconciling *between* providers is the resolver's job, and
  /// keeping the two steps apart is what makes it possible to show a user two
  /// sources disagreeing instead of a single blended number neither of them
  /// reported.
  static List<SleepSession> sessionize(
    List<RawSleepRecord> records, {
    required DateTime ingestedAt,
  }) {
    if (records.isEmpty) return const [];

    final byProvider = <String, List<RawSleepRecord>>{};
    for (final record in records) {
      byProvider.putIfAbsent(record.providerId, () => []).add(record);
    }

    final sessions = <SleepSession>[];
    for (final entry in byProvider.entries) {
      final provider = List<RawSleepRecord>.from(entry.value)
        ..sort((a, b) => a.startAt.compareTo(b.startAt));

      // Health Connect already did this work; taking its sessions apart to
      // re-derive them would only introduce our own errors.
      final preSessionized = provider.where((r) => r.preSessionized);
      for (final record in preSessionized) {
        final session = _fromSessionRecord(record, ingestedAt: ingestedAt);
        if (session != null) sessions.add(session);
      }

      final samples = provider.where((r) => !r.preSessionized).toList();
      for (final group in _groupByGap(samples)) {
        final session = _fromSamples(group, ingestedAt: ingestedAt);
        if (session != null) sessions.add(session);
      }
    }

    sessions.sort((a, b) => a.startAt.compareTo(b.startAt));
    return sessions;
  }

  /// Splits time-ordered samples wherever the gap exceeds [maxFragmentGap].
  ///
  /// Overlap counts as no gap at all, which matters because HealthKit samples
  /// routinely overlap: an `inBed` sample spans the whole night while the
  /// `asleepCore` samples inside it come and go.
  static List<List<RawSleepRecord>> _groupByGap(List<RawSleepRecord> samples) {
    if (samples.isEmpty) return const [];
    final groups = <List<RawSleepRecord>>[];
    var current = <RawSleepRecord>[samples.first];
    var runningEnd = samples.first.endAt;

    for (final sample in samples.skip(1)) {
      final gap = sample.startAt.difference(runningEnd);
      if (gap > maxFragmentGap) {
        groups.add(current);
        current = [sample];
        runningEnd = sample.endAt;
        continue;
      }
      current.add(sample);
      if (sample.endAt.isAfter(runningEnd)) runningEnd = sample.endAt;
    }
    groups.add(current);
    return groups;
  }

  /// One Health Connect session → one [SleepSession], verbatim.
  static SleepSession? _fromSessionRecord(
    RawSleepRecord record, {
    required DateTime ingestedAt,
  }) {
    if (record.duration < minSessionLength) return null;

    final stages = List<SleepStageSegment>.from(record.stages)
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final interruptions = _interruptionsFrom(stages);
    final inBed = _inBedSpanFrom(stages, fallbackStart: record.startAt,
        fallbackEnd: record.endAt);

    // The session record is one contiguous span, so it covers itself. Stage
    // gaps inside it are unstaged sleep, not missing sleep.
    const completeness = 1.0;

    final method = methodFor(
      providerId: record.providerId,
      deviceKind: record.deviceKind,
      recordingMethod: record.recordingMethod,
    );

    return SleepSession(
      id: record.id,
      startAt: record.startAt,
      endAt: record.endAt,
      startOffsetMinutes: record.startOffsetMinutes,
      endOffsetMinutes: record.endOffsetMinutes,
      tzId: record.tzId,
      inBedStartAt: inBed?.$1,
      inBedEndAt: inBed?.$2,
      stages: stages,
      interruptions: interruptions,
      provenance: SleepProvenance(
        method: method,
        providerId: record.providerId,
        providerName: record.providerName,
        deviceKind: record.deviceKind,
        recordingMethod: record.recordingMethod,
        confidence: confidenceFor(
          method: method,
          hasStages: stages.any((s) => s.stage.isAsleep),
          completeness: completeness,
          sourceCount: 1,
        ),
        completeness: completeness,
        rawRefs: [record.id],
        ingestedAt: ingestedAt,
      ),
    );
  }

  /// A group of HealthKit fragments → one [SleepSession].
  static SleepSession? _fromSamples(
    List<RawSleepRecord> group, {
    required DateTime ingestedAt,
  }) {
    if (group.isEmpty) return null;

    final asleep = group.where((r) => r.stage.isAsleep).toList();
    final inBedSamples =
        group.where((r) => r.stage == SleepStage.inBed).toList();

    // The session's span is the ASLEEP data, not the in-bed data. Reading a
    // book for an hour before sleeping is time in bed, and counting it as
    // sleep would inflate every night for every user who tracks both.
    //
    // A group with only in-bed samples is still worth keeping — it is a real
    // record of a real period — but it is explicitly unstaged, and the sleep
    // span then honestly equals the in-bed span because that is all we know.
    final spanning = asleep.isNotEmpty ? asleep : group;
    final startAt = spanning
        .map((r) => r.startAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final endAt =
        spanning.map((r) => r.endAt).reduce((a, b) => a.isAfter(b) ? a : b);
    if (endAt.difference(startAt) < minSessionLength) return null;

    final stages = <SleepStageSegment>[
      for (final r in group)
        if (r.stage != SleepStage.inBed && r.stage != SleepStage.outOfBed)
          SleepStageSegment(startAt: r.startAt, endAt: r.endAt, stage: r.stage),
    ]..sort((a, b) => a.startAt.compareTo(b.startAt));

    final inBedStart = inBedSamples.isEmpty
        ? null
        : inBedSamples.map((r) => r.startAt).reduce((a, b) => a.isBefore(b) ? a : b);
    final inBedEnd = inBedSamples.isEmpty
        ? null
        : inBedSamples.map((r) => r.endAt).reduce((a, b) => a.isAfter(b) ? a : b);

    final completeness = _coverage(
      segments: [
        for (final r in spanning) (r.startAt, r.endAt),
      ],
      spanStart: startAt,
      spanEnd: endAt,
    );

    final anchor = spanning.first;
    final method = methodFor(
      providerId: anchor.providerId,
      deviceKind: anchor.deviceKind,
      recordingMethod: anchor.recordingMethod,
    );

    // Stage detail means *graded* sleep. A pile of `asleepUnspecified` samples
    // is a source saying "asleep, don't know which kind", and treating that as
    // stage detail would promote a pre-watchOS-9 night to high confidence.
    final hasGradedStages = stages.any(
      (s) =>
          s.stage == SleepStage.light ||
          s.stage == SleepStage.deep ||
          s.stage == SleepStage.rem,
    );

    return SleepSession(
      id: '${anchor.providerId}:${startAt.toUtc().toIso8601String()}',
      startAt: startAt,
      endAt: endAt,
      startOffsetMinutes: anchor.startOffsetMinutes,
      endOffsetMinutes: group.last.endOffsetMinutes,
      tzId: anchor.tzId,
      inBedStartAt: inBedStart,
      inBedEndAt: inBedEnd,
      stages: stages,
      interruptions: _interruptionsFrom(stages),
      provenance: SleepProvenance(
        method: method,
        providerId: anchor.providerId,
        providerName: anchor.providerName,
        deviceKind: anchor.deviceKind,
        recordingMethod: anchor.recordingMethod,
        confidence: confidenceFor(
          method: method,
          hasStages: hasGradedStages,
          completeness: completeness,
          sourceCount: 1,
        ),
        completeness: completeness,
        rawRefs: [for (final r in group) r.id],
        ingestedAt: ingestedAt,
      ),
    );
  }

  /// Awake runs at or above [SleepSession.minInterruptionMinutes], merged
  /// where they touch. Shorter stirrings are ordinary sleep architecture and
  /// showing them would make every night look broken.
  static List<SleepInterruption> _interruptionsFrom(
    List<SleepStageSegment> stages,
  ) {
    final awake = stages.where((s) => s.stage == SleepStage.awake).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    if (awake.isEmpty) return const [];

    final merged = <SleepInterruption>[];
    var start = awake.first.startAt;
    var end = awake.first.endAt;
    for (final segment in awake.skip(1)) {
      if (!segment.startAt.isAfter(end)) {
        if (segment.endAt.isAfter(end)) end = segment.endAt;
        continue;
      }
      merged.add(SleepInterruption(startAt: start, endAt: end));
      start = segment.startAt;
      end = segment.endAt;
    }
    merged.add(SleepInterruption(startAt: start, endAt: end));

    return merged
        .where(
          (i) => i.duration.inMinutes >= SleepSession.minInterruptionMinutes,
        )
        .toList(growable: false);
  }

  /// The in-bed span implied by bed-occupancy stages, or null when the source
  /// tracked none. Falls back to nothing rather than to the sleep span —
  /// see [SleepSession.inBedStartAt] for why a null here is load-bearing.
  static (DateTime, DateTime)? _inBedSpanFrom(
    List<SleepStageSegment> stages, {
    required DateTime fallbackStart,
    required DateTime fallbackEnd,
  }) {
    final inBed =
        stages.where((s) => s.stage == SleepStage.inBed).toList();
    if (inBed.isEmpty) return null;
    final start = inBed
        .map((s) => s.startAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final end =
        inBed.map((s) => s.endAt).reduce((a, b) => a.isAfter(b) ? a : b);
    return (
      start.isBefore(fallbackStart) ? start : fallbackStart,
      end.isAfter(fallbackEnd) ? end : fallbackEnd,
    );
  }

  /// Fraction of `[spanStart, spanEnd]` actually covered by [segments], with
  /// overlaps counted once.
  ///
  /// This is what [SleepProvenance.completeness] reports, and it is the guard
  /// against a sparse cloud: a source writing half-hour samples every
  /// seventy-five minutes stitches into one five-and-a-half-hour session under
  /// [maxFragmentGap], and `endAt - startAt` alone would present that as five
  /// and a half hours of measured sleep when under half of it is backed by a
  /// sample. (Samples further apart than [maxFragmentGap] split instead, which
  /// is the other half of the same guard.)
  static double _coverage({
    required List<(DateTime, DateTime)> segments,
    required DateTime spanStart,
    required DateTime spanEnd,
  }) {
    final total = spanEnd.difference(spanStart).inSeconds;
    if (total <= 0) return 0;

    final sorted = List<(DateTime, DateTime)>.from(segments)
      ..sort((a, b) => a.$1.compareTo(b.$1));
    var covered = 0;
    DateTime? runStart;
    DateTime? runEnd;
    for (final (start, end) in sorted) {
      if (runStart == null || runEnd == null) {
        runStart = start;
        runEnd = end;
        continue;
      }
      if (start.isAfter(runEnd)) {
        covered += runEnd.difference(runStart).inSeconds;
        runStart = start;
        runEnd = end;
        continue;
      }
      if (end.isAfter(runEnd)) runEnd = end;
    }
    if (runStart != null && runEnd != null) {
      covered += runEnd.difference(runStart).inSeconds;
    }

    return (covered / total).clamp(0.0, 1.0);
  }
}
