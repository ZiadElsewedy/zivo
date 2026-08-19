import 'live_session.dart';
import 'logged_set.dart';
import 'session_status.dart';

/// What an exercise looked like the last time it was trained — the done sets
/// from the most recent completed session that included it, so the live screen
/// can show "previous 60 × 8" beside each set and compute the progress delta.
class ExerciseHistory {
  const ExerciseHistory({required this.performedAt, required this.sets});

  final DateTime performedAt;

  /// The done sets for the exercise, in order — index-align with the current
  /// session's sets to show each set's previous performance.
  final List<LoggedSet> sets;

  /// The heaviest weight lifted last time (its "top set"), if any.
  double? get topWeightKg {
    double? top;
    for (final s in sets) {
      final w = s.actualWeightKg;
      if (w != null && (top == null || w > top)) top = w;
    }
    return top;
  }
}

/// The most recent completed session's performance for [exerciseId], scanning
/// [pastSessions] (any order). Only [SessionStatus.completed] sessions with at
/// least one done set for the exercise count. Returns null if never trained.
ExerciseHistory? lastPerformanceFor(String exerciseId, Iterable<LiveSession> pastSessions) {
  LiveSession? best;
  for (final session in pastSessions) {
    if (session.status != SessionStatus.completed) continue;
    final hasDone = session.exercises.any(
      (e) => e.exerciseId == exerciseId && e.sets.any((s) => s.done),
    );
    if (!hasDone) continue;
    final at = session.completedAt ?? session.startedAt;
    final bestAt = best?.completedAt ?? best?.startedAt;
    if (best == null || at.isAfter(bestAt!)) best = session;
  }
  if (best == null) return null;

  final exercise = best.exercises.firstWhere((e) => e.exerciseId == exerciseId);
  return ExerciseHistory(
    performedAt: best.completedAt ?? best.startedAt,
    sets: exercise.sets.where((s) => s.done).toList(growable: false),
  );
}
