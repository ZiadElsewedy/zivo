import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/day_progress_analysis.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/progress_comparison.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';

const _planId = 'plan-1';

WorkoutDay _dayWith(List<PlannedExercise> exercises) =>
    WorkoutDay(id: 'day-a', slot: 'A', label: 'Push', order: 0, exercises: exercises);

PlannedExercise _plannedEx(String id, {int sets = 1}) => PlannedExercise(
  id: id,
  name: 'Exercise $id',
  order: 0,
  defaultRestSeconds: 90,
  sets: [
    for (var i = 0; i < sets; i++)
      PlannedSet(order: i, repTarget: RepTarget.range(8, 10), restSeconds: 90, type: SetType.working),
  ],
);

LoggedSet _set(String id, {int? reps, double? weight, bool done = true}) => LoggedSet(
  id: id,
  target: RepTarget.range(8, 10),
  actualReps: reps,
  actualWeightKg: weight,
  done: done,
);

LiveSession _session({
  required String id,
  String planId = _planId,
  String dayId = 'day-a',
  required DateTime completedAt,
  required List<SessionExercise> exercises,
  SessionStatus status = SessionStatus.completed,
}) => LiveSession(
  id: id,
  planId: planId,
  dayId: dayId,
  dayLabel: 'Push',
  startedAt: completedAt.subtract(const Duration(minutes: 45)),
  completedAt: completedAt,
  status: status,
  exercises: exercises,
);

SessionExercise _sessionEx(String exerciseId, List<LoggedSet> sets) =>
    SessionExercise(id: exerciseId, exerciseId: exerciseId, name: 'Exercise $exerciseId', restSeconds: 90, sets: sets);

void main() {
  group('analyzeDayProgress', () {
    test('no completed sessions for the day → empty analysis', () {
      final day = _dayWith([_plannedEx('e1')]);
      final result = analyzeDayProgress(day: day, planId: _planId, allSessions: const []);

      expect(result.sessionCount, 0);
      expect(result.overallVerdict, isNull);
      expect(result.exercises.single.verdict, isNull);
      expect(result.exercises.single.appearances, 0);
    });

    test('a single completed session → first-time state, no verdict', () {
      final day = _dayWith([_plannedEx('e1')]);
      final session = _session(
        id: 's1',
        completedAt: DateTime(2026, 1, 1),
        exercises: [
          _sessionEx('e1', [_set('e1-s0', reps: 8, weight: 40)]),
        ],
      );

      final result = analyzeDayProgress(day: day, planId: _planId, allSessions: [session]);

      expect(result.sessionCount, 1);
      expect(result.overallVerdict, isNull);
      final ex = result.exercises.single;
      expect(ex.verdict, isNull);
      expect(ex.appearances, 1);
      expect(ex.lastTopWeightKg, 40);
      expect(ex.trend, hasLength(1));
    });

    test('weight + reps increase week over week → progressing, correct deltas', () {
      final day = _dayWith([_plannedEx('e1')]);
      final previous = _session(
        id: 's1',
        completedAt: DateTime(2026, 1, 1),
        exercises: [
          _sessionEx('e1', [_set('e1-s0', reps: 8, weight: 40)]),
        ],
      );
      final last = _session(
        id: 's2',
        completedAt: DateTime(2026, 1, 8),
        exercises: [
          _sessionEx('e1', [_set('e1-s0', reps: 10, weight: 42.5)]),
        ],
      );

      final result = analyzeDayProgress(day: day, planId: _planId, allSessions: [previous, last]);

      expect(result.sessionCount, 2);
      final ex = result.exercises.single;
      expect(ex.verdict, ProgressVerdict.progressing);
      expect(ex.weightChangeKg, closeTo(2.5, 0.001));
      expect(ex.repsChangePercent, closeTo(25.0, 0.001)); // (10-8)/8*100
      // volume: prev 8*40=320, last 10*42.5=425 → +32.8125%
      expect(ex.volumeChangePercent, closeTo(32.8125, 0.001));
      expect(result.improvedCount, 1);
      expect(result.matchedCount, 0);
      expect(result.regressedCount, 0);
      expect(result.overallVerdict, ProgressVerdict.progressing);
    });

    test('identical reps + weight → matched', () {
      final day = _dayWith([_plannedEx('e1')]);
      final sets = [_set('e1-s0', reps: 8, weight: 40)];
      final previous = _session(
        id: 's1',
        completedAt: DateTime(2026, 1, 1),
        exercises: [_sessionEx('e1', sets)],
      );
      final last = _session(
        id: 's2',
        completedAt: DateTime(2026, 1, 8),
        exercises: [_sessionEx('e1', [_set('e1-s0', reps: 8, weight: 40)])],
      );

      final result = analyzeDayProgress(day: day, planId: _planId, allSessions: [previous, last]);

      expect(result.exercises.single.verdict, ProgressVerdict.matched);
      expect(result.matchedCount, 1);
      expect(result.overallVerdict, ProgressVerdict.matched);
    });

    test('weight drop → down', () {
      final day = _dayWith([_plannedEx('e1')]);
      final previous = _session(
        id: 's1',
        completedAt: DateTime(2026, 1, 1),
        exercises: [
          _sessionEx('e1', [_set('e1-s0', reps: 8, weight: 40)]),
        ],
      );
      final last = _session(
        id: 's2',
        completedAt: DateTime(2026, 1, 8),
        exercises: [
          _sessionEx('e1', [_set('e1-s0', reps: 8, weight: 35)]),
        ],
      );

      final result = analyzeDayProgress(day: day, planId: _planId, allSessions: [previous, last]);

      expect(result.exercises.single.verdict, ProgressVerdict.down);
      expect(result.regressedCount, 1);
      expect(result.overallVerdict, ProgressVerdict.down);
    });

    test('exercise skipped in one of the day\'s two sessions → still only 1 appearance', () {
      final day = _dayWith([_plannedEx('e1'), _plannedEx('e2')]);
      final s1 = _session(
        id: 's1',
        completedAt: DateTime(2026, 1, 1),
        exercises: [
          _sessionEx('e1', [_set('e1-s0', reps: 8, weight: 40)]),
          _sessionEx('e2', [_set('e2-s0', reps: 8, weight: 20)]),
        ],
      );
      // e2 skipped this time (not done → doesn't count as an appearance).
      final s2 = _session(
        id: 's2',
        completedAt: DateTime(2026, 1, 8),
        exercises: [
          _sessionEx('e1', [_set('e1-s0', reps: 9, weight: 42.5)]),
          _sessionEx('e2', [_set('e2-s0', reps: null, weight: null, done: false)]),
        ],
      );

      final result = analyzeDayProgress(day: day, planId: _planId, allSessions: [s1, s2]);
      final e1 = result.exercises.firstWhere((e) => e.exerciseId == 'e1');
      final e2 = result.exercises.firstWhere((e) => e.exerciseId == 'e2');

      expect(e1.appearances, 2);
      expect(e1.verdict, isNotNull);
      expect(e2.appearances, 1);
      expect(e2.verdict, isNull);
    });

    test('set count differs between sessions → compares only the overlapping sets', () {
      final day = _dayWith([_plannedEx('e1', sets: 3)]);
      final previous = _session(
        id: 's1',
        completedAt: DateTime(2026, 1, 1),
        exercises: [
          _sessionEx('e1', [_set('e1-s0', reps: 8, weight: 40)]),
        ],
      );
      final last = _session(
        id: 's2',
        completedAt: DateTime(2026, 1, 8),
        exercises: [
          _sessionEx('e1', [
            _set('e1-s0', reps: 9, weight: 42.5),
            _set('e1-s1', reps: 9, weight: 42.5),
          ]),
        ],
      );

      // Should not throw despite the mismatched set counts, and compares
      // only the first (overlapping) set.
      final result = analyzeDayProgress(day: day, planId: _planId, allSessions: [previous, last]);
      expect(result.exercises.single.verdict, ProgressVerdict.progressing);
    });

    test('bodyweight exercise (no weight ever logged) → reps-driven verdict, null weight/volume deltas', () {
      final day = _dayWith([_plannedEx('e1')]);
      final previous = _session(
        id: 's1',
        completedAt: DateTime(2026, 1, 1),
        exercises: [
          _sessionEx('e1', [_set('e1-s0', reps: 10, weight: null)]),
        ],
      );
      final last = _session(
        id: 's2',
        completedAt: DateTime(2026, 1, 8),
        exercises: [
          _sessionEx('e1', [_set('e1-s0', reps: 12, weight: null)]),
        ],
      );

      final result = analyzeDayProgress(day: day, planId: _planId, allSessions: [previous, last]);
      final ex = result.exercises.single;

      expect(ex.weightChangeKg, isNull);
      expect(ex.volumeChangePercent, isNull);
      expect(ex.repsChangePercent, closeTo(20.0, 0.001));
      expect(ex.verdict, ProgressVerdict.progressing);
    });

    test('trend is oldest-to-newest and capped at trendLength', () {
      final day = _dayWith([_plannedEx('e1')]);
      final sessions = [
        for (var w = 0; w < 8; w++)
          _session(
            id: 's$w',
            completedAt: DateTime(2026, 1, 1).add(Duration(days: w * 7)),
            exercises: [
              _sessionEx('e1', [_set('e1-s0', reps: 8, weight: 40.0 + w)]),
            ],
          ),
      ];

      final result = analyzeDayProgress(day: day, planId: _planId, allSessions: sessions, trendLength: 3);
      final trend = result.exercises.single.trend;

      expect(trend, hasLength(3));
      // The 3 most recent sessions (weeks 5,6,7 → weights 45,46,47), oldest-first.
      expect(trend.map((p) => p.topWeightKg), [45.0, 46.0, 47.0]);
    });

    test('sessions from another plan, another day, or not completed are excluded', () {
      final day = _dayWith([_plannedEx('e1')]);
      final wrongPlan = _session(
        id: 's1',
        planId: 'other-plan',
        completedAt: DateTime(2026, 1, 1),
        exercises: [
          _sessionEx('e1', [_set('e1-s0', reps: 8, weight: 40)]),
        ],
      );
      final wrongDay = _session(
        id: 's2',
        dayId: 'day-b',
        completedAt: DateTime(2026, 1, 2),
        exercises: [
          _sessionEx('e1', [_set('e1-s0', reps: 8, weight: 40)]),
        ],
      );
      final abandoned = _session(
        id: 's3',
        completedAt: DateTime(2026, 1, 3),
        status: SessionStatus.abandoned,
        exercises: [
          _sessionEx('e1', [_set('e1-s0', reps: 8, weight: 40)]),
        ],
      );

      final result = analyzeDayProgress(
        day: day,
        planId: _planId,
        allSessions: [wrongPlan, wrongDay, abandoned],
      );

      expect(result.sessionCount, 0);
    });
  });
}
