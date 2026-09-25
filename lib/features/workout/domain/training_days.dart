/// The ONE answer to "what did the plan expect on a day, and what happened".
///
/// A plan is a rotation (Push → Pull → Legs → …), not a weekday calendar, so
/// "what was planned on Thursday" is derived, never stored:
///
/// * **Planned** — a rest slot sits in the cycle after the workout it follows
///   ("Lower → Rest → Push"). So the day(s) right after training a workout
///   that is followed by rest slots are *planned rest*; every other day has a
///   workout due — the rotation waits for it (skipping a day does not move the
///   cycle, exactly as `WorkoutPlan.advanceToAfterDay` already behaves).
/// * **Actual** — a qualifying session (`qualifiesForStreak`) that day, or the
///   user's explicit "take a rest day" (a [TrainingDayMark] whose reason is
///   [MissedDayReason.rest]), or nothing.
///
/// The plan itself is never touched by a user's choice: choosing to rest on a
/// Shoulders day is a day mark, and the rotation still says Shoulders.
///
/// ## Why "missed" needs a plan that schedules rest
///
/// A pure rotation (every day a workout, rest implicit) cannot say whether an
/// unlogged Tuesday was the rest it assumes or a skipped session. Calling it
/// missed would turn every such plan's rest into failures, so on those plans
/// the day is [DayOutcome.unscheduled] and the planned frequency is unknown.
/// Only a cycle that spells its rest out (`WorkoutPlan.schedulesRest`) has
/// missed workouts.
///
/// Mirrored in Node (`functions/ai/analytics/training_days.js`) for the AI
/// coach, pinned by `test/fixtures/training_days_vectors.json`. The core
/// ([classifyTrainingDayRecords]) works on day keys and day ids only, so the
/// two engines see identical inputs.
library;

import '../../../core/util/calendar.dart';
import 'live_session.dart';
import 'training_day_mark.dart';
import 'training_streak.dart';
import 'workout_day.dart';
import 'workout_plan.dart';

/// What one day came to, planned vs actual.
enum DayOutcome {
  /// A workout was due and the user trained.
  completed,

  /// A workout was due, the user did not train and did not choose rest — on a
  /// plan that schedules its rest days.
  missed,

  /// A workout was due and the user explicitly chose to rest instead.
  userRest,

  /// The plan scheduled rest and the user rested.
  plannedRest,

  /// The plan scheduled rest and the user trained anyway.
  extraWorkout,

  /// Nothing logged on a pure rotation whose rest days are implicit — neither
  /// missed nor a planned rest; the rotation simply waited.
  unscheduled,

  /// Today, a workout is due, and nothing has happened yet.
  pending,
}

/// One classified calendar day.
class TrainingDayRecord {
  const TrainingDayRecord({
    required this.day,
    required this.planned,
    required this.outcome,
    this.dueDayId,
    this.trainedDayIds = const [],
  });

  final DateTime day;

  /// What the plan expected.
  final TrainingDayType planned;

  /// The workout the rotation had due, when [planned] is a workout.
  final String? dueDayId;

  /// The plan days trained that day, in session order (may be empty, or hold
  /// ids from another split).
  final List<String> trainedDayIds;

  final DayOutcome outcome;

  bool get trained =>
      outcome == DayOutcome.completed || outcome == DayOutcome.extraWorkout;
}

/// The day's inputs in their engine-neutral form: which plan days were
/// trained (qualifying sessions only, in time order) and whether the user
/// chose rest. Built from sessions/marks by [trainingDayInputs], or directly
/// by the golden-vector tests.
class TrainingDayInputs {
  const TrainingDayInputs({
    this.trainedDayIds = const {},
    this.userRestDays = const {},
  });

  /// Calendar day → the `dayId`s of that day's qualifying sessions, oldest
  /// first. A day present with any entry was trained.
  final Map<DateTime, List<String>> trainedDayIds;

  /// Calendar days the user explicitly chose to rest.
  final Set<DateTime> userRestDays;
}

/// Whether [mark] records the user choosing rest for its day.
///
/// "Take a rest day" and a retroactive "I rested" on a missed day are the same
/// statement from the same person, so they are the same record: a day mark
/// with [MissedDayReason.rest]. Every other reason (travel, illness, …) is
/// context on a day that stays missed.
bool isUserRestMark(TrainingDayMark mark) =>
    mark.reason == MissedDayReason.rest;

/// [sessions] and [marks] in the engine's input form.
TrainingDayInputs trainingDayInputs({
  required List<LiveSession> sessions,
  List<TrainingDayMark> marks = const [],
}) {
  final qualifying = sessions.where(qualifiesForStreak).toList()
    ..sort(
      (a, b) => (a.completedAt ?? a.startedAt).compareTo(
        b.completedAt ?? b.startedAt,
      ),
    );
  final trained = <DateTime, List<String>>{};
  for (final s in qualifying) {
    (trained[streakDayOf(s)] ??= <String>[]).add(s.dayId);
  }
  return TrainingDayInputs(
    trainedDayIds: trained,
    userRestDays: {
      for (final m in marks)
        if (isUserRestMark(m)) startOfDay(m.day),
    },
  );
}

/// Classifies every calendar day from [from] (clamped to the plan's creation
/// day) through [today], oldest first.
List<TrainingDayRecord> classifyTrainingDays({
  required WorkoutPlan plan,
  required List<LiveSession> sessions,
  List<TrainingDayMark> marks = const [],
  required DateTime from,
  required DateTime today,
}) => classifyTrainingDayRecords(
  plan: plan,
  inputs: trainingDayInputs(sessions: sessions, marks: marks),
  from: from,
  today: today,
);

/// The engine core — pure over day keys and day ids (see the library doc).
List<TrainingDayRecord> classifyTrainingDayRecords({
  required WorkoutPlan plan,
  required TrainingDayInputs inputs,
  required DateTime from,
  required DateTime today,
}) {
  final end = startOfDay(today);
  final planStart = startOfDay(plan.createdAt);
  var start = startOfDay(from);
  if (start.isBefore(planStart)) start = planStart;
  if (start.isAfter(end)) return const [];
  if (plan.workoutDays.isEmpty) return const [];

  final workoutIds = {for (final d in plan.workoutDays) d.id};
  // Every day that trained one of THIS plan's workouts, and the last such
  // workout that day — what positions the rotation after it.
  final anchors = <DateTime, String>{};
  for (final entry in inputs.trainedDayIds.entries) {
    final own = entry.value.where(workoutIds.contains);
    if (own.isNotEmpty) anchors[startOfDay(entry.key)] = own.last;
  }
  final anchorDays = anchors.keys.toList()..sort();
  final latestAnchor = anchorDays.isEmpty ? null : anchorDays.last;

  final records = <TrainingDayRecord>[];
  var a = -1; // index of the latest anchor strictly before `day`
  for (var day = start; !day.isAfter(end); day = addCalendarDays(day, 1)) {
    while (a + 1 < anchorDays.length && anchorDays[a + 1].isBefore(day)) {
      a++;
    }
    final previous = a < 0 ? null : anchorDays[a];

    // Planned: rest when this day falls inside the rest slots that follow the
    // last workout trained before it.
    var planned = TrainingDayType.workout;
    String? due;
    if (previous != null) {
      final lastId = anchors[previous]!;
      final gap = calendarDaysBetween(previous, day);
      if (gap >= 1 && gap <= plan.restDaysAfter(lastId)) {
        planned = TrainingDayType.rest;
      } else {
        // Past the rotation's last known position, the live cursor is the
        // truth (it carries swaps and skips); before it, history is.
        due = previous == latestAnchor
            ? plan.nextDay?.id
            : plan.workoutAfter(lastId)?.id;
      }
    } else {
      due = latestAnchor == null
          ? plan.nextDay?.id
          // Before this plan's first logged workout the cycle's position is
          // unknown; the first workout in the cycle is the honest default.
          : plan.workoutDays.first.id;
    }

    final trainedIds = inputs.trainedDayIds[day] ?? const <String>[];
    final trained = trainedIds.isNotEmpty;
    final choseRest = inputs.userRestDays.contains(day);
    final DayOutcome outcome;
    if (planned == TrainingDayType.rest) {
      outcome = trained ? DayOutcome.extraWorkout : DayOutcome.plannedRest;
    } else if (trained) {
      outcome = DayOutcome.completed;
    } else if (choseRest) {
      outcome = DayOutcome.userRest;
    } else if (day == end) {
      outcome = DayOutcome.pending;
    } else {
      outcome = plan.schedulesRest ? DayOutcome.missed : DayOutcome.unscheduled;
    }
    records.add(
      TrainingDayRecord(
        day: day,
        planned: planned,
        outcome: outcome,
        dueDayId: planned == TrainingDayType.workout ? due : null,
        trainedDayIds: List.unmodifiable(trainedIds),
      ),
    );
  }
  return records;
}

/// Today's record alone — what the Today card and the Workout tab branch on.
TrainingDayRecord? todayTrainingRecord({
  required WorkoutPlan plan,
  required List<LiveSession> sessions,
  List<TrainingDayMark> marks = const [],
  required DateTime now,
}) {
  final today = startOfDay(now);
  // The rotation's position comes from the whole history, not the window, so
  // a one-day window is enough.
  final records = classifyTrainingDays(
    plan: plan,
    sessions: sessions,
    marks: marks,
    from: today,
    today: today,
  );
  return records.isEmpty ? null : records.last;
}

/// Every planned rest day of [plan]'s life so far — what a streak surface
/// passes to `computeTrainingStreak`. Empty with no plan, or a pure rotation.
Set<DateTime> plannedRestDaysFor({
  required WorkoutPlan? plan,
  required List<LiveSession> sessions,
  List<TrainingDayMark> marks = const [],
  required DateTime now,
}) {
  if (plan == null || !plan.schedulesRest) return const {};
  return plannedRestDaysOf(
    classifyTrainingDays(
      plan: plan,
      sessions: sessions,
      marks: marks,
      from: plan.createdAt,
      today: now,
    ),
  );
}

/// The calendar days in [records] the plan scheduled as rest — what bridges a
/// streak gap (see `computeTrainingStreak`'s `plannedRestDays`).
Set<DateTime> plannedRestDaysOf(List<TrainingDayRecord> records) => {
  for (final r in records)
    if (r.planned == TrainingDayType.rest) r.day,
};

/// One 7-day bucket of a [TrainingDaySummary], oldest first.
class TrainingWeek {
  const TrainingWeek({
    required this.start,
    required this.trainedDays,
    required this.userRestDays,
    required this.missedDays,
    required this.plannedRestDays,
  });

  final DateTime start;
  final int trainedDays;
  final int userRestDays;
  final int missedDays;
  final int plannedRestDays;
}

/// Planned vs actual over a window — the behaviour, not a single streak.
class TrainingDaySummary {
  const TrainingDaySummary({
    required this.days,
    required this.schedulesRest,
    required this.plannedWorkouts,
    required this.completed,
    required this.missed,
    required this.userRest,
    required this.plannedRest,
    required this.extraWorkouts,
    required this.unscheduled,
    required this.trainingDaysPerWeek,
    required this.plannedTrainingDaysPerWeek,
    required this.skippedByDayId,
    required this.weeks,
  });

  /// Days judged (a still-open today with a workout due is not one).
  final int days;

  /// Whether the plan spells out its rest days — without that, planned
  /// workouts, missed days and the planned frequency are unknowable and null.
  final bool schedulesRest;

  /// Days a workout was due (completed + missed + chosen rest). Null on a
  /// pure rotation.
  final int? plannedWorkouts;
  final int completed;
  final int? missed;
  final int userRest;
  final int plannedRest;
  final int extraWorkouts;
  final int unscheduled;

  /// Days trained (completed + extra) per 7 judged days, to 2 decimals.
  final double trainingDaysPerWeek;

  /// The plan's own rate: workout slots per cycle length × 7. Null on a pure
  /// rotation.
  final double? plannedTrainingDaysPerWeek;

  /// Workout day id → times it was due and not trained (chosen rest or
  /// missed) — which sessions the user tends to drop.
  final Map<String, int> skippedByDayId;

  /// 7-day buckets ending today, oldest first (the oldest may be partial).
  final List<TrainingWeek> weeks;
}

/// Rolls [records] (oldest first) up for [plan].
TrainingDaySummary summarizeTrainingDays(
  WorkoutPlan plan,
  List<TrainingDayRecord> records,
) {
  int count(DayOutcome o) => records.where((r) => r.outcome == o).length;
  final completed = count(DayOutcome.completed);
  final missed = count(DayOutcome.missed);
  final userRest = count(DayOutcome.userRest);
  final extra = count(DayOutcome.extraWorkout);
  final judged = records.where((r) => r.outcome != DayOutcome.pending).length;
  final schedulesRest = plan.schedulesRest;

  final skipped = <String, int>{};
  for (final r in records) {
    if (r.outcome != DayOutcome.userRest && r.outcome != DayOutcome.missed) {
      continue;
    }
    final id = r.dueDayId;
    if (id != null) skipped[id] = (skipped[id] ?? 0) + 1;
  }

  final weeks = <TrainingWeek>[];
  for (var end = records.length; end > 0; end -= 7) {
    final chunk = records.sublist(end - 7 < 0 ? 0 : end - 7, end);
    int n(bool Function(TrainingDayRecord) test) => chunk.where(test).length;
    weeks.insert(
      0,
      TrainingWeek(
        start: chunk.first.day,
        trainedDays: n((r) => r.trained),
        userRestDays: n((r) => r.outcome == DayOutcome.userRest),
        missedDays: n((r) => r.outcome == DayOutcome.missed),
        plannedRestDays: n((r) => r.outcome == DayOutcome.plannedRest),
      ),
    );
  }

  final cycle = plan.days.length;
  return TrainingDaySummary(
    days: judged,
    schedulesRest: schedulesRest,
    plannedWorkouts: schedulesRest ? completed + missed + userRest : null,
    completed: completed,
    missed: schedulesRest ? missed : null,
    userRest: userRest,
    plannedRest: count(DayOutcome.plannedRest),
    extraWorkouts: extra,
    unscheduled: count(DayOutcome.unscheduled),
    trainingDaysPerWeek: judged == 0
        ? 0
        : _round2((completed + extra) * 7 / judged),
    plannedTrainingDaysPerWeek: schedulesRest && cycle > 0
        ? _round2(plan.workoutDays.length * 7 / cycle)
        : null,
    skippedByDayId: skipped,
    weeks: weeks,
  );
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

/// [existing] (or a fresh mark for [day]) with the user's choice to rest.
/// Keeps a restore or note already on the day.
TrainingDayMark chooseRest(
  TrainingDayMark? existing, {
  required DateTime day,
  required DateTime now,
}) => (existing ?? TrainingDayMark(day: startOfDay(day), createdAt: now))
    .copyWith(reason: MissedDayReason.rest);

/// [existing] without its rest choice, or null when nothing else is left on
/// it (the caller deletes the document rather than keep an empty one).
TrainingDayMark? withdrawRest(TrainingDayMark existing) {
  final next = existing.copyWith(reason: null);
  return next.isEmpty ? null : next;
}
