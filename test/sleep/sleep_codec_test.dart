import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/sleep/data/sleep_night_codec.dart';
import 'package:zivo/features/sleep/domain/sleep_night.dart';
import 'package:zivo/features/sleep/domain/sleep_provenance.dart';
import 'package:zivo/features/sleep/domain/sleep_repository.dart';
import 'package:zivo/features/sleep/domain/sleep_session.dart';
import 'package:zivo/features/sleep/domain/sleep_targets.dart';

/// Cover for sleep's durability boundary. A night written today has to survive
/// every build that comes after it, and the decoder's fallbacks have to
/// **under**-claim rather than over-claim when it meets something it does not
/// understand.
void main() {
  final start = DateTime.utc(2026, 9, 6, 23, 47);
  final end = DateTime.utc(2026, 9, 7, 7, 12);

  final session = SleepSession(
    id: 'com.apple.health:2026-09-06T23:47:00Z',
    startAt: start,
    endAt: end,
    startOffsetMinutes: 180,
    endOffsetMinutes: 180,
    tzId: 'Africa/Cairo',
    inBedStartAt: start.subtract(const Duration(minutes: 20)),
    inBedEndAt: end,
    stages: [
      SleepStageSegment(
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        stage: SleepStage.light,
      ),
      SleepStageSegment(
        startAt: start.add(const Duration(hours: 2)),
        endAt: start.add(const Duration(hours: 3)),
        stage: SleepStage.deep,
      ),
    ],
    interruptions: [
      SleepInterruption(
        startAt: start.add(const Duration(hours: 4)),
        endAt: start.add(const Duration(hours: 4, minutes: 12)),
      ),
    ],
    provenance: SleepProvenance(
      method: SleepMethod.measuredWearable,
      providerId: 'com.apple.health',
      providerName: 'Apple Health',
      deviceKind: SleepDeviceKind.watch,
      recordingMethod: SleepRecordingMethod.automatic,
      confidence: SleepConfidence.high,
      completeness: 0.97,
      rawRefs: const ['uuid-a', 'uuid-b'],
      ingestedAt: DateTime.utc(2026, 9, 7, 8),
    ),
  );

  test('document ids are the sleep-day, so a re-sync converges', () {
    expect(SleepNightCodec.docId(DateTime(2026, 9, 7)), '2026-09-07');
    expect(SleepNightCodec.docId(DateTime(2026, 12, 31)), '2026-12-31');
    expect(SleepNightCodec.sleepDayFromId('2026-09-07'), DateTime(2026, 9, 7));
    expect(SleepNightCodec.sleepDayFromId('nonsense'), isNull);
  });

  test('a night survives a full round trip', () {
    final night = SleepNight(
      sleepDay: DateTime(2026, 9, 7),
      main: session,
      alternates: [session.copyWith(id: 'com.ouraring.oura:x')],
      resolution: SleepResolution.bestMethod,
      targets: SleepTargets.defaults,
    );

    final decoded = SleepNightCodec.decodeNight(
      '2026-09-07',
      SleepNightCodec.encodeNight(night),
    );

    expect(decoded.sleepDay, DateTime(2026, 9, 7));
    expect(decoded.resolution, SleepResolution.bestMethod);
    expect(decoded.alternates, hasLength(1));
    expect(decoded.targets!.durationMinutes, 480);

    final main = decoded.main!;
    expect(main.startAt, start);
    expect(main.endAt, end);
    expect(main.startOffsetMinutes, 180);
    expect(main.tzId, 'Africa/Cairo');
    expect(main.stages, hasLength(2));
    expect(main.stages.first.stage, SleepStage.light);
    expect(main.interruptions, hasLength(1));
    expect(main.provenance.method, SleepMethod.measuredWearable);
    expect(main.provenance.confidence, SleepConfidence.high);
    expect(main.provenance.completeness, closeTo(0.97, 0.0001));
    expect(main.provenance.rawRefs, ['uuid-a', 'uuid-b']);
    expect(main.asleepDuration, main.duration - const Duration(minutes: 12));
  });

  test('an unknown time in bed decodes back to null, not to a default', () {
    final bare = SleepSession(
      id: 'x',
      startAt: start,
      endAt: end,
      startOffsetMinutes: 0,
      endOffsetMinutes: 0,
      provenance: SleepProvenance.manual(
        ingestedAt: DateTime.utc(2026, 9, 7),
        providerName: 'You',
      ),
    );

    final decoded = SleepNightCodec.decodeSession(
      SleepNightCodec.encodeSession(bare),
    )!;

    expect(decoded.inBedStartAt, isNull);
    expect(decoded.timeInBed, isNull);
    expect(decoded.efficiency, isNull);
  });

  test('an unreadable provenance decodes to the most cautious values', () {
    // A document from a newer build naming a method this one has never heard
    // of must not be promoted. Under-claiming is the only safe direction.
    final decoded = SleepNightCodec.decodeProvenance({
      'method': 'measuredByTelepathy',
      'confidence': 'perfect',
      'deviceKind': 'monocle',
      'recordingMethod': 'divination',
    });

    expect(decoded.method, SleepMethod.platformDerived);
    expect(decoded.confidence, SleepConfidence.low);
    expect(decoded.deviceKind, SleepDeviceKind.unknown);
    expect(decoded.recordingMethod, SleepRecordingMethod.unknown);
    expect(decoded.completeness, 0);
  });

  test('a night with no main sleep round-trips as empty, not as zero', () {
    final decoded = SleepNightCodec.decodeNight(
      '2026-09-07',
      SleepNightCodec.encodeNight(SleepNight.empty(DateTime(2026, 9, 7))),
    );

    expect(decoded.hasData, isFalse);
    expect(decoded.main, isNull);
    expect(decoded.duration, isNull);
  });

  test('a mark round-trips with the offset it was taken in', () {
    final mark = SleepMark(
      id: 'open',
      atUtc: DateTime.utc(2026, 9, 6, 21),
      offsetMinutes: 180,
      note: 'early one',
    );

    final decoded = SleepNightCodec.decodeMarkOrNull(
      SleepNightCodec.encodeMark(mark),
    )!;

    expect(decoded.atUtc, mark.atUtc);
    expect(decoded.offsetMinutes, 180);
    expect(decoded.localAt.hour, 0);
    expect(decoded.note, 'early one');
  });
}
