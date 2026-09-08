import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_outcome.dart';
import 'package:zivo/features/workout/domain/workout_settings.dart';

import '../support/workout_fixtures.dart';

final _start = DateTime(2026, 8, 19, 18, 0);
const _max = Duration(hours: 3);

void main() {
  group('resolvedAt', () {
    test('Done stamps the moment it was tapped', () {
      final s = session(id: 'a', startedAt: _start, status: SessionStatus.active,
          workingSets: 0, pendingSets: 2);
      final at = _start.add(const Duration(minutes: 12));
      final done = s.markSetDone('e1', 'a-p0', now: at, actualReps: 8, actualWeightKg: 60);
      expect(done.exercises.first.sets.first.resolvedAt, at);
    });

    test('Skip stamps too — a skip is a resolution', () {
      final s = session(id: 'a', startedAt: _start, status: SessionStatus.active,
          workingSets: 0, pendingSets: 2);
      final at = _start.add(const Duration(minutes: 4));
      expect(
        s.markSetSkipped('e1', 'a-p0', now: at).exercises.first.sets.first.resolvedAt,
        at,
      );
    });

    test('undo clears the stamp — an un-done set did not happen', () {
      final s = session(id: 'a', startedAt: _start, status: SessionStatus.active,
              workingSets: 0, pendingSets: 1)
          .markSetDone('e1', 'a-p0', now: _start.add(const Duration(minutes: 9)));
      final undone = s.clearOutcome('e1', 'a-p0');
      expect(undone.exercises.first.sets.first.resolvedAt, isNull);
      expect(undone.lastActivityAt, isNull);
    });

    test('a review edit does NOT re-stamp, so tidying up cannot stretch a session', () {
      final at = _start.add(const Duration(minutes: 9));
      final s = session(id: 'a', startedAt: _start, status: SessionStatus.active,
              workingSets: 0, pendingSets: 1)
          .markSetDone('e1', 'a-p0', now: at);
      final reviewed = s.updateSet('e1', 'a-p0',
          actualReps: 10, actualWeightKg: 70, outcome: SetOutcome.completed);
      expect(reviewed.exercises.first.sets.first.resolvedAt, at);
      expect(reviewed.exercises.first.sets.first.actualReps, 10);
    });

    test('lastActivityAt is the newest stamp across every exercise', () {
      final s = session(id: 'a', startedAt: _start, workingSets: 4);
      expect(
        s.lastActivityAt,
        s.allSets.map((x) => x.resolvedAt!).reduce((a, b) => a.isAfter(b) ? a : b),
      );
    });
  });

  group('elapsed', () {
    test('is wall time minus pauses', () {
      final s = session(
        id: 'a',
        startedAt: _start,
        duration: const Duration(minutes: 70),
        pausedAccumMs: const Duration(minutes: 10).inMilliseconds,
      );
      expect(s.elapsed, const Duration(minutes: 60));
    });

    test('never goes negative when the device clock moves backwards', () {
      final s = session(
        id: 'a',
        startedAt: _start,
        completedAt: _start.subtract(const Duration(hours: 2)),
      );
      expect(s.elapsed, Duration.zero);
    });

    test('a user correction wins outright and leaves the timestamps alone', () {
      final s = session(
        id: 'a',
        startedAt: _start,
        duration: const Duration(hours: 19),
      ).correctDuration(65);
      expect(s.elapsed, const Duration(minutes: 65));
      expect(s.durationSource, DurationSource.userCorrected);
      expect(s.startedAt, _start, reason: 'the record itself is never rewritten');
      expect(s.completedAt, _start.add(const Duration(hours: 19)));
    });

    test('clearing a correction falls back to the measurement', () {
      final s = session(id: 'a', startedAt: _start, duration: const Duration(minutes: 55))
          .correctDuration(65)
          .correctDuration(null);
      expect(s.elapsed, const Duration(minutes: 55));
      expect(s.durationSource, DurationSource.measured);
    });

    test('a negative correction is refused rather than stored', () {
      final s = session(id: 'a', startedAt: _start).correctDuration(-30);
      expect(s.correctedDurationMinutes, isNull);
    });
  });

  group('hasUsableDuration — the gate that keeps averages honest', () {
    test('a normal session is usable', () {
      expect(
        session(id: 'a', startedAt: _start, duration: const Duration(minutes: 55))
            .hasUsableDuration(_max),
        isTrue,
      );
    });

    test('a 19-hour session is not', () {
      final s = session(id: 'a', startedAt: _start, duration: const Duration(hours: 19));
      expect(s.hasUsableDuration(_max), isFalse);
      expect(s.exceedsMaxDuration(_max), isTrue);
    });

    test('an unknowable duration is not, even though it is short', () {
      final s = session(
        id: 'a',
        startedAt: _start,
        duration: const Duration(minutes: 40),
        durationSource: DurationSource.unknown,
      );
      expect(s.hasUsableDuration(_max), isFalse);
    });

    test('a zero-length session is not', () {
      expect(
        session(id: 'a', startedAt: _start, duration: Duration.zero)
            .hasUsableDuration(_max),
        isFalse,
      );
    });

    test('correcting an implausible session makes it usable again', () {
      final s = session(id: 'a', startedAt: _start, duration: const Duration(hours: 19));
      expect(s.hasUsableDuration(_max), isFalse);
      expect(s.correctDuration(70).hasUsableDuration(_max), isTrue);
    });

    test('the threshold is whatever the setting says, not a constant', () {
      final s = session(id: 'a', startedAt: _start, duration: const Duration(hours: 4));
      expect(s.hasUsableDuration(const Duration(hours: 3)), isFalse);
      expect(s.hasUsableDuration(const Duration(hours: 5)), isTrue);
    });
  });

  group('isStale', () {
    LiveSession open({
      required Duration ago,
      Duration? lastSetAgo,
      int workingSets = 3,
    }) {
      final now = _start.add(ago);
      return session(
        id: 'a',
        startedAt: _start,
        status: SessionStatus.active,
        workingSets: workingSets,
        pendingSets: 3,
        lastSetAt: lastSetAgo == null ? null : now.subtract(lastSetAgo),
        duration: ago,
      );
    }

    test('a session inside the maximum is never stale', () {
      final s = open(ago: const Duration(hours: 1));
      expect(
        s.isStale(now: _start.add(const Duration(hours: 1)), maxSessionDuration: _max),
        isFalse,
      );
    });

    test('a session left open overnight is stale', () {
      final s = open(ago: const Duration(hours: 19), lastSetAgo: const Duration(hours: 18));
      expect(
        s.isStale(now: _start.add(const Duration(hours: 19)), maxSessionDuration: _max),
        isTrue,
      );
    });

    test('a genuinely long workout still being logged is NOT stale', () {
      // Past three hours, but a set landed two minutes ago — someone is
      // standing in a gym, and closing this would be the worst bug here.
      final s = open(
        ago: const Duration(hours: 3, minutes: 20),
        lastSetAgo: const Duration(minutes: 2),
      );
      expect(
        s.isStale(
          now: _start.add(const Duration(hours: 3, minutes: 20)),
          maxSessionDuration: _max,
        ),
        isFalse,
      );
    });

    test('past the maximum AND quiet for the grace period is stale', () {
      final s = open(
        ago: const Duration(hours: 3, minutes: 40),
        lastSetAgo: kStaleInactivityGrace + const Duration(minutes: 5),
      );
      expect(
        s.isStale(
          now: _start.add(const Duration(hours: 3, minutes: 40)),
          maxSessionDuration: _max,
        ),
        isTrue,
      );
    });

    test('a completed session is never stale', () {
      final s = session(id: 'a', startedAt: _start, duration: const Duration(hours: 19));
      expect(
        s.isStale(now: _start.add(const Duration(hours: 30)), maxSessionDuration: _max),
        isFalse,
      );
    });

    test('the user setting moves the line', () {
      final s = open(ago: const Duration(hours: 4), lastSetAgo: const Duration(hours: 3));
      final now = _start.add(const Duration(hours: 4));
      expect(s.isStale(now: now, maxSessionDuration: const Duration(hours: 3)), isTrue);
      expect(s.isStale(now: now, maxSessionDuration: const Duration(hours: 6)), isFalse);
    });
  });

  group('autoClose', () {
    test('ends at the last logged set, not the wall clock', () {
      final lastSet = _start.add(const Duration(minutes: 62));
      final s = session(
        id: 'a',
        startedAt: _start,
        status: SessionStatus.active,
        workingSets: 4,
        pendingSets: 4,
        lastSetAt: lastSet,
      );
      final closed = s.autoClose(now: _start.add(const Duration(hours: 19)));
      expect(closed.status, SessionStatus.completed);
      expect(closed.completedAt, lastSet);
      expect(closed.elapsed, const Duration(minutes: 62));
      expect(closed.durationSource, DurationSource.autoClosed);
      expect(closed.hasUsableDuration(_max), isTrue);
    });

    test('NEVER fabricates sets, weights or completions', () {
      final s = session(
        id: 'a',
        startedAt: _start,
        status: SessionStatus.active,
        workingSets: 2,
        pendingSets: 6,
      );
      final closed = s.autoClose(now: _start.add(const Duration(hours: 19)));
      expect(closed.completedSetCount, 2, reason: 'exactly what was logged');
      expect(closed.allSets.where((x) => x.pending).length, 6);
      expect(closed.allSets.where((x) => x.skipped).length, 0,
          reason: 'a pending set is not a skipped one');
      for (final set in closed.allSets.where((x) => x.pending)) {
        expect(set.actualReps, isNull);
        expect(set.actualWeightKg, isNull);
        expect(set.resolvedAt, isNull);
      }
      expect(
        closed.exercises.first.sets.map((x) => x.id).toList(),
        s.exercises.first.sets.map((x) => x.id).toList(),
      );
    });

    test('says the duration is unknown rather than guessing when nothing was logged', () {
      final s = session(
        id: 'a',
        startedAt: _start,
        status: SessionStatus.active,
        workingSets: 0,
        pendingSets: 6,
      );
      final closed = s.autoClose(now: _start.add(const Duration(hours: 19)));
      expect(closed.durationSource, DurationSource.unknown);
      expect(closed.hasUsableDuration(_max), isFalse,
          reason: 'held out of the averages instead of corrupting them');
    });

    test('legacy sets with no timestamps close as unknown, not as 19 hours', () {
      final s = session(
        id: 'a',
        startedAt: _start,
        status: SessionStatus.active,
        workingSets: 3,
        stampResolvedAt: false,
      );
      final closed = s.autoClose(now: _start.add(const Duration(hours: 19)));
      expect(closed.durationSource, DurationSource.unknown);
      expect(closed.hasUsableDuration(_max), isFalse);
    });

    test('drops an open pause instead of folding it in', () {
      final lastSet = _start.add(const Duration(minutes: 40));
      final s = session(
        id: 'a',
        startedAt: _start,
        status: SessionStatus.active,
        workingSets: 3,
        lastSetAt: lastSet,
      ).pause(now: _start.add(const Duration(minutes: 45)));
      final closed = s.autoClose(now: _start.add(const Duration(hours: 19)));
      expect(closed.pausedAt, isNull);
      expect(closed.elapsed, const Duration(minutes: 40));
    });

    test('is a no-op on a session that is not active', () {
      final done = session(id: 'a', startedAt: _start);
      expect(identical(done.autoClose(now: _start), done), isTrue);
    });
  });

  group('finishEarly', () {
    test('ends at now and leaves pending sets pending', () {
      final s = session(
        id: 'a',
        startedAt: _start,
        status: SessionStatus.active,
        workingSets: 3,
        pendingSets: 5,
      );
      final at = _start.add(const Duration(minutes: 48));
      final finished = s.finishEarly(now: at);
      expect(finished.status, SessionStatus.completed);
      expect(finished.completedAt, at);
      expect(finished.elapsed, const Duration(minutes: 48));
      expect(finished.completedSetCount, 3);
      expect(finished.allSets.where((x) => x.pending).length, 5);
      expect(finished.durationSource, DurationSource.measured);
    });

    test('closes an open pause so the pause time is excluded', () {
      final s = session(
        id: 'a',
        startedAt: _start,
        status: SessionStatus.active,
        workingSets: 2,
      ).pause(now: _start.add(const Duration(minutes: 30)));
      final finished = s.finishEarly(now: _start.add(const Duration(minutes: 50)));
      expect(finished.isPaused, isFalse);
      expect(finished.elapsed, const Duration(minutes: 30));
    });

    test('a finished-early session still counts as a trained day', () {
      final s = session(
        id: 'a',
        startedAt: _start,
        status: SessionStatus.active,
        workingSets: 1,
        pendingSets: 9,
      ).finishEarly(now: _start.add(const Duration(minutes: 20)));
      expect(s.hasCompletedWorkingSet, isTrue);
    });

    test('is a no-op on a session that is not active', () {
      final done = session(id: 'a', startedAt: _start);
      expect(identical(done.finishEarly(now: _start), done), isTrue);
    });
  });

  group('void', () {
    test('keeps the record and its numbers, and marks why', () {
      final s = session(id: 'a', startedAt: _start, workingSets: 4)
          .voidSession(reason: VoidReason.badDuration, now: _start);
      expect(s.status, SessionStatus.voided);
      expect(s.voidReason, VoidReason.badDuration);
      expect(s.voidedAt, _start);
      expect(s.completedSetCount, 4, reason: 'nothing about the log is erased');
      expect(s.countsAsTraining, isFalse);
    });

    test('can be undone', () {
      final s = session(id: 'a', startedAt: _start)
          .voidSession(reason: VoidReason.notMine, now: _start)
          .unvoid();
      expect(s.status, SessionStatus.completed);
      expect(s.voidReason, isNull);
      expect(s.countsAsTraining, isTrue);
    });
  });

  group('WorkoutSettings', () {
    test('defaults to three hours', () {
      expect(WorkoutSettings.defaults.maxSessionDuration, const Duration(hours: 3));
    });

    test('clamps a value that would disable or trivialise the protection', () {
      expect(WorkoutSettings.defaults.copyWith(maxSessionMinutes: 0).maxSessionMinutes,
          kMinSessionDurationSettingMinutes);
      expect(
        WorkoutSettings.defaults.copyWith(maxSessionMinutes: 99999).maxSessionMinutes,
        kMaxSessionDurationSettingMinutes,
      );
    });

    test('a missing or out-of-range stored value reads as the default', () {
      expect(maxSessionMinutesFrom(null), kDefaultMaxSessionDurationMinutes);
      expect(maxSessionMinutesFrom(0), kMinSessionDurationSettingMinutes);
      expect(maxSessionMinutesFrom(240), 240);
    });
  });
}
