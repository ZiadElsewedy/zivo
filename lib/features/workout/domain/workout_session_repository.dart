import 'live_session.dart';

/// The seam between the app and live-session storage (in-memory demo for now,
/// Firestore-backed later) — every started/finished/abandoned session, newest
/// first. Mirrors the workouts-log repository's list shape (so history can be
/// scanned for `lastPerformanceFor`) plus the workout-plan repository's single
/// "active" convenience, since at most one session is normally in progress.
abstract interface class WorkoutSessionRepository {
  List<LiveSession> get current;
  Stream<List<LiveSession>> watchAll();

  /// The in-progress session, if any — the most recent one still active.
  /// Derived from [current], not separately stored.
  LiveSession? get activeSession;
  Stream<LiveSession?> watchActiveSession();

  /// Creates or replaces [session] by id (idempotent — the live screen saves
  /// on every set edit).
  Future<void> saveSession(LiveSession session);

  Future<void> deleteSession(String id);
}
