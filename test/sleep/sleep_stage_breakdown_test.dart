import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/sleep/domain/sleep_night.dart';
import 'package:zivo/features/sleep/domain/sleep_provenance.dart';
import 'package:zivo/features/sleep/domain/sleep_session.dart';
import 'package:zivo/features/sleep/domain/sleep_stage_breakdown.dart';

/// Cover for the stage arithmetic — and, more importantly, for every case in
/// which it **refuses to produce a number**.
///
/// Stage data has been in the pipeline from the start and was never rendered,
/// so this file is the guard on the newest way the feature could start lying:
/// a pie chart is uniquely persuasive, and one built over a fragment of a
/// night, or over samples that overlap, or over a source that never graded the
/// sleep at all, looks exactly as authoritative as one built over a real
/// hypnogram.

final _base = DateTime.utc(2026, 9, 7, 23, 0);

SleepSession _session({
  required List<SleepStageSegment> stages,
  Duration length = const Duration(hours: 8),
}) => SleepSession(
  id: 's',
  startAt: _base,
  endAt: _base.add(length),
  startOffsetMinutes: 0,
  endOffsetMinutes: 0,
  stages: stages,
  provenance: SleepProvenance(
    method: SleepMethod.measuredWearable,
    providerId: 'com.apple.health',
    providerName: 'Apple Watch',
    deviceKind: SleepDeviceKind.watch,
    recordingMethod: SleepRecordingMethod.automatic,
    confidence: SleepConfidence.high,
    completeness: 1,
    rawRefs: const [],
    ingestedAt: _base,
  ),
);

SleepStageSegment _seg(SleepStage stage, int fromMinutes, int toMinutes) =>
    SleepStageSegment(
      startAt: _base.add(Duration(minutes: fromMinutes)),
      endAt: _base.add(Duration(minutes: toMinutes)),
      stage: stage,
    );

void main() {
  group('SleepStageBreakdown.forSession', () {
    test('sums a graded night and reports each stage share', () {
      final breakdown = SleepStageBreakdown.forSession(
        _session(
          stages: [
            _seg(SleepStage.light, 0, 240), // 4h
            _seg(SleepStage.deep, 240, 360), // 2h
            _seg(SleepStage.rem, 360, 480), // 2h
          ],
        ),
      )!;

      expect(breakdown.light, const Duration(hours: 4));
      expect(breakdown.deep, const Duration(hours: 2));
      expect(breakdown.rem, const Duration(hours: 2));
      expect(breakdown.asleepTotal, const Duration(hours: 8));
      expect(breakdown.shareOf(SleepStage.deep), closeTo(0.25, 0.001));
    });

    test('orders the rows deep, REM, light — and drops a stage with no time',
        () {
      // A missing REM segment is not evidence of zero REM sleep. It gets no
      // row rather than a `0m` one, because `0m REM` is a clinical claim and
      // "the source did not report any" is not the same statement.
      final breakdown = SleepStageBreakdown.forSession(
        _session(
          stages: [
            _seg(SleepStage.light, 0, 360),
            _seg(SleepStage.deep, 360, 480),
          ],
        ),
      )!;

      expect(
        breakdown.gradedParts.map((part) => part.$1),
        [SleepStage.deep, SleepStage.light],
      );
    });

    test('counts overlapping samples once', () {
      // The HealthKit shape. Two light-sleep samples describing the same hour
      // must not produce two hours of light sleep — which is what a plain sum
      // of segment lengths gives, inside a session that is only eight hours
      // long.
      final breakdown = SleepStageBreakdown.forSession(
        _session(
          stages: [
            _seg(SleepStage.light, 0, 240),
            _seg(SleepStage.light, 120, 300), // overlaps the first
            _seg(SleepStage.deep, 300, 480),
          ],
        ),
      )!;

      expect(breakdown.light, const Duration(hours: 5));
      expect(breakdown.asleepTotal, const Duration(hours: 8));
    });

    test('clips segments to the session span', () {
      final breakdown = SleepStageBreakdown.forSession(
        _session(
          stages: [
            _seg(SleepStage.light, -60, 240), // starts an hour early
            _seg(SleepStage.deep, 240, 600), // ends two hours late
          ],
        ),
      )!;

      expect(breakdown.stagedTotal, const Duration(hours: 8));
    });

    test('refuses a night with no graded stages', () {
      // An Apple Watch before watchOS 9, or a bare Health Connect session:
      // "asleep, kind unknown". Rendering that as a composition would invent
      // exactly the detail the source declined to give.
      expect(
        SleepStageBreakdown.forSession(
          _session(stages: [_seg(SleepStage.asleepUnspecified, 0, 480)]),
        ),
        isNull,
      );
    });

    test('refuses staging that covers too little of the night', () {
      // Twenty minutes of stage detail inside an eight-hour session describes
      // a fragment. A chart over it would be a chart about nothing, presented
      // as a chart about the night.
      expect(
        SleepStageBreakdown.forSession(
          _session(
            stages: [
              _seg(SleepStage.deep, 0, 10),
              _seg(SleepStage.rem, 10, 20),
            ],
          ),
        ),
        isNull,
      );
    });

    test('ignores in-bed segments, which run in parallel with the stages', () {
      // `inBed` typically spans the whole night alongside the real stages.
      // Counting it would roughly double every figure.
      final breakdown = SleepStageBreakdown.forSession(
        _session(
          stages: [
            _seg(SleepStage.inBed, 0, 480),
            _seg(SleepStage.light, 0, 300),
            _seg(SleepStage.deep, 300, 420),
            _seg(SleepStage.rem, 420, 480),
          ],
        ),
      )!;

      expect(breakdown.stagedTotal, const Duration(hours: 8));
    });

    test('reports awake time separately from asleep time', () {
      final breakdown = SleepStageBreakdown.forSession(
        _session(
          stages: [
            _seg(SleepStage.light, 0, 200),
            _seg(SleepStage.awake, 200, 230),
            _seg(SleepStage.deep, 230, 350),
            _seg(SleepStage.rem, 350, 480),
          ],
        ),
      )!;

      expect(breakdown.awake, const Duration(minutes: 30));
      // The shares are of asleep time, so awake never dilutes them.
      expect(breakdown.asleepTotal, const Duration(minutes: 450));
    });
  });

  group('SleepStageAverages.forWindow', () {
    SleepNight night(int dayOffset, {required bool staged}) => SleepNight(
      sleepDay: DateTime(2026, 9, 1 + dayOffset),
      main: _session(
        stages: staged
            ? [
                _seg(SleepStage.light, 0, 300),
                _seg(SleepStage.deep, 300, 400),
                _seg(SleepStage.rem, 400, 480),
              ]
            : [_seg(SleepStage.asleepUnspecified, 0, 480)],
      ),
    );

    test('averages over the staged nights only', () {
      final averages = SleepStageAverages.forWindow([
        night(0, staged: true),
        night(1, staged: false),
        night(2, staged: true),
        night(3, staged: true),
        night(4, staged: false),
      ])!;

      // Four unstaged nights must not be averaged in as zero deep sleep — the
      // denominator is the staged nights, and it is reported.
      expect(averages.nightsWithStages, 3);
      expect(averages.meanDeep, const Duration(minutes: 100));
    });

    test('is null below the average gate', () {
      // Two staged nights is not "your sleep composition".
      expect(
        SleepStageAverages.forWindow([
          night(0, staged: true),
          night(1, staged: true),
        ]),
        isNull,
      );
    });

    test('is null when a week has no staged night at all', () {
      expect(
        SleepStageAverages.forWindow([
          night(0, staged: false),
          night(1, staged: false),
          night(2, staged: false),
          night(3, staged: false),
        ]),
        isNull,
      );
    });
  });
}
