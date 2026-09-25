import '../../../core/util/calendar.dart';
import 'live_session.dart';
import 'session_status.dart';
import 'training_day_mark.dart';
import 'training_streak.dart';
import 'workout_settings.dart';

/// The Workout Dashboard's aggregate picture of training activity — built
/// entirely from [LiveSession]s (the real record of what happened, when, and
/// for how long), never the lossy flat `Workout` log.
///
/// Three rules run through everything here:
///
/// 1. **Completed sessions only** for counts and averages. An abandoned
///    session was quit and a [SessionStatus.voided] one was withdrawn, so
///    neither may skew "how long a session takes" or "when I train".
///    [recentSessions] deliberately keeps every status so the activity feed
///    can show what actually happened to each one.
/// 2. **A day is the day training FINISHED** (`completedAt ?? startedAt`) —
///    the same instant `workout_analytics.dart`, `today_pulse.dart` and
///    `functions/ai/workout_analytics.js` already bucket by. This file used to
///    be the only holdout, using `startedAt`, which is why the hub and Today
///    could show two different streaks for the same history.
/// 3. **Only durations we can stand behind feed the averages.** A session left
///    open overnight is kept in full and shown in history, but it is held out
///    of [averageSessionDuration] rather than dragging it toward a number that
///    never happened — see [LiveSession.hasUsableDuration] and
///    [durationsExcluded].
///
/// All day and week arithmetic goes through `core/util/calendar.dart`, never
/// `Duration`, so nothing here changes shape twice a year.
class TrainingDashboardStats {
  const TrainingDashboardStats({
    required this.totalCompletedSessions,
    required this.sessionsThisWeek,
    required this.currentStreakWeeks,
    required this.streak,
    required this.averageSessionDuration,
    required this.durationsCounted,
    required this.durationsExcluded,
    required this.averageStartMinutesSinceMidnight,
    required this.averageEndMinutesSinceMidnight,
    required this.sessionCountByDayLabel,
    required this.recentSessions,
  });

  final int totalCompletedSessions;
  final int sessionsThisWeek;

  /// Consecutive weeks (this one included) with at least one completed
  /// session, counting back from the most recent week that has one — a week
  /// still in progress with nothing logged yet doesn't break the streak
  /// until it actually ends.
  final int currentStreakWeeks;

  /// The day streak, from the one engine (`training_streak.dart`).
  final TrainingStreak streak;

  /// Trained days in the current run — the Streak tile's number.
  int get currentStreakDays => streak.currentDays;

  /// Mean of the durations we can stand behind. Null when there are none —
  /// which is not the same as "no sessions", and the UI should say so.
  final Duration? averageSessionDuration;

  /// How many sessions [averageSessionDuration] is an average *of*, and how
  /// many were held out for having an implausible or unknowable duration. The
  /// pair is what lets a tile say "over 23 of 24" instead of quietly
  /// presenting a partial average as a total one.
  final int durationsCounted;
  final int durationsExcluded;

  /// Mean clock-in time across completed sessions, as minutes since local
  /// midnight (e.g. 6:30am = 390) — a plain arithmetic mean, not a circular
  /// one, since training happens within a single day, never wrapping
  /// midnight. Null when there are no completed sessions.
  ///
  /// Reads `startedAt`, which is recorded when the user taps Start and is
  /// unaffected by anything that goes wrong later — so this is the one stat a
  /// session left open overnight cannot distort, and it needs no gate.
  final double? averageStartMinutesSinceMidnight;

  /// Same shape as [averageStartMinutesSinceMidnight], for when sessions end.
  /// Gated on a usable duration, because a bad end time is exactly what a
  /// session left open has.
  final double? averageEndMinutesSinceMidnight;

  /// How many completed sessions landed on each day label (e.g. "Push": 12,
  /// "Pull": 10) — what's actually being trained, not just how often.
  final Map<String, int> sessionCountByDayLabel;

  /// Every session (any status), newest-finished-first, capped to the
  /// dashboard's activity-feed window.
  final List<LiveSession> recentSessions;
}

/// The instant a session belongs at on a timeline — see rule 2 above.
DateTime sessionInstant(LiveSession s) => s.completedAt ?? s.startedAt;

/// Computes [TrainingDashboardStats] from every known session.
///
/// [now] drives the "this week"/streak windowing, [maxSessionDuration] is the
/// user's own threshold (see [WorkoutSettings]), [marks] carry streak restores
/// and missed-day context, and [recentLimit] caps [recentSessions].
TrainingDashboardStats computeTrainingDashboardStats({
  required List<LiveSession> sessions,
  required DateTime now,
  Duration maxSessionDuration = const Duration(
    minutes: kDefaultMaxSessionDurationMinutes,
  ),
  List<TrainingDayMark> marks = const [],
  int recentLimit = 8,
}) {
  final completed = sessions.where((s) => s.status == SessionStatus.completed).toList()
    ..sort((a, b) => sessionInstant(b).compareTo(sessionInstant(a)));

  final recent = [...sessions]
    ..sort((a, b) => sessionInstant(b).compareTo(sessionInstant(a)));

  final weekStart = startOfWeek(now);
  final sessionsThisWeek = completed
      .where((s) => !startOfWeek(sessionInstant(s)).isBefore(weekStart))
      .length;

  final weekStartsTrained = completed.map((s) => startOfWeek(sessionInstant(s))).toSet();
  final streakWeeks = _currentStreakWeeks(weekStartsTrained, now);

  final streak = computeTrainingStreak(
    sessions: sessions,
    now: now,
    marks: marks,
  );

  final usable = completed
      .where((s) => s.hasUsableDuration(maxSessionDuration))
      .toList(growable: false);
  final durations = usable.map((s) => s.elapsed).toList();
  final avgDuration = durations.isEmpty ? null : _averageDuration(durations);

  final startMinutes = completed
      .map((s) => _minutesSinceMidnight(s.startedAt))
      .toList();
  final avgStart = startMinutes.isEmpty ? null : _average(startMinutes);

  final endMinutes = usable
      .where((s) => s.completedAt != null)
      .map((s) => _minutesSinceMidnight(s.completedAt!))
      .toList();
  final avgEnd = endMinutes.isEmpty ? null : _average(endMinutes);

  final byDay = <String, int>{};
  for (final s in completed) {
    byDay[s.dayLabel] = (byDay[s.dayLabel] ?? 0) + 1;
  }

  return TrainingDashboardStats(
    totalCompletedSessions: completed.length,
    sessionsThisWeek: sessionsThisWeek,
    currentStreakWeeks: streakWeeks,
    streak: streak,
    averageSessionDuration: avgDuration,
    durationsCounted: usable.length,
    durationsExcluded: completed.length - usable.length,
    averageStartMinutesSinceMidnight: avgStart,
    averageEndMinutesSinceMidnight: avgEnd,
    sessionCountByDayLabel: byDay,
    recentSessions: recent.take(recentLimit).toList(growable: false),
  );
}

int _currentStreakWeeks(Set<DateTime> weekStartsTrained, DateTime now) {
  var cursor = startOfWeek(now);
  if (!weekStartsTrained.contains(cursor)) {
    cursor = addCalendarWeeks(cursor, -1);
  }
  var streak = 0;
  while (weekStartsTrained.contains(cursor)) {
    streak++;
    cursor = addCalendarWeeks(cursor, -1);
  }
  return streak;
}

double _minutesSinceMidnight(DateTime dt) => dt.hour * 60 + dt.minute + dt.second / 60;

double _average(List<double> values) => values.reduce((a, b) => a + b) / values.length;

Duration _averageDuration(List<Duration> values) {
  final totalMicros = values.fold<int>(0, (sum, d) => sum + d.inMicroseconds);
  return Duration(microseconds: totalMicros ~/ values.length);
}

// ---- Streak drill-down (Day Streak stat) ----------------------------------

/// Every session that fell on [day] and counts as training — the per-day
/// detail behind a streak entry. Includes a still-active session, for the same
/// reason the streak does: a workout you haven't tapped Finish on still
/// happened.
List<LiveSession> sessionsOnDay(List<LiveSession> sessions, DateTime day) {
  final start = startOfDay(day);
  return sessions
      .where(
        (s) =>
            s.countsAsTraining &&
            s.hasCompletedWorkingSet &&
            startOfDay(sessionInstant(s)) == start,
      )
      .toList();
}

// ---- Tile sparklines ------------------------------------------------------
//
// The dashboard's stat tiles carry the SHAPE of their own metric instead of a
// chevron (design handoff §"Workout hub"), so each of these returns a plain
// oldest-first series a sparkline can normalise over its own range.

/// Completed sessions per calendar week for the last [weeks] weeks, oldest
/// first and including the current (partial) week — the Sessions tile's
/// sparkline. Always exactly [weeks] entries, so a quiet stretch reads as a
/// dip rather than shortening the line.
List<double> weeklySessionCounts({
  required List<LiveSession> sessions,
  required DateTime now,
  int weeks = 8,
}) {
  final trained = <DateTime, int>{};
  for (final s in sessions) {
    if (s.status != SessionStatus.completed) continue;
    final week = startOfWeek(sessionInstant(s));
    trained[week] = (trained[week] ?? 0) + 1;
  }
  final thisWeek = startOfWeek(now);
  return [
    for (var i = weeks - 1; i >= 0; i--)
      (trained[addCalendarWeeks(thisWeek, -i)] ?? 0).toDouble(),
  ];
}

/// Qualifying sessions per day for the last [days] days, oldest first and
/// including today — the Streak tile's bar cluster, where the last bar is
/// today and carries the full accent. Counts the same thing the streak does,
/// so the bars and the number can never tell different stories.
List<double> dailySessionCounts({
  required List<LiveSession> sessions,
  required DateTime now,
  int days = 7,
}) {
  final trained = trainedDayCounts(sessions);
  final today = startOfDay(now);
  return [
    for (var i = days - 1; i >= 0; i--)
      (trained[addCalendarDays(today, -i)] ?? 0).toDouble(),
  ];
}

/// The last [limit] usable session durations in minutes, oldest first — the
/// Duration tile's sparkline. A session held out of the average is held out of
/// its shape too; the sparkline hides itself below two points.
List<double> recentSessionDurationMinutes({
  required List<LiveSession> sessions,
  Duration maxSessionDuration = const Duration(
    minutes: kDefaultMaxSessionDurationMinutes,
  ),
  int limit = 8,
}) {
  final completed =
      sessions
          .where(
            (s) =>
                s.status == SessionStatus.completed &&
                s.hasUsableDuration(maxSessionDuration),
          )
          .toList()
        ..sort((a, b) => sessionInstant(a).compareTo(sessionInstant(b)));
  final window = completed.length <= limit
      ? completed
      : completed.sublist(completed.length - limit);
  return [for (final s in window) s.elapsed.inSeconds / 60];
}
