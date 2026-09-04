/// ZIVO's centralized workout analytics engine.
///
/// ONE source of truth for "how am I progressing", consumed by BOTH the
/// progress UI and the AI coach — never re-implemented per surface. A pure
/// function of a user's [LiveSession] history plus `now`; it reads no clock
/// and no repository, so it is deterministic and testable, and its Node
/// mirror (`functions/ai/workout_analytics.js`) can be pinned to the exact
/// same numbers by shared golden vectors.
///
/// Deliberately shallow (per the product brief): estimated 1RM, PRs,
/// per-exercise status, a simple per-muscle rollup, working volume, and a
/// plain-language overall summary — NOT a deep analytics platform. It answers
/// five questions and stops: Am I progressing? What's improving? What's stuck?
/// Any new PRs? What next?
///
/// Two correctness rules it holds throughout, both fixes for audit findings:
///  1. **Warm-ups never count as training.** Only [_isWorkingSet] sets feed
///     e1RM, PRs, volume and progression — a warm-up ramp must not inflate
///     tonnage or be index-aligned against a working set.
///  2. **No verdict from one workout.** A status needs [kMinAppearances]
///     working appearances and a real [kMeaningfulChangePct] threshold, and
///     compares the best of a recent window against an earlier one so a single
///     off day can neither manufacture nor erase progress.
library;

import '../live_session.dart';
import '../logged_set.dart';
import '../progression.dart';
import '../rep_target.dart';
import '../session_status.dart';
import '../set_outcome.dart';
import '../set_type.dart';

// ---- Tunables (mirrored verbatim in the Node engine) ----------------------

/// Reps above this make an e1RM estimate unreliable, so a high-rep set
/// contributes no strength estimate (it still counts as volume). Epley and
/// every other formula drift badly past ~12 reps.
const int kMaxReliableRepsForE1RM = 12;

/// Fewest working appearances of an exercise before ZIVO will call a
/// direction. Below this it reports [ProgressStatus.building] — "not enough
/// yet", never a guess.
const int kMinAppearances = 3;

/// At/above this many working appearances, a flat exercise reads as
/// [ProgressStatus.plateauing] (stuck for a while) rather than the gentler
/// [ProgressStatus.maintaining] (stable, but not for long).
const int kPlateauAppearances = 4;

/// The band that counts as "the same". A performance change smaller than this
/// (in %) is inside normal day-to-day noise and never flips a verdict.
const double kMeaningfulChangePct = 2.5;

/// Beyond this magnitude a per-exercise strength change is not a trustworthy
/// figure to show — more than a doubling (or halving) of estimated strength
/// means the baseline was a near-empty or first-exposure load, so the honest
/// read is "you started light", not a literal "+400%". The DIRECTION still
/// stands (the status is set from the raw comparison); only the precise number
/// is withheld ([ExercisePerformance.strengthChangePercent] becomes null). This
/// is the guard that stops a light early session headlining an absurd percent.
const double kMaxReliableStrengthChangePct = 100.0;

/// A muscle's weekly working volume dropping by at least this much (%) vs the
/// prior comparable week is worth flagging as needing attention.
const double kMuscleVolumeDropPct = 20.0;

/// The rolling window every "this period vs last period" comparison uses — 7
/// days. The ONE definition of a training week for analytics (the audit found
/// tonnage using trailing-7 while sessions/streaks used calendar weeks; this
/// engine standardizes on trailing windows so progression comparisons line
/// up). Calendar-week streaks legitimately stay in `training_dashboard_stats`.
const int kWeekWindowDays = 7;

/// The headline strength window — "your strength is up 8% over the last 6
/// weeks". Recent 6 weeks vs the 6 before it.
const int kStrengthWindowDays = 42;

/// A PR counts as "recent" (surfaced in the Recent PRs strip) for this long.
const int kRecentPrWindowDays = 30;

/// Floating-point slack for weight / e1RM equality — a PR must clear the old
/// best by more than this to count, so re-lifting the same load is not a PR.
const double _eps = 0.0001;

// ---- Enums ----------------------------------------------------------------

/// The plain-language direction of an exercise (or the whole training block).
enum ProgressStatus {
  progressing,
  maintaining,
  plateauing,
  regressing,

  /// Not enough working history yet to call a direction.
  building,
}

/// Which kind of best a [PrRecord] represents.
enum PrKind { heaviestWeight, mostReps, bestEstimatedStrength }

/// Whether a [TrainingFinding] states a measured fact or an interpretation of
/// one — so the AI can keep the line between the two (brief §15).
enum FindingConfidence { fact, interpretation }

/// The role a [TrainingFinding] plays, mirroring the diet coach's typed
/// findings so the AI phrases them consistently across both surfaces.
enum FindingKind { observation, analysis, recommendation, warning, encouragement }

// ---- Value types ----------------------------------------------------------

/// One completed appearance of an exercise, reduced to the few numbers the
/// engine reasons over — working sets only.
class ExerciseAppearance {
  const ExerciseAppearance({
    required this.date,
    required this.bestE1RM,
    required this.topWeightKg,
    required this.workingVolumeKg,
    required this.bestReps,
    required this.bestRepsWeightKg,
  });

  final DateTime date;

  /// Best estimated 1RM across this session's working sets (null when nothing
  /// was loaded, or every working set was above [kMaxReliableRepsForE1RM]).
  final double? bestE1RM;

  /// Heaviest working-set load (null for a bodyweight movement).
  final double? topWeightKg;

  /// Σ reps × weight over working sets (0 when unloaded).
  final double workingVolumeKg;

  /// Most reps on any single working set this session.
  final int bestReps;

  /// The load carried on that best-reps set (null if unloaded).
  final double? bestRepsWeightKg;
}

/// Everything the UI/AI needs about one exercise's trajectory.
class ExercisePerformance {
  const ExercisePerformance({
    required this.exerciseId,
    required this.name,
    required this.muscleGroup,
    required this.status,
    required this.appearances,
    required this.currentE1RM,
    required this.baselineE1RM,
    required this.strengthChangePercent,
    required this.lastPerformedAt,
    required this.e1rmSeries,
  });

  final String exerciseId;
  final String name;

  /// The normalized major muscle bucket ([normalizeMuscleGroup]), or null.
  final String? muscleGroup;

  final ProgressStatus status;

  /// How many completed working appearances fed this (drives `building`).
  final int appearances;

  /// Most-recent-appearance best e1RM — the "current estimated strength".
  /// Null for a bodyweight movement (status is then judged on reps).
  final double? currentE1RM;

  /// The comparable earlier best e1RM the change is measured from.
  final double? baselineE1RM;

  /// Signed % change of the performance score (e1RM when loaded, else best
  /// reps) — recent window vs baseline. Null when [status] is `building`.
  final double? strengthChangePercent;

  final DateTime lastPerformedAt;

  /// Oldest→newest e1RM points for a sparkline (nulls dropped).
  final List<double> e1rmSeries;

  bool get isWeighted => currentE1RM != null;
}

/// A single personal record for one exercise.
class PrRecord {
  const PrRecord({
    required this.exerciseId,
    required this.name,
    required this.kind,
    required this.weightKg,
    required this.reps,
    required this.estimatedOneRepMax,
    required this.achievedAt,
  });

  final String exerciseId;
  final String name;
  final PrKind kind;

  /// The load on the record set (null only for an unloaded reps PR).
  final double? weightKg;
  final int reps;

  /// The e1RM of the record set (null when unloaded / unreliable reps).
  final double? estimatedOneRepMax;
  final DateTime achievedAt;
}

/// A major muscle bucket's simple weekly picture.
class MuscleGroupProgress {
  const MuscleGroupProgress({
    required this.muscle,
    required this.weeklyWorkingSets,
    required this.status,
    required this.volumeChangePercent,
  });

  final String muscle;

  /// Working sets in the trailing [kWeekWindowDays].
  final int weeklyWorkingSets;
  final ProgressStatus status;

  /// Working-volume % change vs the prior comparable week (null when there was
  /// no prior volume to compare against).
  final double? volumeChangePercent;
}

/// Working-volume trend — the one volume number the brief asks for.
class VolumeSummary {
  const VolumeSummary({
    required this.thisWeekKg,
    required this.lastWeekKg,
    required this.changePercent,
  });

  final double thisWeekKg;
  final double lastWeekKg;

  /// % change vs last week, null when last week had no working volume.
  final double? changePercent;
}

/// One highlight/warning/next-step, typed and evidenced the way the diet
/// coach's findings are — the AI leads with these and never contradicts them.
class TrainingFinding {
  const TrainingFinding({
    required this.kind,
    required this.confidence,
    required this.text,
    this.evidence = const [],
  });

  final FindingKind kind;
  final FindingConfidence confidence;

  /// A plain sentence that is correct on its own.
  final String text;

  /// The analysis fields this rests on (for traceability / the validator).
  final List<String> evidence;
}

/// A concrete, data-grounded next step for one exercise — reuses the live
/// session's [computeGoal] double-progression logic verbatim.
class NextStepRecommendation {
  const NextStepRecommendation({
    required this.exerciseId,
    required this.name,
    required this.text,
  });

  final String exerciseId;
  final String name;
  final String text;
}

/// The whole picture — the single object the progress UI renders and the AI
/// coach is handed.
class TrainingAnalysis {
  const TrainingAnalysis({
    required this.overallStatus,
    required this.summaryHeadline,
    required this.summaryDetail,
    required this.overallStrengthChangePercent,
    required this.exercises,
    required this.muscles,
    required this.volume,
    required this.recentPrs,
    required this.improving,
    required this.needsAttention,
    required this.nextStep,
    required this.findings,
    required this.completedSessionCount,
  });

  final ProgressStatus overallStatus;
  final String summaryHeadline;
  final String summaryDetail;

  /// Median strength change across judged exercises over [kStrengthWindowDays]
  /// — null when nothing had enough history.
  final double? overallStrengthChangePercent;

  /// Every exercise with at least one working appearance, best-first by how
  /// much it moved.
  final List<ExercisePerformance> exercises;
  final List<MuscleGroupProgress> muscles;
  final VolumeSummary volume;

  /// PRs set within [kRecentPrWindowDays], newest first.
  final List<PrRecord> recentPrs;

  /// Exercises clearly improving (subset of [exercises]).
  final List<ExercisePerformance> improving;

  /// Exercises stuck/declining worth a look (subset of [exercises]).
  final List<ExercisePerformance> needsAttention;

  final NextStepRecommendation? nextStep;
  final List<TrainingFinding> findings;
  final int completedSessionCount;

  bool get isEmpty => completedSessionCount == 0;
}

// ---- Primitives -----------------------------------------------------------

/// Epley estimated 1RM from one working set — `w × (1 + reps/30)`. Returns
/// the bare weight for a true single, and null when there's no load, a
/// non-positive load, or the reps are too high to estimate reliably
/// ([kMaxReliableRepsForE1RM]). This is the ONLY place the formula lives.
double? estimatedOneRepMax(double? weightKg, int? reps) {
  if (weightKg == null || reps == null) return null;
  if (weightKg <= 0 || reps < 1 || reps > kMaxReliableRepsForE1RM) return null;
  if (reps == 1) return weightKg;
  return weightKg * (1 + reps / 30.0);
}

/// A set that counts as training: performed ([LoggedSet.done]) and not a
/// warm-up. Dropsets and to-failure sets are working sets; only [SetType.warmup]
/// is excluded.
///
/// Exposed publicly ([isWorkingSet]) so the deeper per-exercise engine
/// (`exercise_analysis.dart`) applies the EXACT same rule — a warm-up must
/// never leak into a session's tonnage or intensity there either.
bool isWorkingSet(LoggedSet s) => s.done && s.type != SetType.warmup;
bool _isWorkingSet(LoggedSet s) => isWorkingSet(s);

/// Folds a free-text `muscleGroup` into one of ZIVO's six major buckets so a
/// simple per-area rollup is reliable despite inconsistent labels ("Pecs",
/// "chest", "Upper chest" → "Chest"). Returns null when nothing matches — the
/// caller keeps such work out of the muscle rollup rather than guessing.
String? normalizeMuscleGroup(String? raw) {
  if (raw == null) return null;
  final s = raw.toLowerCase();
  bool has(List<String> keys) => keys.any(s.contains);
  if (has(['chest', 'pec', 'bench'])) return 'Chest';
  if (has(['back', 'lat', 'row', 'pull', 'trap', 'rhomboid', 'erector'])) {
    return 'Back';
  }
  if (has(['quad', 'hamstring', 'glute', 'calf', 'calves', 'leg', 'squat',
      'lunge', 'hip'])) {
    return 'Legs';
  }
  if (has(['shoulder', 'delt', 'ohp', 'press (overhead)', 'lateral raise'])) {
    return 'Shoulders';
  }
  if (has(['bicep', 'tricep', 'forearm', 'arm', 'curl'])) return 'Arms';
  if (has(['ab', 'core', 'oblique'])) return 'Core';
  return null;
}

// ---- The engine -----------------------------------------------------------

/// Reduces one session's working sets for [exerciseId] into an
/// [ExerciseAppearance], or null when it had no working set for that exercise.
ExerciseAppearance? _appearanceFor(LiveSession session, String exerciseId) {
  final ex = session.exercises
      .where((e) => e.exerciseId == exerciseId)
      .fold<List<LoggedSet>>([], (acc, e) => acc..addAll(e.sets));
  final working = ex.where(_isWorkingSet).toList(growable: false);
  if (working.isEmpty) return null;

  double? bestE1RM;
  double? topWeight;
  var volume = 0.0;
  var bestReps = 0;
  double? bestRepsWeight;
  for (final s in working) {
    final reps = s.actualReps;
    final w = s.actualWeightKg;
    if (reps != null && w != null) volume += reps * w;
    if (w != null && (topWeight == null || w > topWeight)) topWeight = w;
    final e = estimatedOneRepMax(w, reps);
    if (e != null && (bestE1RM == null || e > bestE1RM)) bestE1RM = e;
    if (reps != null && reps > bestReps) {
      bestReps = reps;
      bestRepsWeight = w;
    }
  }
  return ExerciseAppearance(
    date: session.completedAt ?? session.startedAt,
    bestE1RM: bestE1RM,
    topWeightKg: topWeight,
    workingVolumeKg: volume,
    bestReps: bestReps,
    bestRepsWeightKg: bestRepsWeight,
  );
}

/// Every exerciseId ever seen, mapped to its completed working appearances,
/// oldest→newest. Also carries the freshest display name and muscle per id.
class _ExerciseHistory {
  _ExerciseHistory(this.name, this.muscleGroup);
  String name;
  String? muscleGroup;
  final List<ExerciseAppearance> appearances = [];
}

Map<String, _ExerciseHistory> _historyByExercise(List<LiveSession> completed) {
  // Newest session first drives "freshest name"; appearances are re-sorted
  // oldest→newest after collection.
  final byId = <String, _ExerciseHistory>{};
  for (final session in completed) {
    for (final ex in session.exercises) {
      final appearance = _appearanceFor(session, ex.exerciseId);
      if (appearance == null) continue;
      final entry = byId.putIfAbsent(
        ex.exerciseId,
        () => _ExerciseHistory(ex.name, normalizeMuscleGroup(ex.muscleGroup)),
      );
      entry.appearances.add(appearance);
    }
  }
  for (final entry in byId.values) {
    entry.appearances.sort((a, b) => a.date.compareTo(b.date));
  }
  return byId;
}

/// Best reps across appearances (for a purely bodyweight movement, where reps
/// are the only progression signal). Null when none logged reps.
double? _bestReps(List<ExerciseAppearance> apps) {
  double? best;
  for (final a in apps) {
    if (a.bestReps > 0 && (best == null || a.bestReps > best)) {
      best = a.bestReps.toDouble();
    }
  }
  return best;
}

/// Classifies one exercise from its oldest→newest appearances. Best-of-recent
/// vs best-of-earlier so a single bad day neither creates nor hides a trend.
ExercisePerformance _classify(String id, _ExerciseHistory h) {
  final apps = h.appearances;
  final last = apps.last;
  final series = [for (final a in apps) if (a.bestE1RM != null) a.bestE1RM!];

  ProgressStatus status;
  double? changePercent;
  double? baseline;
  if (apps.length < kMinAppearances) {
    status = ProgressStatus.building;
  } else {
    // Recent window = last min(2, n) appearances; baseline = the rest. Compare
    // on ONE metric so kilograms and reps are never divided by each other:
    // estimated 1RM for a loaded lift, best reps for a purely bodyweight one.
    // Each window keeps its BEST so a single off day can't swing either side.
    final recentCount = apps.length >= 2 ? 2 : 1;
    final recentApps = apps.sublist(apps.length - recentCount);
    final earlierApps = apps.sublist(0, apps.length - recentCount);
    final weighted = apps.any((a) => a.bestE1RM != null);
    final recentScore =
        weighted ? _bestE1RM(recentApps) : _bestReps(recentApps);
    final baselineScore =
        weighted ? _bestE1RM(earlierApps) : _bestReps(earlierApps);
    if (recentScore == null || baselineScore == null || baselineScore <= 0) {
      // A loaded lift whose baseline window carries no logged weight has no
      // comparable strength number — report "building", never a reps-vs-kg
      // ratio (the bug that turned an unweighted first session into +2750%).
      status = ProgressStatus.building;
    } else {
      final raw = (recentScore - baselineScore) / baselineScore * 100;
      baseline = weighted ? _bestE1RM(earlierApps) : null;
      if (raw >= kMeaningfulChangePct) {
        status = ProgressStatus.progressing;
      } else if (raw <= -kMeaningfulChangePct) {
        status = ProgressStatus.regressing;
      } else if (apps.length >= kPlateauAppearances) {
        status = ProgressStatus.plateauing;
      } else {
        status = ProgressStatus.maintaining;
      }
      // The direction stands; report the % only when the baseline is a
      // trustworthy reference (see [kMaxReliableStrengthChangePct]).
      changePercent = raw.abs() <= kMaxReliableStrengthChangePct ? raw : null;
    }
  }

  return ExercisePerformance(
    exerciseId: id,
    name: h.name,
    muscleGroup: h.muscleGroup,
    status: status,
    appearances: apps.length,
    currentE1RM: last.bestE1RM,
    baselineE1RM: baseline,
    strengthChangePercent: changePercent,
    lastPerformedAt: last.date,
    e1rmSeries: series,
  );
}

double? _bestE1RM(List<ExerciseAppearance> apps) {
  double? best;
  for (final a in apps) {
    final e = a.bestE1RM;
    if (e != null && (best == null || e > best)) best = e;
  }
  return best;
}

/// All-time PRs per exercise, derived purely from [completed] history (no
/// stored ledger). One record per [PrKind] per exercise, achieved-earliest
/// wins a tie so the date is when it was FIRST reached.
Map<String, Map<PrKind, PrRecord>> personalRecords(List<LiveSession> completed) {
  final byId = <String, Map<PrKind, PrRecord>>{};
  // Oldest first so the FIRST time a best is reached is the one kept.
  final ordered = [...completed]
    ..sort((a, b) =>
        (a.completedAt ?? a.startedAt).compareTo(b.completedAt ?? b.startedAt));
  for (final session in ordered) {
    final at = session.completedAt ?? session.startedAt;
    for (final ex in session.exercises) {
      for (final s in ex.sets) {
        if (!_isWorkingSet(s)) continue;
        final reps = s.actualReps;
        final w = s.actualWeightKg;
        if (reps == null) continue;
        final records = byId.putIfAbsent(ex.exerciseId, () => {});

        // Heaviest weight (requires a load).
        if (w != null) {
          final cur = records[PrKind.heaviestWeight];
          if (cur == null || w > (cur.weightKg ?? 0) + _eps) {
            records[PrKind.heaviestWeight] = PrRecord(
              exerciseId: ex.exerciseId,
              name: ex.name,
              kind: PrKind.heaviestWeight,
              weightKg: w,
              reps: reps,
              estimatedOneRepMax: estimatedOneRepMax(w, reps),
              achievedAt: at,
            );
          }
        }

        // Most reps (heavier load breaks a rep tie so it isn't a warm-up-y PR).
        final repPr = records[PrKind.mostReps];
        final beatsReps = repPr == null ||
            reps > repPr.reps ||
            (reps == repPr.reps && (w ?? 0) > (repPr.weightKg ?? 0) + _eps);
        if (beatsReps) {
          records[PrKind.mostReps] = PrRecord(
            exerciseId: ex.exerciseId,
            name: ex.name,
            kind: PrKind.mostReps,
            weightKg: w,
            reps: reps,
            estimatedOneRepMax: estimatedOneRepMax(w, reps),
            achievedAt: at,
          );
        }

        // Best estimated 1RM (requires a reliable estimate).
        final e = estimatedOneRepMax(w, reps);
        if (e != null) {
          final cur = records[PrKind.bestEstimatedStrength];
          if (cur == null || e > (cur.estimatedOneRepMax ?? 0) + _eps) {
            records[PrKind.bestEstimatedStrength] = PrRecord(
              exerciseId: ex.exerciseId,
              name: ex.name,
              kind: PrKind.bestEstimatedStrength,
              weightKg: w,
              reps: reps,
              estimatedOneRepMax: e,
              achievedAt: at,
            );
          }
        }
      }
    }
  }
  return byId;
}

/// The PRs the just-finished [session] newly set — computed by diffing the
/// all-time bests WITH the session against those from history BEFORE it, so a
/// record only counts when this session actually beat what came before.
/// [priorSessions] must NOT include [session]. Surfaced right after a workout.
List<PrRecord> detectNewPrs({
  required LiveSession session,
  required List<LiveSession> priorSessions,
}) {
  if (session.status != SessionStatus.completed) return const [];
  final before = personalRecords(priorSessions);
  final after = personalRecords([...priorSessions, session]);
  final fresh = <PrRecord>[];
  for (final entry in after.entries) {
    final priorForEx = before[entry.key] ?? const {};
    for (final rec in entry.value.values) {
      // Only records THIS session produced (achievedAt == session time) and
      // that strictly beat the prior best of that kind.
      final sessionAt = session.completedAt ?? session.startedAt;
      if (rec.achievedAt != sessionAt) continue;
      final prior = priorForEx[rec.kind];
      final isNew = switch (rec.kind) {
        PrKind.heaviestWeight =>
          prior == null || (rec.weightKg ?? 0) > (prior.weightKg ?? 0) + _eps,
        PrKind.mostReps => prior == null ||
            rec.reps > prior.reps ||
            (rec.reps == prior.reps &&
                (rec.weightKg ?? 0) > (prior.weightKg ?? 0) + _eps),
        PrKind.bestEstimatedStrength => prior == null ||
            (rec.estimatedOneRepMax ?? 0) >
                (prior.estimatedOneRepMax ?? 0) + _eps,
      };
      // A brand-new exercise's very first working set is a baseline, not a
      // "PR" worth celebrating — require some prior history for that exercise.
      if (isNew && prior != null) fresh.add(rec);
    }
  }
  // Heaviest-weight first, then best strength, then reps — the order they read.
  fresh.sort((a, b) => a.kind.index.compareTo(b.kind.index));
  return fresh;
}

/// Working volume (Σ reps × weight over working sets) inside [fromDays,toDays)
/// day-offsets back from [now], over completed sessions.
double _windowVolume(
  List<LiveSession> completed,
  DateTime now,
  int fromDaysAgo,
  int toDaysAgo,
) {
  final today = DateTime(now.year, now.month, now.day);
  final start = today.subtract(Duration(days: fromDaysAgo));
  final end = today.subtract(Duration(days: toDaysAgo));
  var total = 0.0;
  for (final session in completed) {
    final at = session.completedAt ?? session.startedAt;
    final day = DateTime(at.year, at.month, at.day);
    if (day.isBefore(start) || !day.isBefore(end)) continue;
    for (final ex in session.exercises) {
      for (final s in ex.sets) {
        if (!_isWorkingSet(s)) continue;
        final reps = s.actualReps;
        final w = s.actualWeightKg;
        if (reps != null && w != null) total += reps * w;
      }
    }
  }
  return total;
}

/// The one public entry point. Builds the full [TrainingAnalysis] from every
/// known session (any status; it filters to completed) as of [now].
TrainingAnalysis analyzeTraining({
  required List<LiveSession> sessions,
  required DateTime now,
}) {
  final completed = sessions
      .where((s) => s.status == SessionStatus.completed)
      .toList(growable: false);

  if (completed.isEmpty) {
    return TrainingAnalysis(
      overallStatus: ProgressStatus.building,
      summaryHeadline: "Let's get started",
      summaryDetail:
          'Log a few sessions and ZIVO will start tracking how you progress.',
      overallStrengthChangePercent: null,
      exercises: const [],
      muscles: const [],
      volume: const VolumeSummary(thisWeekKg: 0, lastWeekKg: 0, changePercent: null),
      recentPrs: const [],
      improving: const [],
      needsAttention: const [],
      nextStep: null,
      findings: const [],
      completedSessionCount: 0,
    );
  }

  final history = _historyByExercise(completed);
  final exercises = [
    for (final entry in history.entries) _classify(entry.key, entry.value),
  ]..sort((a, b) {
      // Most-moved first: judged exercises by |change| desc, then by recency.
      final ca = a.strengthChangePercent?.abs() ?? -1;
      final cb = b.strengthChangePercent?.abs() ?? -1;
      if (ca != cb) return cb.compareTo(ca);
      return b.lastPerformedAt.compareTo(a.lastPerformedAt);
    });

  // ---- Strength over the headline window (recent 6wk vs prior 6wk) --------
  final strengthChanges = <double>[];
  for (final entry in history.entries) {
    final change = _strengthChangeOverWindow(entry.value, now);
    if (change != null) strengthChanges.add(change);
  }
  final overallStrength =
      strengthChanges.isEmpty ? null : _median(strengthChanges);

  // ---- Volume (trailing week vs prior week) -------------------------------
  final thisWeek = _windowVolume(completed, now, kWeekWindowDays, 0);
  final lastWeek =
      _windowVolume(completed, now, kWeekWindowDays * 2, kWeekWindowDays);
  final volume = VolumeSummary(
    thisWeekKg: thisWeek,
    lastWeekKg: lastWeek,
    changePercent: lastWeek <= 0 ? null : (thisWeek - lastWeek) / lastWeek * 100,
  );

  // ---- Muscle rollup ------------------------------------------------------
  final muscles = _muscleRollup(completed, now);

  // ---- PRs (recent) -------------------------------------------------------
  final prMap = personalRecords(completed);
  final cutoff = now.subtract(const Duration(days: kRecentPrWindowDays));
  final recentPrs = <PrRecord>[
    for (final byKind in prMap.values)
      for (final rec in byKind.values)
        if (rec.achievedAt.isAfter(cutoff)) rec,
  ]..sort((a, b) => b.achievedAt.compareTo(a.achievedAt));

  // ---- Improving / needs attention ----------------------------------------
  // Status already encodes the threshold (progressing ⇔ raw ≥ meaningful), so
  // gate on it alone — a big-but-withheld % (null) is still improving.
  final improving = exercises
      .where((e) => e.status == ProgressStatus.progressing)
      .toList(growable: false);
  final needsAttention = exercises
      .where((e) =>
          e.status == ProgressStatus.regressing ||
          e.status == ProgressStatus.plateauing)
      .toList(growable: false);

  // ---- Overall status + summary copy --------------------------------------
  final (overallStatus, headline, detail) = _overall(
    overallStrength: overallStrength,
    recentPrCount: recentPrs.length,
    improving: improving,
    needsAttention: needsAttention,
    now: now,
  );

  // ---- Next step (reuses computeGoal) -------------------------------------
  final nextStep = _nextStep(exercises, history);

  // ---- Findings for the AI ------------------------------------------------
  final findings = _buildFindings(
    overallStatus: overallStatus,
    overallStrength: overallStrength,
    recentPrs: recentPrs,
    improving: improving,
    needsAttention: needsAttention,
    muscles: muscles,
    volume: volume,
  );

  return TrainingAnalysis(
    overallStatus: overallStatus,
    summaryHeadline: headline,
    summaryDetail: detail,
    overallStrengthChangePercent: overallStrength,
    exercises: exercises,
    muscles: muscles,
    volume: volume,
    recentPrs: recentPrs,
    improving: improving,
    needsAttention: needsAttention,
    nextStep: nextStep,
    findings: findings,
    completedSessionCount: completed.length,
  );
}

/// Strength change for one exercise over [kStrengthWindowDays]: best e1RM in
/// the recent window vs best e1RM in the window before it. Null unless both
/// windows carry a reliable estimate.
double? _strengthChangeOverWindow(_ExerciseHistory h, DateTime now) {
  final recentStart = now.subtract(const Duration(days: kStrengthWindowDays));
  final priorStart = now.subtract(const Duration(days: kStrengthWindowDays * 2));
  double? recentBest;
  double? priorBest;
  for (final a in h.appearances) {
    final e = a.bestE1RM;
    if (e == null) continue;
    if (a.date.isAfter(recentStart)) {
      if (recentBest == null || e > recentBest) recentBest = e;
    } else if (a.date.isAfter(priorStart)) {
      if (priorBest == null || e > priorBest) priorBest = e;
    }
  }
  if (recentBest == null || priorBest == null || priorBest == 0) return null;
  return (recentBest - priorBest) / priorBest * 100;
}

List<MuscleGroupProgress> _muscleRollup(
  List<LiveSession> completed,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final weekStart = today.subtract(const Duration(days: kWeekWindowDays));
  final priorStart = today.subtract(const Duration(days: kWeekWindowDays * 2));
  final setsThisWeek = <String, int>{};
  final volThisWeek = <String, double>{};
  final volPriorWeek = <String, double>{};
  for (final session in completed) {
    final at = session.completedAt ?? session.startedAt;
    final day = DateTime(at.year, at.month, at.day);
    final inThisWeek = !day.isBefore(weekStart) && !day.isAfter(today);
    final inPriorWeek = !day.isBefore(priorStart) && day.isBefore(weekStart);
    if (!inThisWeek && !inPriorWeek) continue;
    for (final ex in session.exercises) {
      final muscle = normalizeMuscleGroup(ex.muscleGroup);
      if (muscle == null) continue;
      for (final s in ex.sets) {
        if (!_isWorkingSet(s)) continue;
        final reps = s.actualReps;
        final w = s.actualWeightKg;
        final vol = (reps != null && w != null) ? reps * w : 0.0;
        if (inThisWeek) {
          setsThisWeek[muscle] = (setsThisWeek[muscle] ?? 0) + 1;
          volThisWeek[muscle] = (volThisWeek[muscle] ?? 0) + vol;
        } else {
          volPriorWeek[muscle] = (volPriorWeek[muscle] ?? 0) + vol;
        }
      }
    }
  }
  final muscles = {...setsThisWeek.keys, ...volPriorWeek.keys};
  final out = <MuscleGroupProgress>[];
  for (final m in muscles) {
    final vThis = volThisWeek[m] ?? 0;
    final vPrior = volPriorWeek[m] ?? 0;
    final change = vPrior <= 0 ? null : (vThis - vPrior) / vPrior * 100;
    ProgressStatus status;
    if (change == null) {
      status = ProgressStatus.building;
    } else if (change >= kMeaningfulChangePct) {
      status = ProgressStatus.progressing;
    } else if (change <= -kMuscleVolumeDropPct) {
      status = ProgressStatus.regressing;
    } else {
      status = ProgressStatus.maintaining;
    }
    out.add(MuscleGroupProgress(
      muscle: m,
      weeklyWorkingSets: setsThisWeek[m] ?? 0,
      status: status,
      volumeChangePercent: change,
    ));
  }
  out.sort((a, b) => b.weeklyWorkingSets.compareTo(a.weeklyWorkingSets));
  return out;
}

(ProgressStatus, String, String) _overall({
  required double? overallStrength,
  required int recentPrCount,
  required List<ExercisePerformance> improving,
  required List<ExercisePerformance> needsAttention,
  required DateTime now,
}) {
  final prPart = recentPrCount == 0
      ? ''
      : ', and you\'ve set $recentPrCount new PR${recentPrCount == 1 ? '' : 's'}';

  if (overallStrength != null && overallStrength >= kMeaningfulChangePct) {
    return (
      ProgressStatus.progressing,
      "You're progressing",
      'Your strength is up ${_pct(overallStrength)} over the last 6 weeks$prPart.',
    );
  }
  if (overallStrength != null && overallStrength <= -kMeaningfulChangePct) {
    return (
      ProgressStatus.regressing,
      'Progress may be slowing',
      'Your main lifts are down ${_pct(overallStrength.abs())} over the last 6 weeks — worth easing off or checking recovery.',
    );
  }
  // Flat / not enough strength signal.
  if (recentPrCount > 0) {
    return (
      ProgressStatus.maintaining,
      'Progress is steady',
      'Most of your main lifts are holding, with $recentPrCount new PR${recentPrCount == 1 ? '' : 's'} this month.',
    );
  }
  if (needsAttention.isNotEmpty && improving.isEmpty) {
    return (
      ProgressStatus.plateauing,
      'Progress may be slowing',
      'A few lifts have been flat recently — small changes could get them moving again.',
    );
  }
  return (
    ProgressStatus.maintaining,
    'Progress is steady',
    "You're holding your performance. Keep logging and ZIVO will surface where you're trending.",
  );
}

NextStepRecommendation? _nextStep(
  List<ExercisePerformance> exercises,
  Map<String, _ExerciseHistory> history,
) {
  if (exercises.isEmpty) return null;
  // Prefer a healthy, progressing/maintaining weighted lift to advance; else
  // the most-flagged one to address.
  ExercisePerformance? target;
  for (final e in exercises) {
    if (e.isWeighted &&
        (e.status == ProgressStatus.progressing ||
            e.status == ProgressStatus.maintaining)) {
      target = e;
      break;
    }
  }
  target ??= exercises.firstWhere(
    (e) => e.status == ProgressStatus.plateauing || e.status == ProgressStatus.regressing,
    orElse: () => exercises.first,
  );

  final h = history[target.exerciseId];
  if (h == null || h.appearances.isEmpty) return null;

  // Reuse the live double-progression engine on the last working set to phrase
  // a concrete "next time" — same logic the session goal card uses.
  final text = switch (target.status) {
    ProgressStatus.building =>
      'Keep logging ${target.name} — a couple more sessions and ZIVO can guide the load.',
    ProgressStatus.progressing || ProgressStatus.maintaining =>
      _advanceText(target, h),
    ProgressStatus.plateauing =>
      '${target.name} has been flat for a few sessions. Try a small load bump, or drop the reps slightly and build back up.',
    ProgressStatus.regressing =>
      '${target.name} has trended down lately. Hold the weight and rebuild your reps before adding load — and check your recovery.',
  };
  return NextStepRecommendation(
    exerciseId: target.exerciseId,
    name: target.name,
    text: text,
  );
}

/// Phrases a concrete next target for a healthy lift via [computeGoal] on its
/// last working set.
String _advanceText(ExercisePerformance e, _ExerciseHistory h) {
  final last = h.appearances.last;
  // Reconstruct a representative previous set from the appearance to feed the
  // double-progression engine (its top working set is the meaningful anchor).
  final prevWeight = last.topWeightKg;
  final prevReps = last.bestReps > 0 ? last.bestReps : null;
  final previous = (prevReps == null)
      ? null
      : LoggedSet(
          id: 'analytics-anchor',
          target: const RepTarget.range(6, 8),
          actualReps: prevReps,
          actualWeightKg: prevWeight,
          outcome: _completedOutcome,
        );
  final goal = computeGoal(
    target: const RepTarget.range(6, 8),
    targetWeightKg: prevWeight,
    previous: previous,
    muscleGroup: e.muscleGroup,
  );
  return 'Next time on ${e.name}: aim for ${goal.label}.';
}

List<TrainingFinding> _buildFindings({
  required ProgressStatus overallStatus,
  required double? overallStrength,
  required List<PrRecord> recentPrs,
  required List<ExercisePerformance> improving,
  required List<ExercisePerformance> needsAttention,
  required List<MuscleGroupProgress> muscles,
  required VolumeSummary volume,
}) {
  final out = <TrainingFinding>[];

  if (overallStrength != null) {
    out.add(TrainingFinding(
      kind: FindingKind.observation,
      confidence: FindingConfidence.fact,
      text: overallStrength >= 0
          ? 'Overall estimated strength is up ${_pct(overallStrength)} over the last 6 weeks.'
          : 'Overall estimated strength is down ${_pct(overallStrength.abs())} over the last 6 weeks.',
      evidence: const ['overallStrengthChangePercent'],
    ));
  }

  if (recentPrs.isNotEmpty) {
    final top = recentPrs.first;
    out.add(TrainingFinding(
      kind: FindingKind.encouragement,
      confidence: FindingConfidence.fact,
      text:
          '${recentPrs.length} new PR${recentPrs.length == 1 ? '' : 's'} in the last month — including ${top.name}.',
      evidence: const ['recentPrs'],
    ));
  }

  for (final e in improving.take(2)) {
    final pct = e.strengthChangePercent;
    out.add(TrainingFinding(
      kind: FindingKind.analysis,
      confidence: FindingConfidence.interpretation,
      text: pct == null
          ? '${e.name} is progressing.'
          : '${e.name} is progressing — estimated strength ${_signedPct(pct)}.',
      evidence: const ['exercises'],
    ));
  }

  for (final e in needsAttention.take(2)) {
    final pct = e.strengthChangePercent;
    final line = e.status == ProgressStatus.regressing
        ? (pct == null
            ? '${e.name} has been trending down recently.'
            : '${e.name} has been trending down recently (${_signedPct(pct)}).')
        : '${e.name} has stayed about the same for several sessions.';
    out.add(TrainingFinding(
      kind: FindingKind.warning,
      confidence: FindingConfidence.interpretation,
      text: line,
      evidence: const ['exercises'],
    ));
  }

  final droppedMuscle = muscles.firstWhere(
    (m) => (m.volumeChangePercent ?? 0) <= -kMuscleVolumeDropPct,
    orElse: () => const MuscleGroupProgress(
        muscle: '', weeklyWorkingSets: 0, status: ProgressStatus.building, volumeChangePercent: null),
  );
  if (droppedMuscle.muscle.isNotEmpty) {
    out.add(TrainingFinding(
      kind: FindingKind.observation,
      confidence: FindingConfidence.fact,
      text:
          '${droppedMuscle.muscle} working volume is down ${_pct((droppedMuscle.volumeChangePercent ?? 0).abs())} vs last week.',
      evidence: const ['muscles'],
    ));
  }

  if (volume.changePercent != null && volume.changePercent!.abs() >= kMeaningfulChangePct) {
    out.add(TrainingFinding(
      kind: FindingKind.observation,
      confidence: FindingConfidence.fact,
      text: 'Weekly working volume is ${_signedPct(volume.changePercent!)} vs last week.',
      evidence: const ['volume'],
    ));
  }

  return out;
}

// ---- Formatting helpers ---------------------------------------------------

String _pct(double v) => '${v.round()}%';
String _signedPct(double v) => '${v > 0 ? '+' : ''}${v.round()}%';

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

const SetOutcome _completedOutcome = SetOutcome.completed;
