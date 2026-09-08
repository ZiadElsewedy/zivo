import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/training_dashboard_stats.dart';

import '../support/workout_fixtures.dart';

// A Wednesday, so "this week" (Mon-start) and "last week" are unambiguous.
final _now = DateTime(2026, 8, 19, 18, 0);

/// The shared fixture, which gives every session a real completed working set
/// — the bar the streak actually measures. The old local builder produced
/// sessions with no exercises at all, which read like trained days and were
/// not.
LiveSession _session({
  required String id,
  required DateTime startedAt,
  Duration duration = const Duration(minutes: 50),
  String dayLabel = 'Push',
  SessionStatus status = SessionStatus.completed,
  String planId = 'p1',
  int workingSets = 1,
  DurationSource durationSource = DurationSource.measured,
}) => session(
  id: id,
  startedAt: startedAt,
  duration: duration,
  dayLabel: dayLabel,
  status: status,
  planId: planId,
  workingSets: workingSets,
  durationSource: durationSource,
);

void main() {
  group('computeTrainingDashboardStats', () {
    test('empty input yields zeroed/null stats and no recent sessions', () {
      final stats = computeTrainingDashboardStats(sessions: const [], now: _now);
      expect(stats.totalCompletedSessions, 0);
      expect(stats.sessionsThisWeek, 0);
      expect(stats.currentStreakWeeks, 0);
      expect(stats.currentStreakDays, 0);
      expect(stats.averageSessionDuration, isNull);
      expect(stats.averageStartMinutesSinceMidnight, isNull);
      expect(stats.averageEndMinutesSinceMidnight, isNull);
      expect(stats.sessionCountByDayLabel, isEmpty);
      expect(stats.recentSessions, isEmpty);
    });

    test('averages duration and start/end time-of-day across completed sessions only', () {
      final sessions = [
        // 6:00am start, 50min duration -> ends 6:50am.
        _session(id: 's1', startedAt: DateTime(2026, 8, 18, 6, 0), duration: const Duration(minutes: 50)),
        // 7:00am start, 70min duration -> ends 8:10am.
        _session(id: 's2', startedAt: DateTime(2026, 8, 17, 7, 0), duration: const Duration(minutes: 70)),
        // An active (never-finished) session must not skew the averages.
        _session(id: 's3', startedAt: DateTime(2026, 8, 16, 5, 0), status: SessionStatus.active),
        // Neither should an abandoned one.
        _session(id: 's4', startedAt: DateTime(2026, 8, 15, 9, 0), status: SessionStatus.abandoned),
      ];

      final stats = computeTrainingDashboardStats(sessions: sessions, now: _now);

      expect(stats.totalCompletedSessions, 2);
      expect(stats.averageSessionDuration, const Duration(minutes: 60));
      // Average of 6:00am (360min) and 7:00am (420min) = 6:30am (390min).
      expect(stats.averageStartMinutesSinceMidnight, 390);
      // Average of 6:50am (410min) and 8:10am (490min) = 7:30am (450min).
      expect(stats.averageEndMinutesSinceMidnight, 450);
      // All 4 sessions show up in the activity feed regardless of status.
      expect(stats.recentSessions, hasLength(4));
      expect(stats.recentSessions.first.id, 's1'); // newest-started-first
    });

    test('sessionsThisWeek only counts the current Mon-Sun week', () {
      final sessions = [
        _session(id: 'this-mon', startedAt: DateTime(2026, 8, 17, 6)), // this week
        _session(id: 'this-wed', startedAt: DateTime(2026, 8, 19, 6)), // this week (= now's day)
        _session(id: 'last-sun', startedAt: DateTime(2026, 8, 16, 6)), // last week
      ];
      final stats = computeTrainingDashboardStats(sessions: sessions, now: _now);
      expect(stats.sessionsThisWeek, 2);
    });

    test('currentStreakWeeks counts consecutive trained weeks back from the latest one', () {
      final sessions = [
        // Trained last week and the week before, nothing yet this week —
        // the in-progress week doesn't break the streak.
        _session(id: 'w-1', startedAt: DateTime(2026, 8, 10, 6)),
        _session(id: 'w-2', startedAt: DateTime(2026, 8, 3, 6)),
        // A gap, then an older isolated week that must NOT extend the streak.
        _session(id: 'w-4', startedAt: DateTime(2026, 7, 20, 6)),
      ];
      final stats = computeTrainingDashboardStats(sessions: sessions, now: _now);
      expect(stats.currentStreakWeeks, 2);
    });

    test('currentStreakWeeks is 0 when nothing has ever been logged', () {
      final stats = computeTrainingDashboardStats(sessions: const [], now: _now);
      expect(stats.currentStreakWeeks, 0);
    });

    // The rule itself lives in `training_streak_test.dart`. What matters HERE
    // is that the dashboard reads that one engine rather than walking the
    // calendar again — two implementations of this is the bug that was fixed.
    test('currentStreakDays comes from the shared streak engine', () {
      final sessions = [
        _session(id: 'd0', startedAt: DateTime(2026, 8, 19, 6)), // today
        _session(id: 'd1', startedAt: DateTime(2026, 8, 18, 6)),
        _session(id: 'd2', startedAt: DateTime(2026, 8, 17, 6)),
        // Four calendar days after the one above — past the allowance.
        _session(id: 'd4', startedAt: DateTime(2026, 8, 13, 6)),
      ];
      final stats = computeTrainingDashboardStats(sessions: sessions, now: _now);
      expect(stats.currentStreakDays, 3);
      expect(stats.streak.currentDays, stats.currentStreakDays);
      expect(stats.streak.days, hasLength(3));
    });

    test('currentStreakDays survives two rest days, per the every-3-days rule', () {
      final sessions = [
        _session(id: 'd1', startedAt: DateTime(2026, 8, 17, 6)),
        _session(id: 'd2', startedAt: DateTime(2026, 8, 14, 6)),
      ];
      final stats = computeTrainingDashboardStats(sessions: sessions, now: _now);
      expect(stats.currentStreakDays, 2);
    });

    test('currentStreakDays is 0 when nothing has ever been logged', () {
      final stats = computeTrainingDashboardStats(sessions: const [], now: _now);
      expect(stats.currentStreakDays, 0);
    });

    test('currentStreakDays does not count an abandoned or voided session', () {
      final sessions = [
        _session(
          id: 'd0',
          startedAt: DateTime(2026, 8, 19, 6),
          status: SessionStatus.abandoned,
        ),
        _session(
          id: 'd1',
          startedAt: DateTime(2026, 8, 18, 6),
          status: SessionStatus.voided,
        ),
      ];
      final stats = computeTrainingDashboardStats(sessions: sessions, now: _now);
      expect(stats.currentStreakDays, 0);
    });

    test('currentStreakDays counts multiple sessions on the same day once', () {
      final sessions = [
        _session(id: 'd0a', startedAt: DateTime(2026, 8, 19, 6)),
        _session(id: 'd0b', startedAt: DateTime(2026, 8, 19, 18)),
      ];
      final stats = computeTrainingDashboardStats(sessions: sessions, now: _now);
      expect(stats.currentStreakDays, 1);
    });

    test('an implausible duration is held out of the average, not folded in', () {
      final sessions = [
        _session(
          id: 'ok1',
          startedAt: DateTime(2026, 8, 19, 6),
          duration: const Duration(minutes: 60),
        ),
        _session(
          id: 'ok2',
          startedAt: DateTime(2026, 8, 18, 6),
          duration: const Duration(minutes: 80),
        ),
        _session(
          id: 'left-open',
          startedAt: DateTime(2026, 8, 17, 18),
          duration: const Duration(hours: 19),
        ),
      ];
      final stats = computeTrainingDashboardStats(
        sessions: sessions,
        now: _now,
        maxSessionDuration: const Duration(hours: 3),
      );
      expect(stats.averageSessionDuration, const Duration(minutes: 70));
      expect(stats.durationsCounted, 2);
      expect(stats.durationsExcluded, 1);
      expect(
        stats.totalCompletedSessions,
        3,
        reason: 'excluded from the AVERAGE, not from history',
      );
    });

    test('an unknowable duration is excluded even though it is short', () {
      final stats = computeTrainingDashboardStats(
        sessions: [
          _session(
            id: 'a',
            startedAt: DateTime(2026, 8, 19, 6),
            duration: const Duration(minutes: 40),
            durationSource: DurationSource.unknown,
          ),
        ],
        now: _now,
      );
      expect(stats.averageSessionDuration, isNull);
      expect(stats.durationsExcluded, 1);
    });

    test('a corrected session rejoins the average with its corrected length', () {
      final bad = _session(
        id: 'left-open',
        startedAt: DateTime(2026, 8, 19, 6),
        duration: const Duration(hours: 19),
      );
      final fixed = bad.correctDuration(64);
      final stats = computeTrainingDashboardStats(
        sessions: [fixed],
        now: _now,
        maxSessionDuration: const Duration(hours: 3),
      );
      expect(stats.averageSessionDuration, const Duration(minutes: 64));
      expect(stats.durationsExcluded, 0);
    });

    test('sessionCountByDayLabel tallies completed sessions per split day', () {
      final sessions = [
        _session(id: 's1', startedAt: DateTime(2026, 8, 17, 6), dayLabel: 'Push'),
        _session(id: 's2', startedAt: DateTime(2026, 8, 18, 6), dayLabel: 'Push'),
        _session(id: 's3', startedAt: DateTime(2026, 8, 19, 6), dayLabel: 'Pull'),
        // Abandoned attempts don't count as trained.
        _session(id: 's4', startedAt: DateTime(2026, 8, 15, 6), dayLabel: 'Legs', status: SessionStatus.abandoned),
      ];
      final stats = computeTrainingDashboardStats(sessions: sessions, now: _now);
      expect(stats.sessionCountByDayLabel, {'Push': 2, 'Pull': 1});
    });

    test('recentSessions respects recentLimit and stays newest-first regardless of status', () {
      final sessions = [
        for (var i = 0; i < 12; i++)
          _session(
            id: 's$i',
            startedAt: DateTime(2026, 8, 1).add(Duration(days: i)),
            status: i.isEven ? SessionStatus.completed : SessionStatus.abandoned,
          ),
      ];
      final stats = computeTrainingDashboardStats(sessions: sessions, now: _now, recentLimit: 5);
      expect(stats.recentSessions, hasLength(5));
      expect(stats.recentSessions.map((s) => s.id), ['s11', 's10', 's9', 's8', 's7']);
    });
  });
}
