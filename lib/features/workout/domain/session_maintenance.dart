import 'live_session.dart';
import 'session_status.dart';
import 'workout_session_repository.dart';
import 'workout_settings_repository.dart';

/// What a sweep decided to do with one left-open session.
enum StaleSessionOutcome {
  /// It logged real work, and was closed at its last logged set.
  closed,

  /// Nothing was ever logged in it, so it is indistinguishable from a session
  /// that was never started — deleted, the same rule
  /// `LiveSessionController.leave` already applies on the way out.
  deleted,
}

/// One sweep's decisions, for logging and for tests.
class StaleSessionSweep {
  const StaleSessionSweep({required this.closed, required this.deleted});

  static const none = StaleSessionSweep(closed: [], deleted: []);

  final List<LiveSession> closed;
  final List<String> deleted;

  int get total => closed.length + deleted.length;
  bool get isEmpty => total == 0;
}

/// Closes sessions that were left open — the sweep that stops a 6pm Tuesday
/// workout from still being "in progress" on Thursday.
///
/// Modelled on `SleepService`: a small domain service over repository
/// interfaces, wired once at app root and triggered on sign-in and on app
/// resume, rather than a side effect hidden inside a screen's build.
///
/// **What it will not do.** It never marks a set done, never writes a weight,
/// never turns a pending set into a skipped one, and never caps a duration to
/// the maximum. Closing a session is a statement about when it *ended*, and
/// the only end it will claim is one the user's own taps prove:
/// [LiveSession.autoClose] ends at the last resolved set, or admits the
/// duration is unknown. Everything logged is preserved exactly; everything not
/// logged stays not logged.
class SessionMaintenance {
  SessionMaintenance({
    required WorkoutSessionRepository sessions,
    required WorkoutSettingsRepository settings,
    // A named parameter cannot start with an underscore, so these cannot be
    // initializing formals — the same shape `LiveSessionController` uses.
    // ignore: prefer_initializing_formals
  }) : _sessions = sessions,
       // ignore: prefer_initializing_formals
       _settings = settings;

  final WorkoutSessionRepository _sessions;
  final WorkoutSettingsRepository _settings;

  /// The session a live screen currently has open, if any.
  ///
  /// Set by `LiveSessionPage` while it is mounted, cleared when it leaves.
  /// Without it there is a real (if narrow) way for this to do harm: a workout
  /// past the maximum, idle for the grace period, with the user sitting on the
  /// logging screen — the app resumes, the sweep runs, and the session closes
  /// underneath them. That controller owns its session; this defers to it.
  String? openSessionId;

  /// Sweeps every known session. [now] is injected so the rule is testable
  /// without waiting three hours.
  ///
  /// [exceptSessionId] spares one session explicitly; [openSessionId] does the
  /// same for whatever a live screen has open, which is the one way this could
  /// damage a workout actually in progress.
  Future<StaleSessionSweep> sweep({
    required DateTime now,
    String? exceptSessionId,
  }) async {
    final spared = exceptSessionId ?? openSessionId;
    final max = _settings.current.maxSessionDuration;
    final closed = <LiveSession>[];
    final deleted = <String>[];

    for (final session in _sessions.current) {
      if (session.status != SessionStatus.active) continue;
      if (session.id == spared) continue;
      if (!session.isStale(now: now, maxSessionDuration: max)) continue;

      if (!session.hasCompletedWorkingSet && session.completedSetCount == 0) {
        deleted.add(session.id);
        await _sessions.deleteSession(session.id);
        continue;
      }
      final result = session.autoClose(now: now);
      closed.add(result);
      await _sessions.saveSession(result);
    }
    return StaleSessionSweep(closed: closed, deleted: deleted);
  }
}
