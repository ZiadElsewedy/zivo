import 'live_session.dart';
import 'session_status.dart';
import 'workout_day.dart';
import 'workout_plan.dart';

/// Cheap, pure summaries of a planned day and a plan's position in time —
/// the numbers Today's "next session" card leads with (`10 EXERCISES ·
/// 24 SETS · ~65 MINUTES`, `WEEK 4 · DAY 2`).
///
/// Deliberately derived rather than stored: a plan edit changes them the
/// instant it lands, with nothing to keep in sync.

/// Every planned set across the day's exercises — warm-up ramps included,
/// since they're sets you actually perform.
int plannedSetCount(WorkoutDay day) =>
    day.exercises.fold(0, (sum, e) => sum + e.setCount);

/// How long the day is likely to take: the work itself plus the rest each
/// exercise prescribes between its own sets.
///
/// [_workSecondsPerSet] is a flat estimate — a working set is roughly
/// three-quarters of a minute under load plus the setup around it — because
/// nothing in the plan model carries tempo or time-under-tension. The card
/// renders this with a `~`, and it is never used for anything that has to be
/// exact (the session's real duration is wall-clock, see
/// [LiveSession.activeElapsed]).
const int _workSecondsPerSet = 45;

Duration estimatedDayDuration(WorkoutDay day) {
  var seconds = 0;
  for (final exercise in day.exercises) {
    final sets = exercise.setCount;
    if (sets == 0) continue;
    seconds += sets * _workSecondsPerSet;
    // Rest happens BETWEEN sets, so one fewer rest than sets.
    seconds += (sets - 1) * exercise.defaultRestSeconds;
  }
  return Duration(seconds: seconds);
}

/// Which week of the plan [now] falls in, 1-based — "how far into this split
/// am I", counted from the day the split was created. Always at least 1, so a
/// plan created today reads as `WEEK 1` rather than `WEEK 0`.
int planWeekNumber(WorkoutPlan plan, DateTime now) {
  final days = _dateOnly(now).difference(_dateOnly(plan.createdAt)).inDays;
  if (days < 0) return 1;
  return days ~/ 7 + 1;
}

/// The day's 1-based position in the split's rotation.
int planDayNumber(WorkoutDay day) => day.order + 1;

/// Today's completed training, as (day label, active duration) — what the
/// Trained ring's sub-caption reports (`PULL · 62 MIN`). Null when nothing
/// has completed today.
({String label, Duration duration})? trainedTodaySummary(
  List<LiveSession> sessions,
  DateTime now,
) {
  final today = _dateOnly(now);
  LiveSession? latest;
  for (final s in sessions) {
    if (s.status != SessionStatus.completed) continue;
    final done = s.completedAt ?? s.startedAt;
    if (_dateOnly(done) != today) continue;
    if (latest == null || done.isAfter(latest.completedAt ?? latest.startedAt)) {
      latest = s;
    }
  }
  if (latest == null) return null;
  return (label: latest.dayLabel, duration: latest.elapsed);
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
