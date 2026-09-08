import 'live_session.dart';
import 'workout_day.dart';
import 'workout_plan.dart';
import 'workout_settings.dart';

/// The day a plan's "up next" card should show, and the session (if any) to
/// resume into it.
///
/// A session running for [WorkoutPlan] wins over the rotation's
/// [WorkoutPlan.nextDay] — the card should mirror what's actually under way,
/// not offer a fresh start on a different day — falling back to
/// [WorkoutPlan.nextDay] when there's no session for this plan, or when the
/// session's day was edited out of the plan since it started.
///
/// This is the single place both the Home and Workout-tab "up next" cards
/// read, so they can't drift the way they once did — one branching on the
/// active session's own day, the other always pinned to [WorkoutPlan.nextDay]
/// and only offering Resume when the two happened to already match.
class UpNextSelection {
  const UpNextSelection({required this.day, required this.resumable});

  /// The day to show, or null only when [WorkoutPlan.nextDay] is also null
  /// (the plan has no days).
  final WorkoutDay? day;

  /// The plan's own active session to resume into [day], or null to start a
  /// fresh one.
  final LiveSession? resumable;
}

/// [now] and [maxSessionDuration] are what stop a session that was left open
/// from hijacking the card forever.
///
/// A running session outranks the rotation because it mirrors what is actually
/// under way — but a session abandoned on Tuesday is not under way on
/// Thursday, and until this check existed it went on offering "Resume Push" in
/// place of the day that was genuinely due, indefinitely. A stale session is
/// passed over here and closed by `SessionMaintenance` shortly after; the card
/// falls back to [WorkoutPlan.nextDay], which is the truth.
///
/// Both default to "never stale" so a caller with no clock (a pure test, a
/// screen that genuinely wants the raw preference) keeps the old behaviour
/// explicitly rather than by omission.
UpNextSelection resolveUpNext(
  WorkoutPlan plan,
  LiveSession? activeSession, {
  DateTime? now,
  Duration maxSessionDuration = const Duration(
    minutes: kDefaultMaxSessionDurationMinutes,
  ),
}) {
  final stale =
      activeSession != null &&
      now != null &&
      activeSession.isStale(now: now, maxSessionDuration: maxSessionDuration);
  final activeForPlan =
      activeSession != null && !stale && activeSession.planId == plan.id
      ? activeSession
      : null;
  final sessionDay = activeForPlan == null ? null : _dayById(plan, activeForPlan.dayId);
  return UpNextSelection(
    day: sessionDay ?? plan.nextDay,
    resumable: sessionDay == null ? null : activeForPlan,
  );
}

WorkoutDay? _dayById(WorkoutPlan plan, String dayId) {
  for (final day in plan.days) {
    if (day.id == dayId) return day;
  }
  return null;
}
