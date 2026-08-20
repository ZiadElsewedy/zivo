import 'live_session.dart';
import 'logged_set.dart';
import 'progress_comparison.dart';
import 'session_status.dart';
import 'workout_day.dart';

/// One point in an exercise's session-over-session trend — a completed
/// session's top-set weight (null for a set logged with no weight) and total
/// volume (reps × weight, done sets only), oldest-to-newest.
class ExerciseTrendPoint {
  const ExerciseTrendPoint({required this.date, required this.topWeightKg, required this.volume});

  final DateTime date;
  final double? topWeightKg;
  final double volume;
}

/// Progress for one exercise within a day, rolled up from set-level
/// [compareToLastTime] comparisons between its two most recent completed
/// appearances. [verdict] is null when the exercise hasn't appeared in at
/// least two completed sessions of this day — nothing to compare yet.
class ExerciseProgress {
  const ExerciseProgress({
    required this.exerciseId,
    required this.name,
    required this.verdict,
    required this.repsChangePercent,
    required this.weightChangeKg,
    required this.volumeChangePercent,
    required this.lastTopWeightKg,
    required this.trend,
    required this.appearances,
  });

  final String exerciseId;
  final String name;
  final ProgressVerdict? verdict;
  final double? repsChangePercent;
  final double? weightChangeKg;
  final double? volumeChangePercent;

  /// The heaviest weight lifted in the most recent completed appearance —
  /// null if never logged with a weight (e.g. never trained, or bodyweight).
  final double? lastTopWeightKg;

  /// Oldest-to-newest, capped at the analysis's `trendLength`.
  final List<ExerciseTrendPoint> trend;

  /// How many completed sessions (within the scanned window) actually
  /// trained this exercise — 0 means it's never been logged for this day.
  final int appearances;
}

/// A day's progressive-overload analysis — per-exercise comparisons plus a
/// day-level rollup, built entirely from completed [LiveSession]s (never the
/// flat `Workout` log; see WORKOUT_SYSTEM.md §3.3).
class DayProgressAnalysis {
  const DayProgressAnalysis({
    required this.day,
    required this.exercises,
    required this.sessionCount,
    required this.improvedCount,
    required this.matchedCount,
    required this.regressedCount,
  });

  final WorkoutDay day;
  final List<ExerciseProgress> exercises;

  /// Total completed sessions found for this day (planId + dayId) — drives
  /// the page's empty (0) / single-session (1) / full-analysis (2+) states.
  final int sessionCount;

  final int improvedCount;
  final int matchedCount;
  final int regressedCount;

  int get comparableCount => improvedCount + matchedCount + regressedCount;

  /// The day's overall verdict, judged on which side has more exercises —
  /// null when nothing was comparable yet (no exercise has 2+ appearances).
  ProgressVerdict? get overallVerdict {
    if (comparableCount == 0) return null;
    if (improvedCount == regressedCount) return ProgressVerdict.matched;
    return improvedCount > regressedCount ? ProgressVerdict.progressing : ProgressVerdict.down;
  }
}

double _volumeOf(Iterable<LoggedSet> sets) {
  var total = 0.0;
  for (final s in sets) {
    final reps = s.actualReps;
    final weight = s.actualWeightKg;
    if (reps == null || weight == null) continue;
    total += reps * weight;
  }
  return total;
}

double? _topWeightOf(Iterable<LoggedSet> sets) {
  double? top;
  for (final s in sets) {
    final w = s.actualWeightKg;
    if (w != null && (top == null || w > top)) top = w;
  }
  return top;
}

List<LoggedSet> _doneSetsFor(LiveSession session, String exerciseId) {
  final exercise = session.exercises.firstWhere((e) => e.exerciseId == exerciseId);
  return exercise.sets.where((s) => s.done).toList(growable: false);
}

/// Analyzes progressive overload for [day] within plan [planId], from every
/// completed session in [allSessions] (any plan/day — this filters). Reuses
/// [compareToLastTime] for the actual verdict math; this only aggregates it.
DayProgressAnalysis analyzeDayProgress({
  required WorkoutDay day,
  required String planId,
  required List<LiveSession> allSessions,
  int trendLength = 6,
}) {
  final daySessions =
      allSessions.where((s) => s.status == SessionStatus.completed && s.planId == planId && s.dayId == day.id).toList()
        ..sort((a, b) => (b.completedAt ?? b.startedAt).compareTo(a.completedAt ?? a.startedAt));

  final plannedExercises = [...day.exercises]..sort((a, b) => a.order.compareTo(b.order));

  var improved = 0;
  var matched = 0;
  var regressed = 0;
  final results = <ExerciseProgress>[];

  for (final ex in plannedExercises) {
    final exerciseId = ex.id;
    // Newest-first sessions that actually trained this exercise (>=1 done set).
    final appearances = daySessions
        .where((s) => s.exercises.any((e) => e.exerciseId == exerciseId && e.sets.any((set) => set.done)))
        .toList();

    if (appearances.isEmpty) {
      results.add(
        ExerciseProgress(
          exerciseId: exerciseId,
          name: ex.name,
          verdict: null,
          repsChangePercent: null,
          weightChangeKg: null,
          volumeChangePercent: null,
          lastTopWeightKg: null,
          trend: const [],
          appearances: 0,
        ),
      );
      continue;
    }

    final trend = [
      for (final session in appearances.take(trendLength).toList().reversed)
        ExerciseTrendPoint(
          date: session.completedAt ?? session.startedAt,
          topWeightKg: _topWeightOf(_doneSetsFor(session, exerciseId)),
          volume: _volumeOf(_doneSetsFor(session, exerciseId)),
        ),
    ];

    final lastSets = _doneSetsFor(appearances.first, exerciseId);
    final lastTopWeightKg = _topWeightOf(lastSets);

    if (appearances.length < 2) {
      results.add(
        ExerciseProgress(
          exerciseId: exerciseId,
          name: ex.name,
          verdict: null,
          repsChangePercent: null,
          weightChangeKg: null,
          volumeChangePercent: null,
          lastTopWeightKg: lastTopWeightKg,
          trend: trend,
          appearances: 1,
        ),
      );
      continue;
    }

    final previousSets = _doneSetsFor(appearances[1], exerciseId);
    // Index-align done sets between the two sessions — a set added/removed
    // between sessions just isn't compared past the shorter side's length.
    final pairCount = lastSets.length < previousSets.length ? lastSets.length : previousSets.length;

    final comparisons = <SetProgressComparison>[];
    for (var i = 0; i < pairCount; i++) {
      final c = compareToLastTime(
        previous: previousSets[i],
        actualReps: lastSets[i].actualReps,
        actualWeightKg: lastSets[i].actualWeightKg,
      );
      if (c != null) comparisons.add(c);
    }

    final lastVolume = _volumeOf(lastSets.take(pairCount));
    final previousVolume = _volumeOf(previousSets.take(pairCount));
    final volumeChangePercent = previousVolume == 0 ? null : (lastVolume - previousVolume) / previousVolume * 100;

    final lastTotalReps = lastSets.take(pairCount).fold<int>(0, (sum, s) => sum + (s.actualReps ?? 0));
    final prevTotalReps = previousSets.take(pairCount).fold<int>(0, (sum, s) => sum + (s.actualReps ?? 0));
    final repsChangePercent = prevTotalReps == 0 ? null : (lastTotalReps - prevTotalReps) / prevTotalReps * 100;

    double? weightChangeKg;
    final prevTopWeightKg = _topWeightOf(previousSets);
    if (lastTopWeightKg != null && prevTopWeightKg != null) {
      weightChangeKg = lastTopWeightKg - prevTopWeightKg;
    }

    ProgressVerdict? verdict;
    if (comparisons.isNotEmpty) {
      final up = comparisons.where((c) => c.verdict == ProgressVerdict.progressing).length;
      final down = comparisons.where((c) => c.verdict == ProgressVerdict.down).length;
      verdict = up == down
          ? ProgressVerdict.matched
          : (up > down ? ProgressVerdict.progressing : ProgressVerdict.down);
      switch (verdict) {
        case ProgressVerdict.progressing:
          improved++;
        case ProgressVerdict.matched:
          matched++;
        case ProgressVerdict.down:
          regressed++;
      }
    }

    results.add(
      ExerciseProgress(
        exerciseId: exerciseId,
        name: ex.name,
        verdict: verdict,
        repsChangePercent: repsChangePercent,
        weightChangeKg: weightChangeKg,
        volumeChangePercent: volumeChangePercent,
        lastTopWeightKg: lastTopWeightKg,
        trend: trend,
        appearances: appearances.length,
      ),
    );
  }

  return DayProgressAnalysis(
    day: day,
    exercises: results,
    sessionCount: daySessions.length,
    improvedCount: improved,
    matchedCount: matched,
    regressedCount: regressed,
  );
}
