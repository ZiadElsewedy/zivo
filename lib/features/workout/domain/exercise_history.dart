import 'live_session.dart';
import 'logged_set.dart';
import 'session_exercise.dart';
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
///
/// **Slot first.** With a [slotId], the most recent time the exercise was done
/// *in that slot* wins, and the exercise's wider history — the same exercise
/// in another slot, day or split — is only the fallback. One exercise can be
/// prescribed very differently in two places (heavy 6–8 on Push, 12–15 on
/// Chest & Back), and last time's numbers are only a useful target when they
/// were done under the same prescription. Trends, PRs and strength still read
/// the whole history; this only decides which session "last time" means.
///
/// [exerciseId] must already be canonical on both sides — pass sessions
/// through `ExerciseIdentityResolver.canonicalize` first.
ExerciseHistory? lastPerformanceFor(
  String exerciseId,
  Iterable<LiveSession> pastSessions, {
  String? slotId,
}) {
  if (slotId != null) {
    final inSlot = _latest(
      pastSessions,
      (e) => e.exerciseId == exerciseId && e.effectiveSlotId == slotId,
    );
    if (inSlot != null) return inSlot;
  }
  return _latest(pastSessions, (e) => e.exerciseId == exerciseId);
}

ExerciseHistory? _latest(
  Iterable<LiveSession> pastSessions,
  bool Function(SessionExercise e) matches,
) {
  LiveSession? best;
  SessionExercise? bestExercise;
  for (final session in pastSessions) {
    if (session.status != SessionStatus.completed) continue;
    SessionExercise? hit;
    for (final e in session.exercises) {
      if (matches(e) && e.sets.any((s) => s.done)) {
        hit = e;
        break;
      }
    }
    if (hit == null) continue;
    final at = session.completedAt ?? session.startedAt;
    final bestAt = best?.completedAt ?? best?.startedAt;
    if (best == null || at.isAfter(bestAt!)) {
      best = session;
      bestExercise = hit;
    }
  }
  if (best == null) return null;
  return ExerciseHistory(
    performedAt: best.completedAt ?? best.startedAt,
    sets: bestExercise!.sets.where((s) => s.done).toList(growable: false),
  );
}
