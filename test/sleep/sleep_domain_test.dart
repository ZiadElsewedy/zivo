import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/sleep/domain/sleep_insight.dart';
import 'package:zivo/features/sleep/domain/sleep_metrics.dart';
import 'package:zivo/features/sleep/domain/sleep_night.dart';
import 'package:zivo/features/sleep/domain/sleep_provenance.dart';
import 'package:zivo/features/sleep/domain/sleep_resolver.dart';
import 'package:zivo/features/sleep/domain/sleep_session.dart';
import 'package:zivo/features/sleep/domain/sleep_sessionizer.dart';
import 'package:zivo/features/sleep/domain/sleep_source.dart';
import 'package:zivo/features/sleep/domain/sleep_targets.dart';

/// Cover for the pure core of sleep — the part that decides what ZIVO is
/// entitled to claim.
///
/// These are the rules from `docs/SLEEP_SYSTEM.md` written as assertions,
/// because every one of them is a rule a later refactor could quietly break
/// while the app still looked fine: a hand-typed night promoted to a
/// measurement, two providers averaged into a night nobody slept, a clock time
/// averaged arithmetically, a "trend" over three days.

final _ingested = DateTime.utc(2026, 9, 7, 12);

RawSleepRecord _sample({
  required DateTime start,
  required DateTime end,
  SleepStage stage = SleepStage.asleepUnspecified,
  String providerId = 'com.apple.health',
  String providerName = 'Apple Health',
  SleepDeviceKind deviceKind = SleepDeviceKind.watch,
  SleepRecordingMethod recordingMethod = SleepRecordingMethod.automatic,
  List<SleepStageSegment> stages = const [],
  bool preSessionized = false,
  String? id,
}) => RawSleepRecord(
  id: id ?? '${providerId}_${start.toIso8601String()}_${stage.name}',
  startAt: start,
  endAt: end,
  startOffsetMinutes: 0,
  endOffsetMinutes: 0,
  stage: stage,
  stages: stages,
  preSessionized: preSessionized,
  providerId: providerId,
  providerName: providerName,
  deviceKind: deviceKind,
  recordingMethod: recordingMethod,
);

SleepSession _session({
  required DateTime start,
  required DateTime end,
  SleepMethod method = SleepMethod.measuredWearable,
  double completeness = 1,
  String providerId = 'com.apple.health',
  int offsetMinutes = 0,
  List<SleepStageSegment> stages = const [],
  String? supersedes,
  DateTime? ingestedAt,
}) => SleepSession(
  id: '$providerId:${start.toIso8601String()}',
  startAt: start,
  endAt: end,
  startOffsetMinutes: offsetMinutes,
  endOffsetMinutes: offsetMinutes,
  stages: stages,
  supersedes: supersedes,
  provenance: SleepProvenance(
    method: method,
    providerId: providerId,
    providerName: providerId,
    deviceKind: SleepDeviceKind.watch,
    recordingMethod: SleepRecordingMethod.automatic,
    confidence: SleepConfidence.medium,
    completeness: completeness,
    rawRefs: const [],
    ingestedAt: ingestedAt ?? _ingested,
  ),
);

void main() {
  group('provenance — method is read, never guessed', () {
    test('a hand-typed entry stays user-reported even from a watch', () {
      // The trap this feature exists to avoid: a manual entry synced through
      // Apple Health arrives carrying an Apple Watch's device metadata. Tier 4
      // dressed as tier 1.
      expect(
        methodFor(
          providerId: 'com.apple.health',
          deviceKind: SleepDeviceKind.watch,
          recordingMethod: SleepRecordingMethod.manual,
        ),
        SleepMethod.userReported,
      );
    });

    test('a watch recording automatically is a wearable measurement', () {
      expect(
        methodFor(
          providerId: 'com.apple.health',
          deviceKind: SleepDeviceKind.watch,
          recordingMethod: SleepRecordingMethod.automatic,
        ),
        SleepMethod.measuredWearable,
      );
    });

    test('a known wearable app is promoted without device metadata', () {
      expect(
        methodFor(
          providerId: 'com.ouraring.oura.watchapp',
          deviceKind: SleepDeviceKind.unknown,
          recordingMethod: SleepRecordingMethod.automatic,
        ),
        SleepMethod.measuredWearable,
      );
    });

    test('an unknown writer is platform-derived, not demoted to an estimate',
        () {
      expect(
        methodFor(
          providerId: 'com.example.unknown',
          deviceKind: SleepDeviceKind.unknown,
          recordingMethod: SleepRecordingMethod.unknown,
        ),
        SleepMethod.platformDerived,
      );
    });

    test('confidence needs stages, coverage and a single source', () {
      expect(
        confidenceFor(
          method: SleepMethod.measuredWearable,
          hasStages: true,
          completeness: 0.95,
          sourceCount: 1,
        ),
        SleepConfidence.high,
      );
      expect(
        confidenceFor(
          method: SleepMethod.measuredWearable,
          hasStages: false,
          completeness: 0.95,
          sourceCount: 1,
        ),
        SleepConfidence.medium,
      );
      // Thin coverage caps a wearable night at low however good the sensor.
      expect(
        confidenceFor(
          method: SleepMethod.measuredWearable,
          hasStages: true,
          completeness: 0.5,
          sourceCount: 1,
        ),
        SleepConfidence.low,
      );
      expect(
        confidenceFor(
          method: SleepMethod.userReported,
          hasStages: true,
          completeness: 1,
          sourceCount: 1,
        ),
        SleepConfidence.low,
      );
    });
  });

  group('sessionizer — HealthKit fragments become nights', () {
    test('adjacent fragments from one provider stitch into one session', () {
      final base = DateTime.utc(2026, 9, 6, 22);
      final records = [
        for (var i = 0; i < 8; i++)
          _sample(
            start: base.add(Duration(minutes: 45 * i)),
            end: base.add(Duration(minutes: 45 * (i + 1))),
            stage: SleepStage.light,
          ),
      ];

      final sessions = SleepSessionizer.sessionize(records,
          ingestedAt: _ingested);

      expect(sessions, hasLength(1));
      expect(sessions.single.duration, const Duration(hours: 6));
      expect(sessions.single.provenance.rawRefs, hasLength(8));
    });

    test('a gap over an hour splits one cloud into two sessions', () {
      final base = DateTime.utc(2026, 9, 6, 21);
      final sessions = SleepSessionizer.sessionize([
        _sample(start: base, end: base.add(const Duration(hours: 1))),
        // Ninety minutes later — a wake bout long enough to end a period.
        _sample(
          start: base.add(const Duration(hours: 2, minutes: 30)),
          end: base.add(const Duration(hours: 6)),
        ),
      ], ingestedAt: _ingested);

      expect(sessions, hasLength(2));
    });

    test('two providers never merge into one session', () {
      final base = DateTime.utc(2026, 9, 6, 23);
      final sessions = SleepSessionizer.sessionize([
        _sample(
          start: base,
          end: base.add(const Duration(hours: 7)),
          providerId: 'com.apple.health',
        ),
        _sample(
          start: base.add(const Duration(minutes: 20)),
          end: base.add(const Duration(hours: 7, minutes: 10)),
          providerId: 'com.ouraring.oura',
        ),
      ], ingestedAt: _ingested);

      expect(sessions, hasLength(2));
    });

    test('in-bed time does not inflate the sleep span', () {
      // An hour of reading in bed before sleeping must not count as sleep.
      final bed = DateTime.utc(2026, 9, 6, 22);
      final asleep = DateTime.utc(2026, 9, 6, 23);
      final wake = DateTime.utc(2026, 9, 7, 6);

      final session = SleepSessionizer.sessionize([
        _sample(start: bed, end: wake, stage: SleepStage.inBed),
        _sample(start: asleep, end: wake, stage: SleepStage.asleepUnspecified),
      ], ingestedAt: _ingested).single;

      expect(session.startAt, asleep);
      expect(session.duration, const Duration(hours: 7));
      expect(session.timeInBed, const Duration(hours: 8));
      expect(session.efficiency, closeTo(7 / 8, 0.001));
    });

    test('efficiency is null — not 1.0 — when time in bed is unknown', () {
      final session = SleepSessionizer.sessionize([
        _sample(
          start: DateTime.utc(2026, 9, 6, 23),
          end: DateTime.utc(2026, 9, 7, 6),
        ),
      ], ingestedAt: _ingested).single;

      expect(session.timeInBed, isNull);
      expect(session.efficiency, isNull);
    });

    test('a sparse cloud reports low completeness and low confidence', () {
      // A source that writes half-hour samples every seventy-five minutes:
      // close enough to stitch into one session, nowhere near enough to back
      // the span it implies. Without completeness this would present as five
      // and a half hours of measured sleep.
      final start = DateTime.utc(2026, 9, 6, 23);
      final session = SleepSessionizer.sessionize([
        for (var i = 0; i < 5; i++)
          _sample(
            start: start.add(Duration(minutes: 75 * i)),
            end: start.add(Duration(minutes: 75 * i + 30)),
            stage: SleepStage.light,
          ),
      ], ingestedAt: _ingested).single;

      expect(session.duration, const Duration(minutes: 330));
      expect(session.provenance.completeness, closeTo(150 / 330, 0.01));
      expect(session.provenance.confidence, SleepConfidence.low);
    });

    test('samples far enough apart split rather than spanning the gap', () {
      // Two forty-minute samples six hours apart are not one six-hour night.
      // The stitch rule splits them, and neither survives as a main sleep.
      final start = DateTime.utc(2026, 9, 6, 23);
      final sessions = SleepSessionizer.sessionize([
        _sample(start: start, end: start.add(const Duration(minutes: 40))),
        _sample(
          start: start.add(const Duration(hours: 5, minutes: 20)),
          end: start.add(const Duration(hours: 6)),
        ),
      ], ingestedAt: _ingested);

      expect(sessions, hasLength(2));
      expect(SleepResolver.resolve(sessions).single.hasData, isFalse);
    });

    test('awake runs under five minutes are not interruptions', () {
      final start = DateTime.utc(2026, 9, 6, 23);
      final session = SleepSessionizer.sessionize([
        _sample(
          start: start,
          end: start.add(const Duration(hours: 3)),
          stage: SleepStage.light,
        ),
        _sample(
          start: start.add(const Duration(hours: 3)),
          end: start.add(const Duration(hours: 3, minutes: 2)),
          stage: SleepStage.awake,
        ),
        _sample(
          start: start.add(const Duration(hours: 3, minutes: 2)),
          end: start.add(const Duration(hours: 7)),
          stage: SleepStage.light,
        ),
      ], ingestedAt: _ingested).single;

      expect(session.interruptions, isEmpty);
      expect(session.asleepDuration, const Duration(hours: 7));
    });

    test('a long awake run is subtracted from time asleep', () {
      final start = DateTime.utc(2026, 9, 6, 23);
      final session = SleepSessionizer.sessionize([
        _sample(
          start: start,
          end: start.add(const Duration(hours: 3)),
          stage: SleepStage.light,
        ),
        _sample(
          start: start.add(const Duration(hours: 3)),
          end: start.add(const Duration(hours: 3, minutes: 40)),
          stage: SleepStage.awake,
        ),
        _sample(
          start: start.add(const Duration(hours: 3, minutes: 40)),
          end: start.add(const Duration(hours: 7)),
          stage: SleepStage.light,
        ),
      ], ingestedAt: _ingested).single;

      expect(session.interruptions, hasLength(1));
      expect(session.asleepDuration, const Duration(hours: 6, minutes: 20));
    });

    test('an Android session passes through without being re-derived', () {
      final start = DateTime.utc(2026, 9, 6, 23);
      final end = DateTime.utc(2026, 9, 7, 7);
      final session = SleepSessionizer.sessionize([
        _sample(
          start: start,
          end: end,
          preSessionized: true,
          providerId: 'com.sec.android.app.shealth',
          stages: [
            SleepStageSegment(
              startAt: start,
              endAt: start.add(const Duration(hours: 2)),
              stage: SleepStage.light,
            ),
            SleepStageSegment(
              startAt: start.add(const Duration(hours: 2)),
              endAt: end,
              stage: SleepStage.deep,
            ),
          ],
        ),
      ], ingestedAt: _ingested).single;

      expect(session.startAt, start);
      expect(session.endAt, end);
      expect(session.provenance.completeness, 1);
      expect(session.provenance.method, SleepMethod.measuredWearable);
      expect(session.provenance.confidence, SleepConfidence.high);
    });

    test('a four-minute stray sample never becomes a session', () {
      final start = DateTime.utc(2026, 9, 6, 23);
      expect(
        SleepSessionizer.sessionize([
          _sample(start: start, end: start.add(const Duration(minutes: 4))),
        ], ingestedAt: _ingested),
        isEmpty,
      );
    });
  });

  group('resolver — choosing, never merging', () {
    test('a night is filed by the date it was woken from', () {
      // 23:00 on the 6th → 07:00 on the 7th is "the night of the 7th".
      final session = _session(
        start: DateTime.utc(2026, 9, 6, 23),
        end: DateTime.utc(2026, 9, 7, 7),
      );
      expect(SleepResolver.sleepDayOf(session), DateTime(2026, 9, 7));
    });

    test('a wearable night outranks a hand-typed one and keeps it', () {
      final watch = _session(
        start: DateTime.utc(2026, 9, 6, 23, 47),
        end: DateTime.utc(2026, 9, 7, 7),
      );
      final typed = _session(
        start: DateTime.utc(2026, 9, 6, 23),
        end: DateTime.utc(2026, 9, 7, 7),
        method: SleepMethod.userReported,
        providerId: 'com.apple.health.manual',
      );

      final night = SleepResolver.resolve([typed, watch]).single;

      expect(night.main!.startAt, watch.startAt);
      expect(night.resolution, SleepResolution.bestMethod);
      // Never merged, never dropped.
      expect(night.alternates, hasLength(1));
      expect(night.alternates.single.startAt, typed.startAt);
    });

    test('the chosen night is one source verbatim, never an average', () {
      final a = _session(
        start: DateTime.utc(2026, 9, 6, 23),
        end: DateTime.utc(2026, 9, 7, 7),
        providerId: 'com.apple.health',
      );
      final b = _session(
        start: DateTime.utc(2026, 9, 6, 23, 30),
        end: DateTime.utc(2026, 9, 7, 7, 30),
        providerId: 'com.ouraring.oura',
        completeness: 0.85,
      );

      final night = SleepResolver.resolve([a, b]).single;

      // Not 23:15 — the midpoint of the two — but exactly one of them.
      expect(
        night.main!.startAt,
        anyOf(a.startAt, b.startAt),
      );
      expect(night.main!.startAt, a.startAt);
      expect(night.largestDisagreement, const Duration(minutes: 30));
    });

    test('a user override wins over every sensor', () {
      final watch = _session(
        start: DateTime.utc(2026, 9, 6, 23, 47),
        end: DateTime.utc(2026, 9, 7, 7),
      );
      final edit = _session(
        start: DateTime.utc(2026, 9, 6, 22, 30),
        end: DateTime.utc(2026, 9, 7, 7),
        method: SleepMethod.userReported,
        providerId: SleepProvenance.manualProviderId,
        supersedes: watch.id,
      );

      final night = SleepResolver.resolve([watch, edit]).single;

      expect(night.resolution, SleepResolution.userOverride);
      expect(night.main!.startAt, edit.startAt);
      expect(night.alternates.single.id, watch.id);
    });

    test('a short episode is a nap and never the night', () {
      final nap = _session(
        start: DateTime.utc(2026, 9, 7, 14),
        end: DateTime.utc(2026, 9, 7, 14, 40),
      );
      final night = SleepResolver.resolve([nap]).single;

      expect(night.hasData, isFalse);
      expect(night.naps, hasLength(1));
      expect(night.resolution, SleepResolution.none);
    });
  });

  group('targets — clock deltas wrap round midnight', () {
    test('a bedtime after midnight is late, not twenty-two hours early', () {
      // The classic bug: 00:30 vs a 23:00 target is +90 min, not -1350.
      expect(signedClockDelta(30, 23 * 60), 90);
      expect(signedClockDelta(22 * 60, 23 * 60), -60);
    });

    test('a night reports its delta against the target it was slept under',
        () {
      final night = SleepNight(
        sleepDay: DateTime(2026, 9, 7),
        main: _session(
          start: DateTime.utc(2026, 9, 7, 0, 30),
          end: DateTime.utc(2026, 9, 7, 7),
        ),
        targets: SleepTargets.defaults,
      );

      expect(night.bedtimeDeltaMinutes, 90);
      expect(night.metBedtimeTarget, isFalse);
      expect(night.durationDeltaMinutes, 390 - 480);
    });
  });

  group('metrics — clock times live on a circle', () {
    test('averaging 23:40 and 00:20 gives midnight, not noon', () {
      // Arithmetic mean would be 12:00 — the single most common bug in this
      // class of feature.
      final mean = SleepMetrics.circularMeanMinutes([23 * 60 + 40, 20]);
      expect(mean, isNotNull);
      expect(mean! % (24 * 60), closeTo(0, 1));
    });

    test('tight bedtimes have a small circular SD across midnight', () {
      final sd = SleepMetrics.circularSdMinutes([
        23 * 60 + 50,
        0,
        10,
        23 * 60 + 55,
        5,
      ]);
      expect(sd, isNotNull);
      expect(sd!, lessThan(20));
    });

    test('scattered bedtimes have a large circular SD', () {
      final sd = SleepMetrics.circularSdMinutes([
        21 * 60,
        23 * 60,
        1 * 60,
        3 * 60,
        22 * 60,
      ]);
      expect(sd, isNotNull);
      expect(sd!, greaterThan(90));
    });

    test('two nights produce no average at all', () {
      final metrics = SleepMetrics.forWindow(
        _nights(2, minutes: 420),
        windowNights: 7,
      );
      expect(metrics.nightCount, 2);
      expect(metrics.meanDurationMinutes, isNull);
      expect(metrics.hasAverage, isFalse);
    });

    test('four nights average but do not yet yield variability', () {
      final metrics = SleepMetrics.forWindow(
        _nights(4, minutes: 420),
        windowNights: 7,
      );
      expect(metrics.meanDurationMinutes, closeTo(420, 0.001));
      expect(metrics.midpointSdMinutes, isNull);
    });

    test('five nights yield variability', () {
      final metrics = SleepMetrics.forWindow(
        _nights(5, minutes: 420),
        windowNights: 7,
      );
      expect(metrics.midpointSdMinutes, isNotNull);
    });

    test('a ten-minute weekly difference is called unchanged, with the figure',
        () {
      final comparison = SleepMetrics.compare(
        current: SleepMetrics.forWindow(_nights(6, minutes: 430),
            windowNights: 7),
        previous: SleepMetrics.forWindow(_nights(6, minutes: 420),
            windowNights: 7),
      );
      expect(comparison.verdict, SleepComparisonVerdict.unchanged);
      expect(comparison.deltaMinutes, 10);
    });

    test('a thirty-minute weekly difference is a real improvement', () {
      final comparison = SleepMetrics.compare(
        current: SleepMetrics.forWindow(_nights(6, minutes: 450),
            windowNights: 7),
        previous: SleepMetrics.forWindow(_nights(6, minutes: 420),
            windowNights: 7),
      );
      expect(comparison.verdict, SleepComparisonVerdict.improved);
      expect(comparison.deltaMinutes, 30);
    });

    test('a thin week yields no comparison however big the gap', () {
      final comparison = SleepMetrics.compare(
        current: SleepMetrics.forWindow(_nights(3, minutes: 500),
            windowNights: 7),
        previous: SleepMetrics.forWindow(_nights(6, minutes: 400),
            windowNights: 7),
      );
      expect(comparison.verdict, SleepComparisonVerdict.insufficientData);
      expect(comparison.deltaMinutes, isNull);
    });

    test('a fortnight is needed before any trend is reported', () {
      expect(
        SleepMetrics.trend(_nights(10, minutes: 420)).direction,
        SleepTrendDirection.insufficientData,
      );
    });

    test('one all-nighter does not flip a fortnight of stable sleep', () {
      // Theil-Sen's whole reason for being here: least squares would let this
      // single outlier drag the slope.
      final nights = _nights(24, minutes: 420);
      final wrecked = [
        for (var i = 0; i < nights.length; i++)
          if (i == 3)
            SleepNight(
              sleepDay: nights[i].sleepDay,
              main: _session(
                start: nights[i].sleepDay.subtract(const Duration(hours: 2)),
                end: nights[i].sleepDay,
              ),
            )
          else
            nights[i],
      ];

      final trend = SleepMetrics.trend(wrecked);
      expect(trend.direction, SleepTrendDirection.flat);
    });
  });

  group('the numeral gate', () {
    late SleepFactSheet sheet;

    setUp(() {
      sheet = SleepFactSheet(
        facts: const [
          SleepFact(
            id: 'meanDuration',
            value: 412,
            unit: 'minutes',
            nightCount: 6,
          ),
          SleepFact(
            id: 'weekOverWeekDelta',
            value: 34,
            unit: 'minutes',
            nightCount: 6,
          ),
        ],
        insufficient: const ['trend'],
        windowNights: 7,
        nightsWithData: 6,
      );
    });

    test('a sentence built from the sheet passes', () {
      expect(
        groundedNumerals(
          'You slept 6h 52m on average across 6 nights, 34 minutes more '
          'than last week.',
          sheet,
        ),
        isTrue,
      );
    });

    test('a fabricated figure is rejected', () {
      expect(
        groundedNumerals('Your deep sleep rose 19% this week.', sheet),
        isFalse,
      );
    });

    test('a plausible-but-invented delta is rejected', () {
      expect(
        groundedNumerals('You slept 47 minutes more than last week.', sheet),
        isFalse,
      );
    });

    test('a leading zero in a clock time still matches', () {
      expect(groundedNumerals('Lights out around 07:00.', sheet), isTrue);
    });

    test('an insight citing nothing is not renderable', () {
      const insight = SleepInsight(
        kind: SleepInsightKind.duration,
        text: 'You slept well.',
        basedOn: [],
        nightCount: 6,
      );
      expect(insight.isAttributable, isFalse);
    });
  });

  group('fact sheet', () {
    test('a failed gate is named, not silently omitted', () {
      final nights = _nights(3, minutes: 420);
      final current = SleepMetrics.forWindow(nights, windowNights: 7);
      final previous = SleepMetrics.forWindow(const [], windowNights: 7);

      final sheet = buildFactSheet(
        current: current,
        previous: previous,
        comparison: SleepMetrics.compare(
          current: current,
          previous: previous,
        ),
        trend: SleepMetrics.trend(nights),
        nights: nights,
      );

      expect(sheet.insufficient, contains('weekOverWeekDelta'));
      expect(sheet.insufficient, contains('trend'));
      expect(sheet.insufficient, contains('midpointVariability'));
      expect(
        sheet.facts.map((f) => f.id),
        contains('meanDuration'),
      );
    });
  });
}

/// [count] consecutive nights of [minutes] sleep, ending on 2026-09-07.
List<SleepNight> _nights(int count, {required int minutes}) {
  final nights = <SleepNight>[];
  for (var i = 0; i < count; i++) {
    final day = DateTime(2026, 9, 7).subtract(Duration(days: i));
    final wake = DateTime.utc(day.year, day.month, day.day, 7);
    nights.add(
      SleepNight(
        sleepDay: day,
        main: _session(
          start: wake.subtract(Duration(minutes: minutes)),
          end: wake,
        ),
      ),
    );
  }
  return nights;
}
