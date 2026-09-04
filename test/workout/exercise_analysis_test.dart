import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/analytics/exercise_analysis.dart';
import 'package:zivo/features/workout/domain/analytics/workout_analytics.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_outcome.dart';
import 'package:zivo/features/workout/domain/set_type.dart';

// ---- Builders -------------------------------------------------------------

LoggedSet _set(
  String id, {
  int? reps,
  double? weight,
  SetType type = SetType.working,
  SetOutcome outcome = SetOutcome.completed,
}) =>
    LoggedSet(
      id: id,
      target: const RepTarget.range(6, 8),
      actualReps: reps,
      actualWeightKg: weight,
      type: type,
      outcome: outcome,
    );

SessionExercise _ex(
  String exerciseId,
  List<LoggedSet> sets, {
  String? name,
  String? muscleGroup,
}) =>
    SessionExercise(
      id: exerciseId,
      exerciseId: exerciseId,
      name: name ?? 'Exercise $exerciseId',
      muscleGroup: muscleGroup,
      restSeconds: 90,
      sets: sets,
    );

int _sign(double? x) => x == null ? 0 : (x > 0 ? 1 : (x < 0 ? -1 : 0));

/// Builds one session from a golden-vector spec `{id, daysAgo, sets:[{reps,weight}]}`.
LiveSession _fromSpec(Map<String, dynamic> s, DateTime now, String exerciseId) {
  final at = now.subtract(Duration(days: (s['daysAgo'] as num).toInt()));
  final sets = <LoggedSet>[
    for (final (i, x) in (s['sets'] as List).indexed)
      _set(
        '${s['id']}-$i',
        reps: (x['reps'] as num?)?.toInt(),
        weight: (x['weight'] as num?)?.toDouble(),
      ),
  ];
  return _session(id: s['id'] as String, at: at, exercises: [_ex(exerciseId, sets)]);
}

/// Asserts a session record's numeric fields against a vector's `expect` map.
void _assertRecord(ExerciseSessionRecord r, Map exp, String label) {
  exp.forEach((k, want) {
    switch (k) {
      case 'topWeightKg':
        expect(r.topWeightKg, want, reason: '$label topWeightKg');
      case 'topReps':
        expect(r.topReps, want, reason: '$label topReps');
      case 'totalReps':
        expect(r.totalReps, want, reason: '$label totalReps');
      case 'totalVolumeKg':
        expect(r.totalVolumeKg, (want as num).toDouble(),
            reason: '$label totalVolumeKg');
      case 'bestE1RM':
        expect(r.bestE1RM, closeTo((want as num).toDouble(), 0.01),
            reason: '$label bestE1RM');
      case 'workingSetCount':
        expect(r.workingSetCount, want, reason: '$label workingSetCount');
      case 'isPrSession':
        expect(r.isPrSession, want, reason: '$label isPrSession');
    }
  });
}

LiveSession _session({
  required String id,
  required DateTime at,
  required List<SessionExercise> exercises,
  SessionStatus status = SessionStatus.completed,
  String dayLabel = 'Push',
}) =>
    LiveSession(
      id: id,
      planId: 'plan-1',
      dayId: 'day-a',
      dayLabel: dayLabel,
      startedAt: at.subtract(const Duration(minutes: 45)),
      completedAt: at,
      status: status,
      exercises: exercises,
    );

void main() {
  final now = DateTime(2026, 9, 2, 18);
  DateTime daysAgo(int d) => now.subtract(Duration(days: d));

  // ---- Golden vectors (the SAME file the Node engine runs) ----------------
  group('golden vectors', () {
    final vectors = jsonDecode(
      File('test/fixtures/workout_analytics_vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    test('analyzeExercise matches the Node engine', () {
      for (final raw in vectors['exerciseAnalysis'] as List) {
        final v = raw as Map<String, dynamic>;
        final vnow = DateTime.parse(v['now'] as String);
        final exerciseId = v['exerciseId'] as String;
        final sessions = [
          for (final s in v['sessions'] as List)
            _fromSpec(s as Map<String, dynamic>, vnow, exerciseId),
        ];
        final a = analyzeExercise(
          exerciseId: exerciseId,
          sessions: sessions,
          now: vnow,
        )!;
        final e = v['expect'] as Map<String, dynamic>;
        final name = v['name'];

        expect(a.totalSessions, e['totalSessions'], reason: '$name sessions');
        if (e['status'] != null) {
          expect(a.status.name, e['status'], reason: '$name status');
        }
        if (e.containsKey('isWeighted')) {
          expect(a.isWeighted, e['isWeighted'], reason: '$name isWeighted');
        }
        if (e.containsKey('currentE1RM')) {
          if (e['currentE1RM'] == null) {
            expect(a.currentE1RM, isNull, reason: '$name currentE1RM');
          } else {
            expect(a.currentE1RM,
                closeTo((e['currentE1RM'] as num).toDouble(), 0.01),
                reason: '$name currentE1RM');
          }
        }
        if (e['latest'] != null) {
          _assertRecord(a.sessions.last, e['latest'] as Map, '$name latest');
        }
        if (e['previous'] != null) {
          _assertRecord(a.sessions[a.sessions.length - 2],
              e['previous'] as Map, '$name previous');
        }
        if (e['latestComparison'] != null) {
          final c = a.comparisons.last;
          final ec = e['latestComparison'] as Map;
          expect(c.tone.name, ec['tone'], reason: '$name tone');
          expect([for (final t in c.tags) t.name], ec['tags'],
              reason: '$name tags');
          expect(c.loadChangeKg, ec['loadChangeKg'], reason: '$name load');
          expect(c.topRepsChange, ec['topRepsChange'], reason: '$name reps');
          expect(_sign(c.e1rmChangePercent), ec['e1rmChangeSign'],
              reason: '$name e1rmSign');
          expect(_sign(c.volumeChangePercent), ec['volumeChangeSign'],
              reason: '$name volSign');
        }
      }
    });
  });

  group('analyzeExercise — no history', () {
    test('returns null when the exercise was never trained', () {
      final analysis = analyzeExercise(
        exerciseId: 'bench',
        sessions: const [],
        now: now,
      );
      expect(analysis, isNull);
    });

    test('ignores incomplete sessions and warm-up-only work', () {
      final sessions = [
        _session(
          id: 's1',
          at: daysAgo(2),
          status: SessionStatus.active, // not completed
          exercises: [_ex('bench', [_set('a', reps: 8, weight: 40)])],
        ),
        _session(
          id: 's2',
          at: daysAgo(1),
          exercises: [
            _ex('bench', [_set('b', reps: 8, weight: 40, type: SetType.warmup)]),
          ],
        ),
      ];
      expect(
        analyzeExercise(exerciseId: 'bench', sessions: sessions, now: now),
        isNull,
      );
    });
  });

  group('session records', () {
    test('reduces working sets into the coach metrics', () {
      final sessions = [
        _session(
          id: 's1',
          at: daysAgo(1),
          exercises: [
            _ex('bench', [
              _set('w', reps: 5, weight: 20, type: SetType.warmup), // excluded
              _set('a', reps: 8, weight: 40),
              _set('b', reps: 10, weight: 35),
            ]),
          ],
        ),
      ];
      final a = analyzeExercise(exerciseId: 'bench', sessions: sessions, now: now)!;
      final r = a.sessions.single;
      expect(r.workingSetCount, 2, reason: 'warm-up excluded');
      expect(r.topWeightKg, 40);
      expect(r.topReps, 10);
      expect(r.totalReps, 18);
      expect(r.totalVolumeKg, 8 * 40 + 10 * 35); // 640
      expect(r.avgLoadKg, closeTo((8 * 40 + 10 * 35) / 18, 0.001));
      expect(r.repRange, (8, 10));
      // Top set is the 40kg set.
      expect(r.sets.where((s) => s.isTopSet).single.weightKg, 40);
    });
  });

  group("the brief's headline case: 40×7 vs 35×10", () {
    // Last week: 35×8, 35×10.  This week: 40×7, 40×7, 37×6.
    late ExerciseAnalysis a;
    setUp(() {
      final sessions = [
        _session(
          id: 'last',
          at: daysAgo(7),
          exercises: [
            _ex('incline', [
              _set('a', reps: 8, weight: 35),
              _set('b', reps: 10, weight: 35),
            ], name: 'Incline DB Press'),
          ],
        ),
        _session(
          id: 'this',
          at: daysAgo(1),
          exercises: [
            _ex('incline', [
              _set('a', reps: 7, weight: 40),
              _set('b', reps: 7, weight: 40),
              _set('c', reps: 6, weight: 37),
            ], name: 'Incline DB Press'),
          ],
        ),
      ];
      a = analyzeExercise(exerciseId: 'incline', sessions: sessions, now: now)!;
    });

    test('the latest session-to-session step reads as an improvement', () {
      final c = a.latestComparison!;
      expect(c.tone, ExerciseTrendTone.improved,
          reason: 'heavier load outweighs the lower reps');
      expect(c.e1rmChangePercent, greaterThan(0));
      expect(c.loadChangeKg, closeTo(5, 0.001)); // 35 → 40
      expect(c.topRepsChange, -3); // 10 → 7
      expect(c.volumeChangePercent, greaterThan(0)); // 630 → 782
      expect(c.tags, contains(SessionChange.strengthUp));
      expect(c.tags, contains(SessionChange.loadUp));
      expect(c.tags, contains(SessionChange.repsDown));
      expect(c.tags, contains(SessionChange.newPr));
    });

    test('volume is NOT the sole definition of progress', () {
      // Strength (e1RM) is the lead signal, not raw tonnage.
      final c = a.latestComparison!;
      expect(c.e1rmChangeKg, greaterThan(0));
      expect(a.currentE1RM, greaterThan(a.sessions.first.bestE1RM!));
    });

    test('two sessions is still "building" — no windowed direction yet', () {
      expect(a.status, ProgressStatus.building);
    });

    test('insight is grounded in the numbers (what happened → why → do)', () {
      final i = a.insight;
      expect(i.whatHappened, contains('35'));
      expect(i.whatHappened, contains('40'));
      expect(i.whatToDo, isNotEmpty);
    });
  });

  group('a real upward trend across 3 sessions', () {
    test('reads as progressing with an intensity-led insight', () {
      final sessions = [
        _session(
          id: 's1',
          at: daysAgo(14),
          exercises: [
            _ex('incline', [_set('a', reps: 8, weight: 30)], name: 'Incline'),
          ],
        ),
        _session(
          id: 's2',
          at: daysAgo(7),
          exercises: [
            _ex('incline', [
              _set('a', reps: 8, weight: 35),
              _set('b', reps: 10, weight: 35),
            ], name: 'Incline'),
          ],
        ),
        _session(
          id: 's3',
          at: daysAgo(1),
          exercises: [
            _ex('incline', [
              _set('a', reps: 7, weight: 40),
              _set('b', reps: 7, weight: 40),
            ], name: 'Incline'),
          ],
        ),
      ];
      final a =
          analyzeExercise(exerciseId: 'incline', sessions: sessions, now: now)!;
      expect(a.status, ProgressStatus.progressing);
      expect(a.strengthChangePercent, greaterThan(0));
      expect(a.insight.tone, ProgressStatus.progressing);
      expect(a.insight.whyItMatters, contains('1RM'));
      expect(a.comparisons.length, 2);
      expect(a.nextStep, isNotNull);
    });
  });

  group('intensity vs volume trade-off', () {
    test('lighter-but-far-more-volume reads as mixed, not a clean win', () {
      final sessions = [
        _session(
          id: 's1',
          at: daysAgo(4),
          exercises: [
            _ex('squat', [_set('a', reps: 5, weight: 100)]), // e1RM ~116.7
          ],
        ),
        _session(
          id: 's2',
          at: daysAgo(1),
          exercises: [
            _ex('squat', [
              _set('a', reps: 12, weight: 80), // e1RM 112, big volume
              _set('b', reps: 12, weight: 80),
            ]),
          ],
        ),
      ];
      final a =
          analyzeExercise(exerciseId: 'squat', sessions: sessions, now: now)!;
      final c = a.latestComparison!;
      expect(c.tone, ExerciseTrendTone.mixed,
          reason: 'volume up sharply but top-end intensity down');
      expect(c.volumeChangePercent, greaterThan(0));
      expect(c.e1rmChangePercent, lessThan(0));
    });
  });

  group('bodyweight / unloaded movement', () {
    test('judged on reps and volume, not e1RM', () {
      final sessions = [
        _session(
          id: 's1',
          at: daysAgo(3),
          exercises: [
            _ex('pullup', [_set('a', reps: 8), _set('b', reps: 8)]),
          ],
        ),
        _session(
          id: 's2',
          at: daysAgo(1),
          exercises: [
            _ex('pullup', [_set('a', reps: 10), _set('b', reps: 10)]),
          ],
        ),
      ];
      final a =
          analyzeExercise(exerciseId: 'pullup', sessions: sessions, now: now)!;
      expect(a.isWeighted, isFalse);
      expect(a.latestComparison!.tone, ExerciseTrendTone.improved);
      expect(a.currentE1RM, isNull);
    });
  });

  group('PR detection along the timeline', () {
    test('first appearance is a baseline, later best is a PR session', () {
      final sessions = [
        _session(
          id: 's1',
          at: daysAgo(5),
          exercises: [_ex('ohp', [_set('a', reps: 5, weight: 40)])],
        ),
        _session(
          id: 's2',
          at: daysAgo(1),
          exercises: [_ex('ohp', [_set('a', reps: 5, weight: 45)])],
        ),
      ];
      final a = analyzeExercise(exerciseId: 'ohp', sessions: sessions, now: now)!;
      expect(a.sessions.first.isPrSession, isFalse, reason: 'baseline');
      expect(a.sessions.last.isPrSession, isTrue, reason: 'beat the first');
      expect(a.records[PrKind.heaviestWeight]!.weightKg, 45);
    });
  });
}
