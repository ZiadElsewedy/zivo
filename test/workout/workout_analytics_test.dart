import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

LiveSession _session({
  required String id,
  required DateTime at,
  required List<SessionExercise> exercises,
  SessionStatus status = SessionStatus.completed,
}) =>
    LiveSession(
      id: id,
      planId: 'plan-1',
      dayId: 'day-a',
      dayLabel: 'Push',
      startedAt: at.subtract(const Duration(minutes: 45)),
      completedAt: at,
      status: status,
      exercises: exercises,
    );

void main() {
  final now = DateTime(2026, 9, 2, 18);
  DateTime daysAgo(int d) => now.subtract(Duration(days: d));

  // Shared golden vectors — the SAME file the Node engine
  // (functions/ai/workout_analytics.test.js) runs, so the two can't drift.
  group('golden vectors', () {
    final vectors = jsonDecode(
      File('test/fixtures/workout_analytics_vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    test('estimated 1RM matches the Node engine', () {
      for (final spec in vectors['e1rm'] as List) {
        final m = spec as Map<String, dynamic>;
        final got = estimatedOneRepMax(
          (m['weightKg'] as num?)?.toDouble(),
          (m['reps'] as num?)?.toInt(),
        );
        final expected = (m['expected'] as num?)?.toDouble();
        if (expected == null) {
          expect(got, isNull, reason: '$spec');
        } else {
          expect(got, closeTo(expected, 0.001), reason: '$spec');
        }
      }
    });

    test('muscle normalization matches the Node engine', () {
      for (final spec in vectors['muscle'] as List) {
        final m = spec as Map<String, dynamic>;
        expect(normalizeMuscleGroup(m['raw'] as String?), m['expected'],
            reason: '$spec');
      }
    });

    test('strength-change guard matches the Node engine', () {
      for (final raw in vectors['strengthChange'] as List) {
        final v = raw as Map<String, dynamic>;
        final vnow = DateTime.parse(v['now'] as String);
        final id = v['exerciseId'] as String;
        final sessions = [
          for (final s in v['sessions'] as List)
            _session(
              id: (s as Map)['id'] as String,
              at: vnow.subtract(Duration(days: (s['daysAgo'] as num).toInt())),
              exercises: [
                _ex(id, [
                  for (final (i, x) in (s['sets'] as List).indexed)
                    _set('${s['id']}-$i',
                        reps: (x['reps'] as num?)?.toInt(),
                        weight: (x['weight'] as num?)?.toDouble()),
                ]),
              ],
            ),
        ];
        final e = analyzeTraining(sessions: sessions, now: vnow)
            .exercises
            .firstWhere((x) => x.exerciseId == id);
        final exp = v['expect'] as Map<String, dynamic>;
        expect(e.status.name, exp['status'], reason: v['name'] as String?);
        if (exp['strengthChangeNull'] == true) {
          expect(e.strengthChangePercent, isNull, reason: '${v['name']} null');
        } else {
          expect(e.strengthChangePercent,
              closeTo((exp['strengthChangeApprox'] as num).toDouble(), 0.5),
              reason: '${v['name']} approx');
        }
      }
    });
  });

  group('estimatedOneRepMax', () {
    test('Epley for multi-rep, bare weight for a single', () {
      expect(estimatedOneRepMax(100, 1), 100);
      // 100 * (1 + 5/30) = 116.67
      expect(estimatedOneRepMax(100, 5)!, closeTo(116.667, 0.01));
    });

    test('null for missing load, non-positive, or unreliable reps', () {
      expect(estimatedOneRepMax(null, 5), isNull);
      expect(estimatedOneRepMax(100, null), isNull);
      expect(estimatedOneRepMax(0, 5), isNull);
      expect(estimatedOneRepMax(100, 13), isNull); // above the reliability cap
    });
  });

  group('normalizeMuscleGroup', () {
    test('folds free text into major buckets', () {
      expect(normalizeMuscleGroup('Pecs'), 'Chest');
      expect(normalizeMuscleGroup('upper chest'), 'Chest');
      expect(normalizeMuscleGroup('Lats'), 'Back');
      expect(normalizeMuscleGroup('Quads'), 'Legs');
      expect(normalizeMuscleGroup('rear delts'), 'Shoulders');
      expect(normalizeMuscleGroup('Biceps'), 'Arms');
      expect(normalizeMuscleGroup('abs'), 'Core');
      expect(normalizeMuscleGroup('gibberish'), isNull);
      expect(normalizeMuscleGroup(null), isNull);
    });
  });

  group('warm-ups', () {
    test('are excluded from e1RM, volume, and PRs', () {
      // A heavy warm-up must not become the top set or a PR.
      final session = _session(id: 's1', at: daysAgo(1), exercises: [
        _ex('bench', [
          _set('w1', reps: 5, weight: 200, type: SetType.warmup),
          _set('a1', reps: 8, weight: 100),
        ]),
      ]);
      final prs = personalRecords([session])['bench']!;
      expect(prs[PrKind.heaviestWeight]!.weightKg, 100);
      expect(prs[PrKind.bestEstimatedStrength]!.weightKg, 100);
    });
  });

  group('analyzeTraining — empty', () {
    test('no completed sessions → building, not a guess', () {
      final analysis = analyzeTraining(sessions: const [], now: now);
      expect(analysis.isEmpty, isTrue);
      expect(analysis.overallStatus, ProgressStatus.building);
      expect(analysis.recentPrs, isEmpty);
    });
  });

  group('exercise progression', () {
    test('needs kMinAppearances before calling a direction', () {
      final sessions = [
        _session(id: 's1', at: daysAgo(20), exercises: [
          _ex('bench', [_set('a', reps: 8, weight: 100)]),
        ]),
        _session(id: 's2', at: daysAgo(10), exercises: [
          _ex('bench', [_set('a', reps: 8, weight: 105)]),
        ]),
      ];
      final analysis = analyzeTraining(sessions: sessions, now: now);
      final bench = analysis.exercises.firstWhere((e) => e.exerciseId == 'bench');
      expect(bench.appearances, 2);
      expect(bench.status, ProgressStatus.building);
    });

    test('rep-only increase at same weight counts as progression', () {
      // 100x8 -> 100x8 -> 100x10 -> 100x10 : progressing via reps/e1RM.
      final sessions = [
        _session(id: 's1', at: daysAgo(28), exercises: [
          _ex('bench', [_set('a', reps: 8, weight: 100)]),
        ]),
        _session(id: 's2', at: daysAgo(21), exercises: [
          _ex('bench', [_set('a', reps: 8, weight: 100)]),
        ]),
        _session(id: 's3', at: daysAgo(7), exercises: [
          _ex('bench', [_set('a', reps: 10, weight: 100)]),
        ]),
        _session(id: 's4', at: daysAgo(1), exercises: [
          _ex('bench', [_set('a', reps: 10, weight: 100)]),
        ]),
      ];
      final analysis = analyzeTraining(sessions: sessions, now: now);
      final bench = analysis.exercises.firstWhere((e) => e.exerciseId == 'bench');
      expect(bench.status, ProgressStatus.progressing);
      expect(bench.strengthChangePercent, greaterThan(0));
    });

    test('one fewer rep on one day does NOT read as regressing', () {
      // Steady 100x8, with a single 100x7 blip — best-of-window smooths it.
      final sessions = [
        _session(id: 's1', at: daysAgo(28), exercises: [
          _ex('bench', [_set('a', reps: 8, weight: 100)]),
        ]),
        _session(id: 's2', at: daysAgo(21), exercises: [
          _ex('bench', [_set('a', reps: 8, weight: 100)]),
        ]),
        _session(id: 's3', at: daysAgo(14), exercises: [
          _ex('bench', [_set('a', reps: 8, weight: 100)]),
        ]),
        _session(id: 's4', at: daysAgo(2), exercises: [
          _ex('bench', [_set('a', reps: 7, weight: 100)]),
        ]),
      ];
      final analysis = analyzeTraining(sessions: sessions, now: now);
      final bench = analysis.exercises.firstWhere((e) => e.exerciseId == 'bench');
      expect(bench.status, isNot(ProgressStatus.regressing));
    });

    test('flat across many sessions reads as plateauing', () {
      final sessions = [
        for (var i = 5; i >= 1; i--)
          _session(id: 's$i', at: daysAgo(i * 5), exercises: [
            _ex('bench', [_set('a', reps: 8, weight: 100)]),
          ]),
      ];
      final analysis = analyzeTraining(sessions: sessions, now: now);
      final bench = analysis.exercises.firstWhere((e) => e.exerciseId == 'bench');
      expect(bench.status, ProgressStatus.plateauing);
    });

    test('sustained decline reads as regressing', () {
      final sessions = [
        _session(id: 's1', at: daysAgo(28), exercises: [
          _ex('bench', [_set('a', reps: 8, weight: 110)]),
        ]),
        _session(id: 's2', at: daysAgo(21), exercises: [
          _ex('bench', [_set('a', reps: 8, weight: 108)]),
        ]),
        _session(id: 's3', at: daysAgo(7), exercises: [
          _ex('bench', [_set('a', reps: 8, weight: 100)]),
        ]),
        _session(id: 's4', at: daysAgo(1), exercises: [
          _ex('bench', [_set('a', reps: 8, weight: 98)]),
        ]),
      ];
      final analysis = analyzeTraining(sessions: sessions, now: now);
      final bench = analysis.exercises.firstWhere((e) => e.exerciseId == 'bench');
      expect(bench.status, ProgressStatus.regressing);
      expect(bench.strengthChangePercent, lessThan(0));
    });
  });

  group('PR detection', () {
    test('detects a new heaviest-weight PR against prior history', () {
      final prior = [
        _session(id: 's1', at: daysAgo(10), exercises: [
          _ex('bench', [_set('a', reps: 8, weight: 100)]),
        ]),
      ];
      final finished = _session(id: 's2', at: daysAgo(1), exercises: [
        _ex('bench', [_set('a', reps: 8, weight: 105)]),
      ]);
      final prs = detectNewPrs(session: finished, priorSessions: prior);
      expect(prs.any((p) => p.kind == PrKind.heaviestWeight && p.weightKg == 105), isTrue);
    });

    test('re-lifting the same load is NOT a PR', () {
      final prior = [
        _session(id: 's1', at: daysAgo(10), exercises: [
          _ex('bench', [_set('a', reps: 8, weight: 100)]),
        ]),
      ];
      final finished = _session(id: 's2', at: daysAgo(1), exercises: [
        _ex('bench', [_set('a', reps: 8, weight: 100)]),
      ]);
      final prs = detectNewPrs(session: finished, priorSessions: prior);
      expect(prs.where((p) => p.kind == PrKind.heaviestWeight), isEmpty);
    });

    test('a brand-new exercise\'s first session is a baseline, not a PR', () {
      final finished = _session(id: 's1', at: daysAgo(1), exercises: [
        _ex('bench', [_set('a', reps: 8, weight: 100)]),
      ]);
      final prs = detectNewPrs(session: finished, priorSessions: const []);
      expect(prs, isEmpty);
    });
  });

  group('volume', () {
    test('this week vs last week, working sets only', () {
      final sessions = [
        // Last week: 100 x 8 = 800
        _session(id: 's1', at: daysAgo(10), exercises: [
          _ex('bench', [_set('a', reps: 8, weight: 100)]),
        ]),
        // This week: 100 x 10 = 1000, plus a warm-up that must NOT count.
        _session(id: 's2', at: daysAgo(2), exercises: [
          _ex('bench', [
            _set('w', reps: 10, weight: 40, type: SetType.warmup),
            _set('a', reps: 10, weight: 100),
          ]),
        ]),
      ];
      final analysis = analyzeTraining(sessions: sessions, now: now);
      expect(analysis.volume.thisWeekKg, 1000);
      expect(analysis.volume.lastWeekKg, 800);
      expect(analysis.volume.changePercent!, closeTo(25, 0.001));
    });
  });
}
