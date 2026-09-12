import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/readiness/domain/readiness.dart';
import 'package:zivo/features/sleep/domain/sleep_night.dart';
import 'package:zivo/features/sleep/domain/sleep_provenance.dart';
import 'package:zivo/features/sleep/domain/sleep_session.dart';
import 'package:zivo/features/workout/domain/analytics/workout_analytics.dart';
import 'package:zivo/features/workout/domain/body_weight_entry.dart';
import 'package:zivo/features/workout/domain/weight_trend.dart';

import '../support/workout_fixtures.dart';

final _now = DateTime(2026, 9, 12, 8);

/// A night the user woke from on [wokeOn], having slept [hours].
SleepNight _night(DateTime wokeOn, double hours) {
  final start = DateTime.utc(wokeOn.year, wokeOn.month, wokeOn.day - 1, 23);
  return SleepNight(
    sleepDay: wokeOn,
    main: SleepSession(
      id: 'n',
      startAt: start,
      endAt: start.add(Duration(minutes: (hours * 60).round())),
      startOffsetMinutes: 0,
      endOffsetMinutes: 0,
      provenance: SleepProvenance.manual(
        ingestedAt: wokeOn,
        providerName: 'You',
      ),
    ),
  );
}

WeightTrend _weight(double changeKg) => WeightTrend(
  latest: BodyWeightEntry(id: 'w', weightKg: 80, loggedAt: _now),
  changeKgOverWindow: changeKg,
  series: const [],
);

void main() {
  group('gate', () {
    test('returns null with nothing to stand on', () {
      expect(computeReadiness(now: _now, sessions: const []), isNull);
    });

    test('a stable weigh-in with nothing notable makes no call', () {
      // A weigh-in exists, but a −0.2 kg drift raises no factor — and a call
      // with nothing to cite would break the feature's own rule, so it hides.
      final r = computeReadiness(
        now: _now,
        sessions: const [],
        weight: _weight(-0.2),
      );
      expect(r, isNull);
    });

    test('a rapid weight loss alone is enough to raise a call', () {
      final r = computeReadiness(
        now: _now,
        sessions: const [],
        weight: _weight(-2.4),
      );
      expect(r, isNotNull);
      expect(r!.factors.single.kind, ReadinessFactorKind.bodyWeight);
    });
  });

  group('sleep drives the call', () {
    test('a well-rested night with no debt reads train hard', () {
      final r = computeReadiness(
        now: _now,
        lastNight: _night(DateTime(2026, 9, 12), 8.5),
        sessions: const [],
      );
      expect(r!.verdict, ReadinessVerdict.trainHard);
      final sleep = r.factors.singleWhere(
        (f) => f.kind == ReadinessFactorKind.sleep,
      );
      expect(sleep.direction, ReadinessDirection.supports);
      expect(sleep.sleepDurationMinutes, 510);
      expect(sleep.sleepDeltaMinutes, 30); // 8.5h vs 8h target
    });

    test('a mildly short night eases off to go light', () {
      final r = computeReadiness(
        now: _now,
        lastNight: _night(DateTime(2026, 9, 12), 7.5), // -30 vs target
        sessions: const [],
      );
      expect(r!.verdict, ReadinessVerdict.goLight);
      final sleep = r.factors.first;
      expect(sleep.direction, ReadinessDirection.caution);
      expect(sleep.sleepDeltaMinutes, -30);
    });

    test('a severely short night alone still only reaches go light', () {
      final r = computeReadiness(
        now: _now,
        lastNight: _night(DateTime(2026, 9, 12), 6), // -120 vs target
        sessions: const [],
      );
      expect(r!.verdict, ReadinessVerdict.goLight);
      expect(r.factors.first.direction, ReadinessDirection.limits);
    });

    test(
      'a stale night (older than yesterday) is not claimed as last night',
      () {
        final r = computeReadiness(
          now: _now,
          lastNight: _night(DateTime(2026, 9, 8), 5), // 4 days old
          // A recovered session gives it a reason to still render, so we can
          // check the stale night contributed no sleep factor.
          sessions: [session(id: 's', startedAt: DateTime(2026, 9, 9))],
        );
        expect(
          r!.factors.where((f) => f.kind == ReadinessFactorKind.sleep),
          isEmpty,
        );
      },
    );
  });

  group('recovery and compounding debt', () {
    test('rested + well-recovered reads train hard', () {
      final r = computeReadiness(
        now: _now,
        lastNight: _night(DateTime(2026, 9, 12), 8),
        // Last trained 3 days ago ⇒ recovered.
        sessions: [session(id: 's', startedAt: DateTime(2026, 9, 9, 18))],
      );
      expect(r!.verdict, ReadinessVerdict.trainHard);
      expect(
        r.factors.any(
          (f) =>
              f.kind == ReadinessFactorKind.recentLoad &&
              f.direction == ReadinessDirection.supports &&
              f.restDays == 3,
        ),
        isTrue,
      );
    });

    test('severe short sleep AND already trained today compounds to rest', () {
      final r = computeReadiness(
        now: _now,
        lastNight: _night(DateTime(2026, 9, 12), 6), // limits (2)
        sessions: [session(id: 's', startedAt: DateTime(2026, 9, 12, 6))],
      );
      expect(r!.verdict, ReadinessVerdict.rest);
    });
  });

  group('body-weight is a soft caution', () {
    test('a rapid loss nudges toward going light', () {
      final r = computeReadiness(
        now: _now,
        lastNight: _night(DateTime(2026, 9, 12), 8), // supports
        sessions: const [],
        weight: _weight(-2.4),
      );
      // supports(0) + caution(1) ⇒ debt 1 ⇒ go light.
      expect(r!.verdict, ReadinessVerdict.goLight);
      expect(
        r.factors
            .singleWhere((f) => f.kind == ReadinessFactorKind.bodyWeight)
            .weightChangeKg,
        -2.4,
      );
    });

    test('a small change raises no factor', () {
      final r = computeReadiness(
        now: _now,
        lastNight: _night(DateTime(2026, 9, 12), 8),
        sessions: const [],
        weight: _weight(-0.5),
      );
      expect(
        r!.factors.where((f) => f.kind == ReadinessFactorKind.bodyWeight),
        isEmpty,
      );
    });
  });

  group('deload predicate reads the Workout verdicts', () {
    test('fires on a cluster of stalled lifts', () {
      expect(
        readinessDeloadDue(
          stalledCount: 2,
          overallStatus: ProgressStatus.maintaining,
        ),
        isTrue,
      );
    });

    test('fires on an overall regression', () {
      expect(
        readinessDeloadDue(
          stalledCount: 0,
          overallStatus: ProgressStatus.regressing,
        ),
        isTrue,
      );
    });

    test('stays quiet when only one lift is stuck and overall is fine', () {
      expect(
        readinessDeloadDue(
          stalledCount: 1,
          overallStatus: ProgressStatus.progressing,
        ),
        isFalse,
      );
    });
  });

  test('factors are ordered strongest-pull first', () {
    final r = computeReadiness(
      now: _now,
      lastNight: _night(DateTime(2026, 9, 12), 6), // limits
      sessions: [session(id: 's', startedAt: DateTime(2026, 9, 9))], // supports
    );
    expect(r!.factors.first.direction, ReadinessDirection.limits);
    expect(r.factors.last.direction, ReadinessDirection.supports);
  });
}
