import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/util/calendar.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/training_day_mark.dart';
import 'package:zivo/features/workout/domain/training_streak.dart';

import '../support/workout_fixtures.dart';

/// A Wednesday at midday — far from both midnight boundaries, so a fixture's
/// +50min completion can never drift onto the next day and quietly change what
/// a test is asserting.
final _today = DateTime(2026, 8, 19, 12, 0);

DateTime _daysAgo(int n) => addCalendarDays(_today, -n).add(const Duration(hours: 12));

TrainingStreak _streak(
  List<LiveSession> sessions, {
  List<TrainingDayMark> marks = const [],
  DateTime? now,
}) => computeTrainingStreak(
  sessions: sessions,
  now: now ?? _today,
  marks: marks,
);

TrainingDayMark _restore(int daysAgo) => TrainingDayMark(
  day: startOfDay(_daysAgo(daysAgo)),
  createdAt: _today,
  restored: true,
);

void main() {
  group('what counts as a trained day', () {
    test('a completed session with a working set counts', () {
      expect(_streak([session(id: 'a', startedAt: _daysAgo(0))]).currentDays, 1);
    });

    test('a session with only warm-up sets does NOT count', () {
      final s = session(
        id: 'a',
        startedAt: _daysAgo(0),
        workingSets: 0,
        warmupSets: 3,
      );
      expect(_streak([s]).currentDays, 0);
    });

    test('a session with only skipped sets does NOT count', () {
      final s = session(
        id: 'a',
        startedAt: _daysAgo(0),
        workingSets: 0,
        skippedSets: 4,
      );
      expect(_streak([s]).currentDays, 0);
    });

    test('a PARTIALLY logged session counts — one working set is enough', () {
      final s = session(
        id: 'a',
        startedAt: _daysAgo(0),
        workingSets: 1,
        pendingSets: 9,
      );
      expect(_streak([s]).currentDays, 1);
    });

    test('a still-ACTIVE session counts, so forgetting Finish costs nothing', () {
      final s = session(
        id: 'a',
        startedAt: _daysAgo(0),
        status: SessionStatus.active,
        workingSets: 4,
        pendingSets: 4,
      );
      expect(_streak([s]).currentDays, 1);
    });

    test('an abandoned session does not count', () {
      final s = session(
        id: 'a',
        startedAt: _daysAgo(0),
        status: SessionStatus.abandoned,
      );
      expect(_streak([s]).currentDays, 0);
    });

    test('a VOIDED session does not count', () {
      final s = session(
        id: 'a',
        startedAt: _daysAgo(0),
        status: SessionStatus.voided,
      );
      expect(_streak([s]).currentDays, 0);
    });

    test('two sessions on the same day count as ONE streak day', () {
      final streak = _streak([
        session(id: 'a', startedAt: _daysAgo(0).subtract(const Duration(hours: 4))),
        session(id: 'b', startedAt: _daysAgo(0)),
      ]);
      expect(streak.currentDays, 1);
      expect(streak.days.single.sessionCount, 2);
    });

    test('a session is bucketed by when it FINISHED, not when it started', () {
      // Started 11:40pm yesterday, finished 12:20am today.
      final crossing = session(
        id: 'a',
        startedAt: addCalendarDays(_today, -1).add(const Duration(hours: 23, minutes: 40)),
        duration: const Duration(minutes: 40),
      );
      final streak = _streak([crossing]);
      expect(streak.lastTrainedDay, startOfDay(_today));
    });
  });

  group('the every-3-days rule', () {
    test('training today continues the streak', () {
      final streak = _streak([
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(1)),
      ]);
      expect(streak.currentDays, 2);
    });

    test('one rest day does not break it', () {
      final streak = _streak([
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(2)),
      ]);
      expect(streak.currentDays, 2);
    });

    test('two rest days do not break it', () {
      final streak = _streak([
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(3)),
      ]);
      expect(streak.currentDays, 2);
    });

    test('a gap of FOUR days breaks it — the run starts over', () {
      final streak = _streak([
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(4)),
        session(id: 'c', startedAt: _daysAgo(5)),
      ]);
      expect(streak.currentDays, 1, reason: 'only today survives the gap');
    });

    test('not training today leaves the streak alive inside the allowance', () {
      final streak = _streak([
        session(id: 'a', startedAt: _daysAgo(2)),
        session(id: 'b', startedAt: _daysAgo(4)),
      ]);
      expect(streak.currentDays, 2);
      expect(streak.daysUntilBreak, 1);
    });

    test('the streak lapses once the allowance runs out', () {
      final streak = _streak([session(id: 'a', startedAt: _daysAgo(4))]);
      expect(streak.currentDays, 0);
      expect(streak.daysUntilBreak, isNull);
      expect(
        streak.lastTrainedDay,
        startOfDay(_daysAgo(4)),
        reason: 'a lapsed streak still remembers when you last trained',
      );
    });

    test('daysUntilBreak counts down from the last trained day', () {
      for (final (ago, left) in [(0, 3), (1, 2), (2, 1), (3, 0)]) {
        final streak = _streak([session(id: 'a', startedAt: _daysAgo(ago))]);
        expect(streak.daysUntilBreak, left, reason: 'trained $ago days ago');
      }
    });

    test('isAtRisk turns on for the last day of the allowance', () {
      expect(_streak([session(id: 'a', startedAt: _daysAgo(0))]).isAtRisk, isFalse);
      expect(_streak([session(id: 'a', startedAt: _daysAgo(2))]).isAtRisk, isTrue);
      expect(_streak([session(id: 'a', startedAt: _daysAgo(3))]).isAtRisk, isTrue);
    });

    test('the run includes its rest days so the drill-down reads continuously', () {
      final streak = _streak([
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(3)),
      ]);
      expect(streak.days.map((d) => d.kind).toList(), [
        StreakDayKind.trained,
        StreakDayKind.rest,
        StreakDayKind.rest,
        StreakDayKind.trained,
      ]);
      expect(streak.currentDays, 2, reason: 'rest days never inflate the count');
    });
  });

  group('best streak', () {
    test('is the longest run ever, by the same rule', () {
      final streak = _streak([
        session(id: 'a', startedAt: _daysAgo(0)),
        // A four-day run, ten days back, each two days apart.
        session(id: 'b', startedAt: _daysAgo(10)),
        session(id: 'c', startedAt: _daysAgo(12)),
        session(id: 'd', startedAt: _daysAgo(14)),
        session(id: 'e', startedAt: _daysAgo(16)),
      ]);
      expect(streak.currentDays, 1);
      expect(streak.bestDays, 4);
    });

    test('is never less than the current run', () {
      final streak = _streak([
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(1)),
      ]);
      expect(streak.bestDays, 2);
    });

    test('is 0 with no history', () {
      expect(_streak(const []).bestDays, 0);
      expect(_streak(const []).currentDays, 0);
      expect(_streak(const []).days, isEmpty);
    });
  });

  group('missed-day reasons are context, never credit', () {
    test('a reason on a gap day does NOT keep a broken streak alive', () {
      final marks = [
        TrainingDayMark(
          day: startOfDay(_daysAgo(2)),
          createdAt: _today,
          reason: MissedDayReason.travel,
        ),
      ];
      final streak = _streak([
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(5)),
      ], marks: marks);
      expect(streak.currentDays, 1, reason: 'travel explains, it does not train');
    });

    test('a reason never adds a trained day', () {
      final marks = [
        TrainingDayMark(
          day: startOfDay(_daysAgo(1)),
          createdAt: _today,
          reason: MissedDayReason.rest,
        ),
      ];
      final withReason = _streak([session(id: 'a', startedAt: _daysAgo(0))], marks: marks);
      final without = _streak([session(id: 'a', startedAt: _daysAgo(0))]);
      expect(withReason.currentDays, without.currentDays);
    });

    test('a reason surfaces on its rest day in the run', () {
      final marks = [
        TrainingDayMark(
          day: startOfDay(_daysAgo(1)),
          createdAt: _today,
          reason: MissedDayReason.recovery,
          note: 'legs wrecked',
        ),
      ];
      final streak = _streak([
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(2)),
      ], marks: marks);
      final restDay = streak.days.firstWhere((d) => d.kind == StreakDayKind.rest);
      expect(restDay.reason, MissedDayReason.recovery);
      expect(restDay.note, 'legs wrecked');
    });
  });

  group('restore', () {
    test('bridges a gap that would otherwise break the streak', () {
      final sessions = [
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(5)),
      ];
      expect(_streak(sessions).currentDays, 1);
      expect(_streak(sessions, marks: [_restore(3)]).currentDays, 2);
    });

    test('does NOT add a trained day to the count', () {
      final streak = _streak([
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(5)),
      ], marks: [_restore(3)]);
      expect(streak.currentDays, 2, reason: 'the two real sessions, not three');
      expect(streak.restoresUsed, 1);
      expect(
        streak.days.where((d) => d.kind == StreakDayKind.restored).length,
        1,
      );
    });

    test('is excluded from the all-time best', () {
      final sessions = [
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(5)),
      ];
      final streak = _streak(sessions, marks: [_restore(3)]);
      expect(streak.currentDays, 2);
      expect(
        streak.bestDays,
        2,
        reason: 'best is max(restore-free best=1, current=2) — never inflated '
            'beyond the current run by a restore',
      );
    });

    test('a restore on a day that was trained anyway changes nothing', () {
      final sessions = [
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(1)),
      ];
      expect(
        _streak(sessions, marks: [_restore(1)]).currentDays,
        _streak(sessions).currentDays,
      );
      expect(_streak(sessions, marks: [_restore(1)]).restoresUsed, 0);
    });

    test('cannot bridge a gap wider than the allowance on its own', () {
      // Restoring day 5 leaves 0..5 still 5 apart on one side.
      final streak = _streak([
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(9)),
      ], marks: [_restore(5)]);
      expect(streak.currentDays, 1);
    });

    test('restores alone, with no training, are not a streak', () {
      final streak = _streak(const [], marks: [_restore(1), _restore(2)]);
      expect(streak.currentDays, 0);
      expect(streak.days, isEmpty);
    });
  });

  group('canRestoreDay', () {
    List<TrainingDayMark> noMarks() => const [];

    test('allows a recent missed day', () {
      expect(
        canRestoreDay(
          day: _daysAgo(2),
          now: _today,
          sessions: const [],
          marks: noMarks(),
        ),
        isTrue,
      );
    });

    test('refuses today and the future', () {
      expect(
        canRestoreDay(day: _today, now: _today, sessions: const [], marks: noMarks()),
        isFalse,
      );
      expect(
        canRestoreDay(
          day: addCalendarDays(_today, 1),
          now: _today,
          sessions: const [],
          marks: noMarks(),
        ),
        isFalse,
      );
    });

    test('refuses to reach further back than a week', () {
      expect(
        canRestoreDay(
          day: _daysAgo(kRestoreReachDays),
          now: _today,
          sessions: const [],
          marks: noMarks(),
        ),
        isTrue,
      );
      expect(
        canRestoreDay(
          day: _daysAgo(kRestoreReachDays + 1),
          now: _today,
          sessions: const [],
          marks: noMarks(),
        ),
        isFalse,
      );
    });

    test('refuses a day that was trained anyway', () {
      expect(
        canRestoreDay(
          day: _daysAgo(2),
          now: _today,
          sessions: [session(id: 'a', startedAt: _daysAgo(2))],
          marks: noMarks(),
        ),
        isFalse,
      );
    });

    test('enforces the cooldown between restores', () {
      final recent = TrainingDayMark(
        day: startOfDay(_daysAgo(5)),
        createdAt: _today,
        restored: true,
      );
      expect(
        canRestoreDay(day: _daysAgo(2), now: _today, sessions: const [], marks: [recent]),
        isFalse,
      );
      final old = TrainingDayMark(
        day: startOfDay(_daysAgo(kRestoreCooldownDays + 1)),
        createdAt: _today,
        restored: true,
      );
      expect(
        canRestoreDay(day: _daysAgo(2), now: _today, sessions: const [], marks: [old]),
        isTrue,
      );
    });
  });

  // The regression that made this a rewrite rather than a tweak. Both old
  // engines walked the calendar with `Duration(days: 1)`, which is 24 absolute
  // hours — so on the two days a year the zone shifts, the walk stepped to
  // 23:00 or 01:00 of some other date, matched nothing, and reported a streak
  // of zero to a user who had not missed a session.
  group('daylight saving', () {
    /// Days in [year] where the zone's UTC offset changes. Discovered rather
    /// than hard-coded so this is meaningful in whatever zone the suite runs
    /// in, and skips cleanly in one that never shifts.
    List<DateTime> transitions(int year) {
      final found = <DateTime>[];
      var previous = DateTime(year, 1, 1).timeZoneOffset;
      for (var day = 2; day <= 366; day++) {
        final date = DateTime(year, 1, day);
        if (date.year != year) break;
        if (date.timeZoneOffset != previous) found.add(date);
        previous = date.timeZoneOffset;
      }
      return found;
    }

    final shifts = [...transitions(2026), ...transitions(2027)];
    final skip = shifts.isEmpty ? 'ambient zone has no DST transition' : false;

    test('an unbroken daily streak survives every transition', () {
      for (final shift in shifts) {
        // Train every day for three days either side of the shift, and stand
        // "today" on the last of them.
        final now = addCalendarDays(shift, 3).add(const Duration(hours: 12));
        final sessions = [
          for (var i = 0; i < 7; i++)
            session(
              id: 'd$i',
              startedAt: addCalendarDays(shift, 3 - i).add(const Duration(hours: 18)),
            ),
        ];
        final streak = computeTrainingStreak(sessions: sessions, now: now);
        expect(
          streak.currentDays,
          7,
          reason: 'streak collapsed across the transition at $shift',
        );
      }
    }, skip: skip);

    test('the every-3-days allowance is measured in dates across a transition', () {
      for (final shift in shifts) {
        final now = addCalendarDays(shift, 2).add(const Duration(hours: 12));
        // Trained the day BEFORE the shift; today is two days after it, so the
        // gap is exactly 3 calendar days — inside the allowance.
        final trained = addCalendarDays(shift, -1).add(const Duration(hours: 18));
        final streak = computeTrainingStreak(
          sessions: [session(id: 'a', startedAt: trained)],
          now: now,
        );
        expect(streak.currentDays, 1, reason: 'gap of 3 dates across $shift');
        expect(streak.daysUntilBreak, 0, reason: 'across $shift');
      }
    }, skip: skip);

    test('a run spanning a transition is not truncated in the best streak', () {
      for (final shift in shifts) {
        final now = addCalendarDays(shift, 4).add(const Duration(hours: 12));
        final sessions = [
          for (var i = 0; i < 9; i++)
            session(
              id: 'd$i',
              startedAt: addCalendarDays(shift, 4 - i).add(const Duration(hours: 18)),
            ),
        ];
        final streak = computeTrainingStreak(sessions: sessions, now: now);
        expect(streak.bestDays, 9, reason: 'best truncated at $shift');
      }
    }, skip: skip);

    test('the run lists every date across a transition exactly once', () {
      for (final shift in shifts) {
        final now = addCalendarDays(shift, 2).add(const Duration(hours: 12));
        final sessions = [
          for (var i = 0; i < 5; i++)
            session(
              id: 'd$i',
              startedAt: addCalendarDays(shift, 2 - i).add(const Duration(hours: 18)),
            ),
        ];
        final streak = computeTrainingStreak(sessions: sessions, now: now);
        expect(streak.days.length, 5, reason: 'across $shift');
        expect(
          streak.days.map((d) => d.day).toSet().length,
          5,
          reason: 'a date was visited twice across $shift',
        );
        expect(
          streak.days.every((d) => d.kind == StreakDayKind.trained),
          isTrue,
          reason: 'a real trained day read as rest across $shift',
        );
      }
    }, skip: skip);
  });
}
