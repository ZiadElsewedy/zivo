import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_settings_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/session_maintenance.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/up_next_selection.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_settings.dart';

import '../support/workout_fixtures.dart';

final _start = DateTime(2026, 8, 19, 18, 0);
final _nextDay = _start.add(const Duration(hours: 19));

({SessionMaintenance sweeper, InMemoryWorkoutSessionRepository sessions})
_harness(List<LiveSession> seed, {int? maxMinutes}) {
  final sessions = InMemoryWorkoutSessionRepository(seed: seed);
  final settings = InMemoryWorkoutSettingsRepository(
    initial: maxMinutes == null
        ? WorkoutSettings.defaults
        : WorkoutSettings.defaults.copyWith(maxSessionMinutes: maxMinutes),
  );
  return (
    sweeper: SessionMaintenance(sessions: sessions, settings: settings),
    sessions: sessions,
  );
}

WorkoutPlan _plan() => WorkoutPlan(
  id: 'p1',
  name: 'PPL',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: _start,
  updatedAt: _start,
  cycleCursor: 1,
  days: const [
    WorkoutDay(id: 'day-a', slot: 'A', label: 'Push', order: 0, exercises: []),
    WorkoutDay(id: 'day-b', slot: 'B', label: 'Pull', order: 1, exercises: []),
  ],
);

void main() {
  group('sweep', () {
    test('closes a session left open overnight at its last logged set', () async {
      final lastSet = _start.add(const Duration(minutes: 62));
      final h = _harness([
        session(
          id: 'a',
          startedAt: _start,
          status: SessionStatus.active,
          workingSets: 4,
          pendingSets: 4,
          lastSetAt: lastSet,
        ),
      ]);

      final result = await h.sweeper.sweep(now: _nextDay);

      expect(result.closed.single.id, 'a');
      final stored = h.sessions.current.single;
      expect(stored.status, SessionStatus.completed);
      expect(stored.completedAt, lastSet);
      expect(stored.elapsed, const Duration(minutes: 62));
      expect(stored.durationSource, DurationSource.autoClosed);
    });

    test('preserves exactly what was logged and invents nothing', () async {
      final h = _harness([
        session(
          id: 'a',
          startedAt: _start,
          status: SessionStatus.active,
          workingSets: 2,
          pendingSets: 6,
        ),
      ]);

      await h.sweeper.sweep(now: _nextDay);

      final stored = h.sessions.current.single;
      expect(stored.completedSetCount, 2);
      expect(stored.allSets.where((s) => s.pending).length, 6);
      expect(stored.allSets.where((s) => s.skipped).length, 0);
      for (final set in stored.allSets.where((s) => s.pending)) {
        expect(set.actualReps, isNull);
        expect(set.actualWeightKg, isNull);
      }
    });

    test('deletes a left-open session that logged nothing at all', () async {
      final h = _harness([
        session(
          id: 'a',
          startedAt: _start,
          status: SessionStatus.active,
          workingSets: 0,
          pendingSets: 6,
        ),
      ]);

      final result = await h.sweeper.sweep(now: _nextDay);

      expect(result.deleted, ['a']);
      expect(h.sessions.current, isEmpty);
    });

    test('leaves a session inside the maximum alone', () async {
      final h = _harness([
        session(
          id: 'a',
          startedAt: _start,
          status: SessionStatus.active,
          workingSets: 2,
        ),
      ]);

      final result = await h.sweeper.sweep(
        now: _start.add(const Duration(minutes: 40)),
      );

      expect(result.isEmpty, isTrue);
      expect(h.sessions.current.single.status, SessionStatus.active);
    });

    test('leaves a genuinely long workout that is still being logged', () async {
      final now = _start.add(const Duration(hours: 3, minutes: 30));
      final h = _harness([
        session(
          id: 'a',
          startedAt: _start,
          status: SessionStatus.active,
          workingSets: 12,
          pendingSets: 2,
          lastSetAt: now.subtract(const Duration(minutes: 2)),
        ),
      ]);

      final result = await h.sweeper.sweep(now: now);

      expect(result.isEmpty, isTrue,
          reason: 'closing this would end a workout under someone mid-set');
      expect(h.sessions.current.single.status, SessionStatus.active);
    });

    test('never touches the session a live screen has open', () async {
      final h = _harness([
        session(
          id: 'open',
          startedAt: _start,
          status: SessionStatus.active,
          workingSets: 3,
        ),
      ]);

      final result = await h.sweeper.sweep(
        now: _nextDay,
        exceptSessionId: 'open',
      );

      expect(result.isEmpty, isTrue);
      expect(h.sessions.current.single.status, SessionStatus.active);
    });

    test('honours the user configured maximum', () async {
      final now = _start.add(const Duration(hours: 5));
      List<LiveSession> seed() => [
        session(
          id: 'a',
          startedAt: _start,
          status: SessionStatus.active,
          workingSets: 3,
          lastSetAt: _start.add(const Duration(hours: 1)),
        ),
      ];

      final strict = _harness(seed(), maxMinutes: 180);
      expect((await strict.sweeper.sweep(now: now)).closed, hasLength(1));

      final loose = _harness(seed(), maxMinutes: 480);
      expect((await loose.sweeper.sweep(now: now)).isEmpty, isTrue);
    });

    test('leaves completed, abandoned and voided sessions alone', () async {
      final h = _harness([
        session(id: 'done', startedAt: _start),
        session(id: 'quit', startedAt: _start, status: SessionStatus.abandoned),
        session(id: 'void', startedAt: _start, status: SessionStatus.voided),
      ]);

      expect((await h.sweeper.sweep(now: _nextDay)).isEmpty, isTrue);
      expect(h.sessions.current, hasLength(3));
    });

    test('sweeps several left-open sessions in one pass', () async {
      final h = _harness([
        session(
          id: 'a',
          startedAt: _start,
          status: SessionStatus.active,
          workingSets: 2,
        ),
        session(
          id: 'b',
          startedAt: _start.subtract(const Duration(days: 3)),
          status: SessionStatus.active,
          workingSets: 0,
          pendingSets: 4,
        ),
      ]);

      final result = await h.sweeper.sweep(now: _nextDay);

      expect(result.closed.map((s) => s.id), ['a']);
      expect(result.deleted, ['b']);
    });

    test('is idempotent — a second sweep finds nothing left to do', () async {
      final h = _harness([
        session(
          id: 'a',
          startedAt: _start,
          status: SessionStatus.active,
          workingSets: 3,
        ),
      ]);

      await h.sweeper.sweep(now: _nextDay);
      expect((await h.sweeper.sweep(now: _nextDay)).isEmpty, isTrue);
    });
  });

  group('a stale session no longer hijacks up next', () {
    LiveSession stale() => session(
      id: 'a',
      startedAt: _start,
      status: SessionStatus.active,
      workingSets: 2,
      dayLabel: 'Push',
    );

    test('a fresh session still wins — the card mirrors what is under way', () {
      final selection = resolveUpNext(
        _plan(),
        stale(),
        now: _start.add(const Duration(minutes: 20)),
      );
      expect(selection.day!.id, 'day-a');
      expect(selection.resumable, isNotNull);
    });

    test('a session left open falls back to the day that is actually due', () {
      final selection = resolveUpNext(_plan(), stale(), now: _nextDay);
      expect(selection.day!.id, 'day-b', reason: 'the rotation, not Tuesday');
      expect(selection.resumable, isNull, reason: 'no stale Resume offered');
    });

    test('the fallback follows the user configured maximum', () {
      final now = _start.add(const Duration(hours: 5));
      expect(
        resolveUpNext(_plan(), stale(), now: now,
                maxSessionDuration: const Duration(hours: 3))
            .resumable,
        isNull,
      );
      expect(
        resolveUpNext(_plan(), stale(), now: now,
                maxSessionDuration: const Duration(hours: 8))
            .resumable,
        isNotNull,
      );
    });
  });
}
