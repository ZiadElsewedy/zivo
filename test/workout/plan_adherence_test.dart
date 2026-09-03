import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/analytics/plan_adherence.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_outcome.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';

PlannedExercise _planned(String id, {String? name}) => PlannedExercise(
      id: id,
      name: name ?? 'Exercise $id',
      order: 0,
      defaultRestSeconds: 90,
      sets: const [
        PlannedSet(
          order: 0,
          repTarget: RepTarget.range(6, 8),
          restSeconds: 90,
          type: SetType.working,
        ),
      ],
    );

WorkoutPlan _plan(Map<String, List<PlannedExercise>> byDay) {
  var order = 0;
  final days = <WorkoutDay>[
    for (final entry in byDay.entries)
      WorkoutDay(
        id: 'day-${entry.key}',
        slot: entry.key,
        label: entry.key,
        order: order++,
        exercises: entry.value,
      ),
  ];
  return WorkoutPlan(
    id: 'plan-1',
    name: 'PPL',
    status: WorkoutPlanStatus.active,
    source: WorkoutPlanSource.manual,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    days: days,
  );
}

LiveSession _did(String exerciseId, DateTime at) => LiveSession(
      id: 'sess-$exerciseId-${at.millisecondsSinceEpoch}',
      planId: 'plan-1',
      dayId: 'day-a',
      dayLabel: 'Push',
      startedAt: at.subtract(const Duration(minutes: 30)),
      completedAt: at,
      status: SessionStatus.completed,
      exercises: [
        SessionExercise(
          id: exerciseId,
          exerciseId: exerciseId,
          name: 'Exercise $exerciseId',
          restSeconds: 90,
          sets: [
            LoggedSet(
              id: 's',
              target: const RepTarget.range(6, 8),
              actualReps: 8,
              actualWeightKg: 40,
              outcome: SetOutcome.completed,
            ),
          ],
        ),
      ],
    );

void main() {
  final now = DateTime(2026, 9, 2, 18);
  DateTime daysAgo(int d) => now.subtract(Duration(days: d));

  test('golden vectors: analyzePlanAdherence matches the Node engine', () {
    final vectors = jsonDecode(
      File('test/fixtures/workout_analytics_vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final raw in vectors['planAdherence'] as List) {
      final v = raw as Map<String, dynamic>;
      final vnow = DateTime.parse(v['now'] as String);
      final byDay = <String, List<PlannedExercise>>{};
      for (final d in (v['plan'] as Map)['days'] as List) {
        byDay[(d as Map)['label'] as String] = [
          for (final ex in d['exercises'] as List)
            _planned((ex as Map)['id'] as String, name: ex['name'] as String?),
        ];
      }
      final sessions = [
        for (final t in v['trained'] as List)
          _did((t as Map)['exerciseId'] as String,
              vnow.subtract(Duration(days: (t['daysAgo'] as num).toInt()))),
      ];
      final a = analyzePlanAdherence(
          plan: _plan(byDay), sessions: sessions, now: vnow);
      final exp = v['expect'] as Map<String, dynamic>;
      expect(a.plannedExerciseCount, exp['plannedExerciseCount'],
          reason: v['name'] as String?);
      final neglected = exp['neglected'] as List;
      expect(a.neglected.length, neglected.length, reason: '${v['name']} count');
      for (final (i, e) in neglected.indexed) {
        final ex = e as Map;
        expect(a.neglected[i].exerciseId, ex['exerciseId'], reason: '[$i] id');
        expect(a.neglected[i].reason.name, ex['reason'], reason: '[$i] reason');
        expect(a.neglected[i].daysSinceLast, ex['daysSinceLast'],
            reason: '[$i] days');
      }
    }
  });

  test('no plan → empty adherence', () {
    final a = analyzePlanAdherence(plan: null, sessions: const [], now: now);
    expect(a.isEmpty, isTrue);
    expect(a.plannedExerciseCount, 0);
  });

  test('a plan with no training history is not yet skipping anything', () {
    final plan = _plan({
      'Push': [_planned('bench'), _planned('ohp')],
    });
    final a = analyzePlanAdherence(plan: plan, sessions: const [], now: now);
    expect(a.neglected, isEmpty);
    expect(a.plannedExerciseCount, 2);
  });

  test('flags never-trained and stale planned movements', () {
    final plan = _plan({
      'Push': [_planned('bench'), _planned('ohp'), _planned('fly')],
    });
    final sessions = [
      _did('bench', daysAgo(2)), // recent → adherent
      _did('ohp', daysAgo(20)), // > 14 days → stale
      // 'fly' never trained
    ];
    final a = analyzePlanAdherence(plan: plan, sessions: sessions, now: now);

    expect(a.plannedExerciseCount, 3);
    expect(a.neglected.length, 2);
    // Never-trained sorts first.
    expect(a.neglected.first.exerciseId, 'fly');
    expect(a.neglected.first.reason, AdherenceReason.neverTrained);
    expect(a.neglected.first.daysSinceLast, isNull);

    final ohp = a.neglected[1];
    expect(ohp.exerciseId, 'ohp');
    expect(ohp.reason, AdherenceReason.stale);
    expect(ohp.daysSinceLast, 20);
    expect(ohp.appearances, 1);
  });

  test('a movement trained within the window is not flagged', () {
    final plan = _plan({
      'Push': [_planned('bench')],
    });
    final a = analyzePlanAdherence(
      plan: plan,
      sessions: [_did('bench', daysAgo(3))],
      now: now,
    );
    expect(a.neglected, isEmpty);
  });

  test('a movement on two days is counted once (first day label wins)', () {
    final plan = _plan({
      'Push': [_planned('bench')],
      'Upper': [_planned('bench')],
    });
    final a = analyzePlanAdherence(
      plan: plan,
      sessions: [_did('other', daysAgo(1))], // trained something, not bench
      now: now,
    );
    expect(a.plannedExerciseCount, 1);
    expect(a.neglected.length, 1);
    expect(a.neglected.single.dayLabel, 'Push');
  });
}
