import 'logged_set.dart';

/// The three-way read on how today's set stacks up against the same set
/// from last time — judged on [SetProgressComparison.overallChangePercent].
enum ProgressVerdict { progressing, matched, down }

/// Where today's performance for a set stands against the same set from
/// last time (see `lastPerformanceFor`/`ExerciseHistory`) — reps % change,
/// weight change, volume (reps × weight) % change, and a single overall %
/// change combining them, rolled into a three-way [ProgressVerdict] for the
/// live Goal card. Produced by [compareToLastTime], which returns null
/// whenever there's nothing real to compare against — first time ever
/// training this set, or today's rep count hasn't been entered yet.
class SetProgressComparison {
  const SetProgressComparison({
    required this.verdict,
    required this.repsChangePercent,
    required this.weightChangeKg,
    required this.volumeChangePercent,
    required this.overallChangePercent,
  });

  final ProgressVerdict verdict;

  /// % change in reps vs. last time — null only when last time's reps were
  /// 0 (division-by-zero guard; not a real scenario in practice).
  final double? repsChangePercent;

  /// Absolute kg change vs. last time — null when either side has no
  /// weight (a bodyweight movement), since there's nothing to subtract.
  final double? weightChangeKg;

  /// % change in volume (reps × weight) vs. last time — null when either
  /// side has no weight, since volume isn't meaningful for a bodyweight set
  /// (see [overallChangePercent], which falls back to reps in that case).
  final double? volumeChangePercent;

  /// The single number the verdict is judged on: volume % change when both
  /// sides have a weight, else reps % change (a bodyweight movement has no
  /// load to factor in) — never null, always what actually drove the
  /// verdict.
  final double overallChangePercent;
}

/// Compares today's in-progress actuals ([actualReps]/[actualWeightKg])
/// against [previous] — the index-aligned set from the last time this exact
/// set was trained. Returns null when there's no real previous rep count
/// (never trained before, or that set was never actually logged) or no
/// rep count entered yet for today — nothing to judge a verdict against.
///
/// A verdict is "matched" only when today's reps AND weight are *exactly*
/// the same as last time — any real difference, however small, reads as
/// progressing or down instead of hiding inside a rounding threshold.
SetProgressComparison? compareToLastTime({
  required LoggedSet? previous,
  required int? actualReps,
  required double? actualWeightKg,
}) {
  final prevReps = previous?.actualReps;
  if (previous == null || prevReps == null || actualReps == null) return null;

  final prevWeight = previous.actualWeightKg;

  final repsChangePercent = prevReps == 0 ? null : (actualReps - prevReps) / prevReps * 100;

  double? weightChangeKg;
  double? volumeChangePercent;
  if (prevWeight != null && actualWeightKg != null) {
    weightChangeKg = actualWeightKg - prevWeight;
    final prevVolume = prevReps * prevWeight;
    final curVolume = actualReps * actualWeightKg;
    volumeChangePercent = prevVolume == 0 ? null : (curVolume - prevVolume) / prevVolume * 100;
  }

  final overall = volumeChangePercent ?? repsChangePercent ?? 0;
  final matched = actualReps == prevReps && actualWeightKg == prevWeight;
  final verdict = matched
      ? ProgressVerdict.matched
      : overall > 0
      ? ProgressVerdict.progressing
      : overall < 0
      ? ProgressVerdict.down
      : ProgressVerdict.matched;

  return SetProgressComparison(
    verdict: verdict,
    repsChangePercent: repsChangePercent,
    weightChangeKg: weightChangeKg,
    volumeChangePercent: volumeChangePercent,
    overallChangePercent: overall,
  );
}
