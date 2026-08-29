import 'live_session.dart';
import 'session_status.dart';

/// The Workout Dashboard's aggregate picture of training activity — built
/// entirely from [LiveSession]s (the real record of what happened, when, and
/// for how long), never the lossy flat `Workout` log.
///
/// Averages/counts ([sessionsThisWeek], [currentStreakWeeks],
/// [averageSessionDuration], [averageStartMinutesSinceMidnight],
/// [averageEndMinutesSinceMidnight], [sessionCountByDayLabel]) are computed
/// from COMPLETED sessions only — an abandoned session was quit, not trained,
/// so it would skew "how long a session takes" or "when I train" downward.
/// [recentSessions] deliberately includes every status (active/completed/
/// abandoned) so the dashboard's activity feed can show whether a given
/// session was actually completed, per the product ask.
class TrainingDashboardStats {
  const TrainingDashboardStats({
    required this.totalCompletedSessions,
    required this.sessionsThisWeek,
    required this.currentStreakWeeks,
    required this.currentStreakDays,
    required this.averageSessionDuration,
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

  /// Consecutive calendar days (local, today included) with at least one
  /// completed session, counting back from the most recent trained day — a
  /// day still in progress with nothing logged yet doesn't break the streak
  /// until it actually ends. Opening the app never counts; only a completed
  /// session does.
  final int currentStreakDays;

  /// Null when there are no completed sessions to average.
  final Duration? averageSessionDuration;

  /// Mean clock-in time across completed sessions, as minutes since local
  /// midnight (e.g. 6:30am = 390) — a plain arithmetic mean, not a circular
  /// one, since training happens within a single day, never wrapping
  /// midnight. Null when there are no completed sessions.
  final double? averageStartMinutesSinceMidnight;

  /// Same shape as [averageStartMinutesSinceMidnight], for when sessions end.
  final double? averageEndMinutesSinceMidnight;

  /// How many completed sessions landed on each day label (e.g. "Push": 12,
  /// "Pull": 10) — what's actually being trained, not just how often.
  final Map<String, int> sessionCountByDayLabel;

  /// Every session (any status), newest-started-first, capped to the
  /// dashboard's activity-feed window.
  final List<LiveSession> recentSessions;
}

/// Computes [TrainingDashboardStats] from every known session. [now] drives
/// the "this week"/streak windowing; [recentLimit] caps [recentSessions].
TrainingDashboardStats computeTrainingDashboardStats({
  required List<LiveSession> sessions,
  required DateTime now,
  int recentLimit = 8,
}) {
  final completed = sessions.where((s) => s.status == SessionStatus.completed).toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  final recent = [...sessions]..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  final weekStart = _weekStart(now);
  final sessionsThisWeek = completed.where((s) => !_weekStart(s.startedAt).isBefore(weekStart)).length;

  final weekStartsTrained = completed.map((s) => _weekStart(s.startedAt)).toSet();
  final streak = _currentStreakWeeks(weekStartsTrained, now);

  final daysTrained = completed.map((s) => _dayStart(s.startedAt)).toSet();
  final streakDays = _currentStreakDays(daysTrained, now);

  final durations = completed.map((s) => s.elapsed).toList();
  final avgDuration = durations.isEmpty ? null : _averageDuration(durations);

  final startMinutes = completed.map((s) => _minutesSinceMidnight(s.startedAt)).toList();
  final avgStart = startMinutes.isEmpty ? null : _average(startMinutes);

  final endMinutes = completed
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
    currentStreakWeeks: streak,
    currentStreakDays: streakDays,
    averageSessionDuration: avgDuration,
    averageStartMinutesSinceMidnight: avgStart,
    averageEndMinutesSinceMidnight: avgEnd,
    sessionCountByDayLabel: byDay,
    recentSessions: recent.take(recentLimit).toList(growable: false),
  );
}

/// Midnight of the Monday starting [d]'s week (local calendar days).
DateTime _weekStart(DateTime d) {
  final date = DateTime(d.year, d.month, d.day);
  return date.subtract(Duration(days: date.weekday - 1));
}

int _currentStreakWeeks(Set<DateTime> weekStartsTrained, DateTime now) {
  var cursor = _weekStart(now);
  if (!weekStartsTrained.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 7));
  }
  var streak = 0;
  while (weekStartsTrained.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 7));
  }
  return streak;
}

/// Midnight of [d]'s local calendar day.
DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

int _currentStreakDays(Set<DateTime> daysTrained, DateTime now) {
  var cursor = _dayStart(now);
  if (!daysTrained.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (daysTrained.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
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

/// The calendar days (local midnight) that make up the CURRENT day streak,
/// newest first — exactly the days [currentStreakDays] counted, so the
/// streak's drill-down page can never disagree with the tile's number.
/// Empty when there is no active streak.
List<DateTime> currentStreakTrainedDays({
  required List<LiveSession> sessions,
  required DateTime now,
}) {
  final completed = sessions
      .where((s) => s.status == SessionStatus.completed)
      .map((s) => _dayStart(s.startedAt))
      .toSet();
  var cursor = _dayStart(now);
  if (!completed.contains(cursor)) cursor = cursor.subtract(const Duration(days: 1));
  final days = <DateTime>[];
  while (completed.contains(cursor)) {
    days.add(cursor);
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return days;
}

/// The longest ever run of consecutive trained days — the "best streak"
/// context line on the streak drill-down page.
int bestStreakDays({required List<LiveSession> sessions}) {
  final days = sessions
      .where((s) => s.status == SessionStatus.completed)
      .map((s) => _dayStart(s.startedAt))
      .toSet().toList()
    ..sort();
  var best = 0;
  var run = 0;
  DateTime? previous;
  for (final day in days) {
    run = (previous != null && day.difference(previous) == const Duration(days: 1))
        ? run + 1
        : 1;
    best = run > best ? run : best;
    previous = day;
  }
  return best;
}

/// Every completed session that fell on [day] — the per-day detail behind a
/// streak entry.
List<LiveSession> sessionsOnDay(List<LiveSession> sessions, DateTime day) {
  final start = _dayStart(day);
  final end = start.add(const Duration(days: 1));
  return sessions
      .where(
        (s) =>
            s.status == SessionStatus.completed &&
            !s.startedAt.isBefore(start) &&
            s.startedAt.isBefore(end),
      )
      .toList();
}

// ---- Tile sparklines ------------------------------------------------------
//
// The dashboard's stat tiles carry the SHAPE of their own metric instead of a
// chevron (design handoff §"Workout hub"), so each of these returns a plain
// oldest-first series a sparkline can normalise over its own range. All three
// count COMPLETED sessions only, for the same reason the averages above do —
// an abandoned session was quit, not trained.

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
    final week = _weekStart(s.startedAt);
    trained[week] = (trained[week] ?? 0) + 1;
  }
  final thisWeek = _weekStart(now);
  return [
    for (var i = weeks - 1; i >= 0; i--)
      (trained[thisWeek.subtract(Duration(days: 7 * i))] ?? 0).toDouble(),
  ];
}

/// Completed sessions per day for the last [days] days, oldest first and
/// including today — the Streak tile's bar cluster, where the last bar is
/// today and carries the full accent.
List<double> dailySessionCounts({
  required List<LiveSession> sessions,
  required DateTime now,
  int days = 7,
}) {
  final trained = <DateTime, int>{};
  for (final s in sessions) {
    if (s.status != SessionStatus.completed) continue;
    final day = _dayStart(s.startedAt);
    trained[day] = (trained[day] ?? 0) + 1;
  }
  final today = _dayStart(now);
  return [
    for (var i = days - 1; i >= 0; i--)
      (trained[today.subtract(Duration(days: i))] ?? 0).toDouble(),
  ];
}

/// The last [limit] completed sessions' durations in minutes, oldest first —
/// the Duration tile's sparkline. Shorter than [limit] (or empty) when there
/// isn't that much history; the sparkline hides itself below two points.
List<double> recentSessionDurationMinutes({
  required List<LiveSession> sessions,
  int limit = 8,
}) {
  final completed =
      sessions.where((s) => s.status == SessionStatus.completed).toList()
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final window = completed.length <= limit
      ? completed
      : completed.sublist(completed.length - limit);
  return [for (final s in window) s.elapsed.inSeconds / 60];
}
