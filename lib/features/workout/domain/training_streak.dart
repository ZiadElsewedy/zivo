/// The ONE training-streak engine.
///
/// There used to be two, and they disagreed. `training_dashboard_stats.dart`
/// bucketed by `startedAt`; `home/domain/today_pulse.dart` bucketed by
/// `completedAt ?? startedAt`; both walked the calendar with
/// `Duration(days: 1)`. So a session finishing at 12:20am landed on different
/// days on the Workout hub and on Today, and both numbers collapsed to zero at
/// every daylight-saving transition. Everything that answers "what is my
/// streak" now comes through here.
///
/// ## The rule
///
/// **Train at least once every [kStreakMaxGapDays] days.** Not "every day" —
/// a tracker built around a coach must not tell you that resting breaks your
/// consistency, because the coach's own advice is that it doesn't. Concretely:
///
/// * a day you trained keeps the streak and adds to it;
/// * one or two days off change nothing — they are the rest the plan assumes;
/// * a gap **longer** than [kStreakMaxGapDays] calendar days between trained
///   days is the only thing that breaks it (a restore aside);
/// * training twice in one day is still one day.
///
/// "Trained" means a session that logged at least one **completed working
/// set**. Turning up, warming up and leaving is not a trained day — the same
/// line `analytics/plan_adherence.dart` already draws. A partly-logged session
/// counts in full: four of six exercises is a workout, and it counts whether
/// or not the user ever tapped Finish, so forgetting to close a session can
/// never cost a day that was actually trained.
///
/// ## What does NOT move the number
///
/// * A [MissedDayReason] is context, never credit. Writing "travel" on a
///   missed day explains it; it does not train you.
/// * A restore bridges a gap **without adding a trained day** — it keeps the
///   chain connected, and the headline count still only counts days you
///   trained.
/// * [bestDays] ignores restores entirely. The record book stays clean.
library;

import '../../../core/util/calendar.dart';
import 'live_session.dart';
import 'training_day_mark.dart';

/// The longest gap, in calendar days, between two trained days that still
/// keeps a streak alive. 3 means "train Monday, and the streak survives until
/// the end of Thursday" — two full rest days in between.
const int kStreakMaxGapDays = 3;

/// How often a restore may be spent, and how far back one may reach. A streak
/// you can repair without limit is a participation trophy.
const int kRestoreCooldownDays = 30;
const int kRestoreReachDays = 7;

/// What a day in the current run is.
enum StreakDayKind {
  /// At least one qualifying session.
  trained,

  /// No training, inside the allowance — the rest the rule is built around.
  rest,

  /// No training, and the gap only holds because a restore was spent here.
  restored,
}

/// One calendar day inside the current run.
class StreakDay {
  const StreakDay({
    required this.day,
    required this.kind,
    this.sessionCount = 0,
    this.reason,
    this.note,
  });

  final DateTime day;
  final StreakDayKind kind;

  /// Qualifying sessions on this day (>1 when the user trained twice; the day
  /// still counts once toward the streak).
  final int sessionCount;

  /// The user's context for a day they didn't train, if they gave any.
  final MissedDayReason? reason;
  final String? note;

  bool get isTrained => kind == StreakDayKind.trained;
}

/// The answer to "what is my streak", computed once and read everywhere.
class TrainingStreak {
  const TrainingStreak({
    required this.currentDays,
    required this.bestDays,
    required this.days,
    required this.restoresUsed,
    this.lastTrainedDay,
    this.daysUntilBreak,
  });

  static const empty = TrainingStreak(
    currentDays: 0,
    bestDays: 0,
    days: [],
    restoresUsed: 0,
  );

  /// Days **trained** in the current run — the headline number. Rest days and
  /// restored days keep the run alive without inflating this.
  final int currentDays;

  /// The best run ever, by the same rule, computed without restores.
  final int bestDays;

  /// Every calendar day in the current run, newest first — trained days and
  /// the rest/restored days between them, so the drill-down can show a
  /// continuous stretch instead of a row of holes. Empty when there is no run.
  final List<StreakDay> days;

  /// How many days in [days] are only there because a restore was spent.
  final int restoresUsed;

  /// The most recent day with a qualifying session, or null if there has never
  /// been one.
  final DateTime? lastTrainedDay;

  /// Days left to train before the run breaks — 0 means "today or it's gone".
  /// Null when there is no run to lose.
  final int? daysUntilBreak;

  bool get isActive => currentDays > 0;

  /// Whether the run ends today unless something is logged.
  bool get isAtRisk => daysUntilBreak != null && daysUntilBreak! <= 1;
}

/// Whether [session] counts as a day trained: it happened (not quit, not
/// withdrawn) and it logged real work.
bool qualifiesForStreak(LiveSession session) =>
    session.countsAsTraining && session.hasCompletedWorkingSet;

/// The calendar day a session belongs to.
///
/// `completedAt ?? startedAt` — when training *finished* is what a person
/// means by "I trained on Tuesday", and it is already what every other engine
/// uses (`workout_analytics.dart`, `functions/ai/workout_analytics.js`'s
/// `completedAtOf`, `today_pulse.dart`'s `weekActivity`). The old dashboard
/// stats were the only holdout, and aligning them is why the two streaks can
/// no longer disagree.
DateTime streakDayOf(LiveSession session) =>
    startOfDay(session.completedAt ?? session.startedAt);

/// Qualifying session counts per calendar day.
Map<DateTime, int> trainedDayCounts(List<LiveSession> sessions) {
  final counts = <DateTime, int>{};
  for (final session in sessions) {
    if (!qualifiesForStreak(session)) continue;
    final day = streakDayOf(session);
    counts[day] = (counts[day] ?? 0) + 1;
  }
  return counts;
}

/// Computes the streak from history and the user's day marks.
///
/// Pure: no clock, no repository. [now] drives "today", [maxGapDays] is the
/// rule, and [marks] carry restores (which bridge) and reasons (which don't).
TrainingStreak computeTrainingStreak({
  required List<LiveSession> sessions,
  required DateTime now,
  List<TrainingDayMark> marks = const [],
  int maxGapDays = kStreakMaxGapDays,
}) {
  final counts = trainedDayCounts(sessions);
  final trained = counts.keys.toSet();
  final marksByDay = <DateTime, TrainingDayMark>{
    for (final m in marks) startOfDay(m.day): m,
  };
  // A restore on a day that was trained anyway is a no-op, not a second link —
  // otherwise a wasted restore would quietly widen the allowance around a day
  // that never needed it.
  final restored = <DateTime>{
    for (final entry in marksByDay.entries)
      if (entry.value.restored && !trained.contains(entry.key)) entry.key,
  };

  final best = _bestRun(trained, maxGapDays);
  final lastTrained = _latestOnOrBefore(trained, startOfDay(now));

  // The chain is trained days plus the restores that bridge between them.
  final chain = <DateTime>{...trained, ...restored}.toList()
    ..sort((a, b) => b.compareTo(a));

  final today = startOfDay(now);
  final head = chain.where((d) => !d.isAfter(today)).firstOrNull;
  if (head == null || calendarDaysBetween(head, today) > maxGapDays) {
    // Nothing logged, or the allowance has already run out.
    return TrainingStreak(
      currentDays: 0,
      bestDays: best,
      days: const [],
      restoresUsed: 0,
      lastTrainedDay: lastTrained,
      daysUntilBreak: null,
    );
  }

  // Walk back while each step stays inside the allowance.
  var earliest = head;
  for (final day in chain) {
    if (!day.isBefore(earliest)) continue;
    if (calendarDaysBetween(day, earliest) > maxGapDays) break;
    earliest = day;
  }

  final days = <StreakDay>[];
  var trainedCount = 0;
  var restoresUsed = 0;
  for (
    var cursor = head;
    !cursor.isBefore(earliest);
    cursor = addCalendarDays(cursor, -1)
  ) {
    final mark = marksByDay[cursor];
    final StreakDayKind kind;
    if (trained.contains(cursor)) {
      kind = StreakDayKind.trained;
      trainedCount++;
    } else if (restored.contains(cursor)) {
      kind = StreakDayKind.restored;
      restoresUsed++;
    } else {
      kind = StreakDayKind.rest;
    }
    days.add(
      StreakDay(
        day: cursor,
        kind: kind,
        sessionCount: counts[cursor] ?? 0,
        reason: mark?.reason,
        note: mark?.note,
      ),
    );
  }

  if (trainedCount == 0) {
    return TrainingStreak(
      currentDays: 0,
      bestDays: best,
      days: const [],
      restoresUsed: 0,
      lastTrainedDay: lastTrained,
      daysUntilBreak: null,
    );
  }

  return TrainingStreak(
    currentDays: trainedCount,
    bestDays: best > trainedCount ? best : trainedCount,
    days: days,
    restoresUsed: restoresUsed,
    lastTrainedDay: lastTrained,
    daysUntilBreak: maxGapDays - calendarDaysBetween(head, today),
  );
}

/// Whether a restore may be spent on [day] right now.
///
/// Rationed deliberately: at most one per [kRestoreCooldownDays], only within
/// the last [kRestoreReachDays], never on today or the future, and never on a
/// day that was trained anyway. Without limits a streak stops measuring
/// anything.
bool canRestoreDay({
  required DateTime day,
  required DateTime now,
  required List<LiveSession> sessions,
  required List<TrainingDayMark> marks,
}) {
  final target = startOfDay(day);
  final today = startOfDay(now);
  final age = calendarDaysBetween(target, today);
  if (age <= 0) return false; // today or the future
  if (age > kRestoreReachDays) return false;
  if (trainedDayCounts(sessions).containsKey(target)) return false;
  for (final mark in marks) {
    if (!mark.restored) continue;
    final spent = startOfDay(mark.day);
    if (spent == target) return false; // already restored
    if (calendarDaysBetween(spent, today) < kRestoreCooldownDays) return false;
  }
  return true;
}

/// Whether spending a restore on [day] would actually keep the streak alive.
///
/// [canRestoreDay] answers whether a restore is *mechanically* eligible — recent
/// enough, off cooldown, not a day already trained. This answers the second,
/// quieter question the UI must not skip: would spending it change anything?
///
/// A restore only ever helps by bridging an earlier trained day into the live
/// run that reaches today, which raises [TrainingStreak.currentDays]. Where it
/// rescues nothing — no active streak to save, or a rest day already safely
/// inside the allowance — the count is untouched. Offered there, the restore
/// would confirm "your streak survives" and then change nothing while still
/// burning the [kRestoreCooldownDays] cooldown: the one outcome this feature
/// exists to prevent. The two predicates are kept apart so each gate stays
/// independently testable; the missed-day sheet requires both.
bool restoreRescuesStreak({
  required DateTime day,
  required DateTime now,
  required List<LiveSession> sessions,
  required List<TrainingDayMark> marks,
}) {
  final target = startOfDay(day);
  final without = computeTrainingStreak(
    sessions: sessions,
    now: now,
    marks: marks,
  );
  final withRestore = computeTrainingStreak(
    sessions: sessions,
    now: now,
    // Appended last so it wins the day key over any existing reason-only mark.
    marks: [...marks, TrainingDayMark(day: target, createdAt: now, restored: true)],
  );
  return withRestore.currentDays > without.currentDays;
}

/// The most recent day in [days] that is on or before [limit].
DateTime? _latestOnOrBefore(Set<DateTime> days, DateTime limit) {
  DateTime? best;
  for (final day in days) {
    if (day.isAfter(limit)) continue;
    if (best == null || day.isAfter(best)) best = day;
  }
  return best;
}

/// The longest run of trained days under the gap rule — restores excluded, so
/// an all-time best is always something that was actually trained.
int _bestRun(Set<DateTime> trained, int maxGapDays) {
  if (trained.isEmpty) return 0;
  final sorted = trained.toList()..sort();
  var best = 1;
  var run = 1;
  for (var i = 1; i < sorted.length; i++) {
    run = calendarDaysBetween(sorted[i - 1], sorted[i]) <= maxGapDays
        ? run + 1
        : 1;
    if (run > best) best = run;
  }
  return best;
}
