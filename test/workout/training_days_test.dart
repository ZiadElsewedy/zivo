import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/util/calendar.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/training_day_mark.dart';
import 'package:zivo/features/workout/domain/training_days.dart';
import 'package:zivo/features/workout/domain/training_streak.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_import_result.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_from_import.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/presentation/controllers/plan_edit_controller.dart';

import '../support/workout_fixtures.dart';

// Plan created on Monday 2026-09-07; "today" is a Wednesday at noon.
final _created = DateTime(2026, 9, 7, 8);
DateTime _day(int n) => addCalendarDays(DateTime(2026, 9, 7), n);
DateTime _noon(int n) => _day(n).add(const Duration(hours: 12));

WorkoutDay _workout(String id, int order) => WorkoutDay(
  id: id,
  slot: id,
  label: id.toUpperCase(),
  order: order,
  exercises: const [],
);

WorkoutDay _rest(String id, int order) => WorkoutDay(
  id: id,
  slot: id,
  label: 'Rest',
  order: order,
  type: TrainingDayType.rest,
  exercises: const [],
);

/// Upper → Lower → Rest → Push → Pull → Rest → Rest.
WorkoutPlan _plan({int cursor = 0, List<WorkoutDay>? days}) => WorkoutPlan(
  id: 'p1',
  name: 'Split',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.pdf,
  createdAt: _created,
  updatedAt: _created,
  cycleCursor: cursor,
  days:
      days ??
      [
        _workout('up', 0),
        _workout('lo', 1),
        _rest('r1', 2),
        _workout('pu', 3),
        _workout('pl', 4),
        _rest('r2', 5),
        _rest('r3', 6),
      ],
);

LiveSession _trained(int dayN, String dayId) =>
    session(id: '$dayN-$dayId', startedAt: _noon(dayN), dayId: dayId);

TrainingDayMark _choseRest(int dayN) => TrainingDayMark(
  day: _day(dayN),
  createdAt: _noon(dayN),
  reason: MissedDayReason.rest,
);

List<DayOutcome> _outcomes(
  WorkoutPlan plan,
  List<LiveSession> sessions, {
  List<TrainingDayMark> marks = const [],
  required int today,
}) => [
  for (final r in classifyTrainingDays(
    plan: plan,
    sessions: sessions,
    marks: marks,
    from: _created,
    today: _noon(today),
  ))
    r.outcome,
];

void main() {
  group('rest is a first-class day type', () {
    test('an imported plan keeps its rest day as a rest day', () {
      final plan = workoutPlanFromImport(
        const WorkoutImportResult(
          planName: 'UL',
          days: [
            ImportedDay(slot: 'A', label: 'Upper', exercises: []),
            ImportedDay(
              slot: 'B',
              label: 'Rest',
              isRest: true,
              exercises: [
                ImportedExercise(name: 'Stray', sets: 3, toFailure: false),
              ],
            ),
          ],
        ),
        id: 'imp',
        now: _created,
      );
      expect(plan.days[1].type, TrainingDayType.rest);
      expect(plan.days[1].exercises, isEmpty, reason: 'rest carries nothing');
      expect(plan.days[0].type, TrainingDayType.workout);
    });

    test('a planned rest day is never the workout up next', () {
      // Cursor sits on the rest slot after Lower: the next WORKOUT is Push.
      final plan = _plan(cursor: 2);
      expect(plan.nextDay?.id, 'pu');
      expect(plan.workoutDays.map((d) => d.id), ['up', 'lo', 'pu', 'pl']);
      expect(plan.restDaysAfter('pl'), 2);
      expect(plan.restDaysAfter('up'), 0);
      expect(plan.workoutAfter('pl')?.id, 'up');
    });

    test('a rest day cannot be swapped with a workout', () {
      final plan = _plan();
      expect(identical(plan.swapDays('up', 'r1'), plan), isTrue);
    });

    test('the split editor saves a rest day and never gives it exercises', () {
      final c = PlanEditController(asSplit: true)
        ..name.text = 'UL'
        ..addDay(
          DayDraft(
            id: 'r',
            slot: 'A',
            label: 'Rest',
            type: TrainingDayType.rest,
          ),
        );
      expect(c.canSave, isFalse, reason: 'rest days alone are not a split');
      c.addDay(DayDraft(id: 'w', slot: 'B', label: 'Upper'));
      expect(c.canSave, isTrue);
      final plan = c.buildPlan(now: _created);
      expect(plan.days.first.isRest, isTrue);
      expect(plan.days.first.exercises, isEmpty);
      c.dispose();
    });
  });

  group('planned vs actual', () {
    test('planned rest is planned rest, never a missed workout', () {
      // Mon Upper, Tue Lower, Wed (planned rest), Thu Push, Fri Pull.
      final outcomes = _outcomes(_plan(cursor: 5), [
        _trained(0, 'up'),
        _trained(1, 'lo'),
        _trained(3, 'pu'),
        _trained(4, 'pl'),
      ], today: 6);
      expect(outcomes, [
        DayOutcome.completed,
        DayOutcome.completed,
        DayOutcome.plannedRest,
        DayOutcome.completed,
        DayOutcome.completed,
        DayOutcome.plannedRest, // Sat
        DayOutcome.plannedRest, // Sun — today, still rest
      ]);
    });

    test('planned workout + no action is a MISSED workout, not rest', () {
      final outcomes = _outcomes(_plan(cursor: 1), [
        _trained(0, 'up'),
      ], today: 3);
      expect(outcomes, [
        DayOutcome.completed,
        DayOutcome.missed,
        DayOutcome.missed,
        DayOutcome.pending, // today is not over
      ]);
    });

    test('planned workout + the user chose rest is user-selected rest', () {
      final records = classifyTrainingDays(
        plan: _plan(cursor: 1),
        sessions: [_trained(0, 'up')],
        marks: [_choseRest(1)],
        from: _created,
        today: _noon(1),
      );
      expect(records.last.outcome, DayOutcome.userRest);
      expect(records.last.planned, TrainingDayType.workout);
      expect(records.last.dueDayId, 'lo', reason: 'the plan still says Lower');
    });

    test('a reason other than rest leaves the day missed (context only)', () {
      final outcomes = _outcomes(
        _plan(cursor: 1),
        [_trained(0, 'up')],
        marks: [
          TrainingDayMark(
            day: _day(1),
            createdAt: _noon(1),
            reason: MissedDayReason.travel,
          ),
        ],
        today: 2,
      );
      expect(outcomes[1], DayOutcome.missed);
    });

    test('planned workout + a workout is completed', () {
      expect(_outcomes(_plan(cursor: 1), [_trained(0, 'up')], today: 0), [
        DayOutcome.completed,
      ]);
    });

    test('planned rest + a workout is an EXTRA workout', () {
      final outcomes = _outcomes(_plan(cursor: 4), [
        _trained(0, 'up'),
        _trained(1, 'lo'),
        _trained(2, 'pu'), // Wed was planned rest
      ], today: 2);
      expect(outcomes.last, DayOutcome.extraWorkout);
    });

    test('a pure rotation never calls implicit rest missed', () {
      final plan = _plan(
        cursor: 1,
        days: [_workout('a', 0), _workout('b', 1), _workout('c', 2)],
      );
      expect(plan.schedulesRest, isFalse);
      final outcomes = _outcomes(plan, [_trained(0, 'a')], today: 2);
      expect(outcomes, [
        DayOutcome.completed,
        DayOutcome.unscheduled,
        DayOutcome.pending,
      ]);
    });

    test('choosing and withdrawing rest never touches the plan', () {
      final plan = _plan(cursor: 1);
      final chosen = chooseRest(null, day: _noon(1), now: _noon(1));
      expect(chosen.reason, MissedDayReason.rest);
      expect(isUserRestMark(chosen), isTrue);
      expect(withdrawRest(chosen), isNull, reason: 'nothing left: delete it');
      final withRestore = chosen.copyWith(restored: true);
      expect(withdrawRest(withRestore)?.restored, isTrue);
      expect(withdrawRest(withRestore)?.reason, isNull);
      expect(plan.nextDay?.id, 'lo');
    });
  });

  group('summary', () {
    test('keeps every state apart and reports both frequencies', () {
      final plan = _plan(cursor: 4);
      final records = classifyTrainingDays(
        plan: plan,
        sessions: [
          _trained(0, 'up'),
          _trained(2, 'lo'), // Tue missed/chosen → Lower on Wed
          _trained(3, 'pu'), // Thu was planned rest → extra
        ],
        marks: [_choseRest(1)],
        from: _created,
        today: _noon(5),
      );
      final s = summarizeTrainingDays(plan, records);
      expect(s.completed, 2);
      expect(s.userRest, 1);
      expect(s.extraWorkouts, 1);
      expect(s.plannedRest, 0);
      expect(s.missed, 1, reason: 'Fri: Pull due, nothing logged');
      expect(s.plannedWorkouts, 4);
      expect(s.days, 5, reason: "today's pending day is not judged");
      expect(s.trainingDaysPerWeek, 4.2);
      expect(s.plannedTrainingDaysPerWeek, 4.0);
      expect(s.skippedByDayId, {'lo': 1, 'pl': 1});
    });
  });

  group('streak', () {
    test('a plan scheduling three rest days in a row keeps the streak', () {
      // One workout, then three scheduled rest days: every gap is 4 days,
      // which the plain 3-day allowance would call a break.
      final plan = _plan(
        cursor: 0,
        days: [
          _workout('a', 0),
          _rest('r1', 1),
          _rest('r2', 2),
          _rest('r3', 3),
        ],
      );
      final sessions = [_trained(0, 'a'), _trained(4, 'a')];
      final now = _noon(8); // four days after the last session
      final planned = plannedRestDaysFor(
        plan: plan,
        sessions: sessions,
        now: now,
      );
      expect(planned, {_day(1), _day(2), _day(3), _day(5), _day(6), _day(7)});
      final without = computeTrainingStreak(sessions: sessions, now: now);
      final withPlan = computeTrainingStreak(
        sessions: sessions,
        now: now,
        plannedRestDays: planned,
      );
      expect(
        without.currentDays,
        0,
        reason: 'a 4-day gap breaks the plain rule',
      );
      expect(withPlan.currentDays, 2, reason: 'the plan scheduled that rest');
      expect(withPlan.bestDays, 2);
    });

    test('a chosen rest day gets no pass beyond the normal allowance', () {
      final plan = _plan(cursor: 1);
      final sessions = [_trained(0, 'up')];
      final planned = plannedRestDaysFor(
        plan: plan,
        sessions: sessions,
        marks: [_choseRest(1), _choseRest(2), _choseRest(3)],
        now: _noon(4),
      );
      expect(planned, isEmpty);
    });

    test('no plan and no rest leaves the streak engine unchanged', () {
      expect(
        plannedRestDaysFor(plan: null, sessions: const [], now: _noon(0)),
        isEmpty,
      );
    });
  });
}
