import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/util/calendar.dart';
import 'package:zivo/features/workout/domain/training_days.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';

/// The Dart half of the shared training-day golden vectors. The SAME
/// `test/fixtures/training_days_vectors.json` is run by
/// `functions/ai/analytics/training_days.test.js`, so what Today shows and what
/// the AI coach is told about planned vs actual days cannot drift.
WorkoutPlan _plan(Map<String, dynamic> raw) {
  final created = dayFromKey(raw['createdDay'] as String)!;
  return WorkoutPlan(
    id: 'p',
    name: 'Vectors',
    status: WorkoutPlanStatus.active,
    source: WorkoutPlanSource.manual,
    createdAt: created,
    updatedAt: created,
    cycleCursor: raw['cycleCursor'] as int,
    days: [
      for (final d in (raw['days'] as List).cast<Map<String, dynamic>>())
        WorkoutDay(
          id: d['id'] as String,
          slot: d['id'] as String,
          label: d['label'] as String,
          order: d['order'] as int,
          type: trainingDayTypeFromName(d['type'] as String?),
          exercises: const [],
        ),
    ],
  );
}

Map<String, dynamic> _summary(TrainingDaySummary s) => {
  'days': s.days,
  'schedulesRest': s.schedulesRest,
  'plannedWorkouts': s.plannedWorkouts,
  'completed': s.completed,
  'missed': s.missed,
  'userRest': s.userRest,
  'plannedRest': s.plannedRest,
  'extraWorkouts': s.extraWorkouts,
  'unscheduled': s.unscheduled,
  'trainingDaysPerWeek': s.trainingDaysPerWeek,
  'plannedTrainingDaysPerWeek': s.plannedTrainingDaysPerWeek,
  'skippedByDayId': s.skippedByDayId,
  'weeks': [
    for (final w in s.weeks)
      {
        'start': dayKey(w.start),
        'trainedDays': w.trainedDays,
        'userRestDays': w.userRestDays,
        'missedDays': w.missedDays,
        'plannedRestDays': w.plannedRestDays,
      },
  ],
};

/// JSON numbers: 4 and 4.0 are the same figure.
Object? _normalize(Object? v) => switch (v) {
  num n => n.toDouble(),
  Map m => {for (final e in m.entries) e.key: _normalize(e.value)},
  List l => [for (final x in l) _normalize(x)],
  _ => v,
};

void main() {
  final vectors =
      jsonDecode(
            File('test/fixtures/training_days_vectors.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('golden vectors: every case matches the shared engine', () {
    final cases = (vectors['cases'] as List).cast<Map<String, dynamic>>();
    expect(cases, isNotEmpty);
    for (final vec in cases) {
      final input = vec['input'] as Map<String, dynamic>;
      final plan = _plan(input['plan'] as Map<String, dynamic>);
      final records = classifyTrainingDayRecords(
        plan: plan,
        inputs: TrainingDayInputs(
          trainedDayIds: {
            for (final e in (input['trainedDayIds'] as Map).entries)
              dayFromKey(e.key as String)!: (e.value as List).cast<String>(),
          },
          userRestDays: {
            for (final k in (input['userRestDays'] as List).cast<String>())
              dayFromKey(k)!,
          },
        ),
        from: dayFromKey(input['from'] as String)!,
        today: dayFromKey(input['today'] as String)!,
      );
      final expected = vec['expected'] as Map<String, dynamic>;
      expect(
        [
          for (final r in records)
            {
              'day': dayKey(r.day),
              'planned': r.planned.name,
              'outcome': r.outcome.name,
              'dueDayId': r.dueDayId,
            },
        ],
        expected['records'],
        reason: '${vec['name']}: records',
      );
      expect(
        _normalize(_summary(summarizeTrainingDays(plan, records))),
        _normalize(expected['summary']),
        reason: '${vec['name']}: summary',
      );
    }
  });
}
