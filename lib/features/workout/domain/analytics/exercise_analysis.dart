/// ZIVO's deep, per-exercise analysis — the drill-down layer beneath the
/// centralized [analyzeTraining] hub engine (`workout_analytics.dart`).
///
/// Where the hub answers "how is my training going" across every lift, this
/// answers "what exactly happened to THIS lift, session by session, and what
/// should I do about it" — the view a coach opens on one movement. It is a
/// pure function of a user's [LiveSession] history plus `now`: it reads no
/// clock and no repository, so it is deterministic and unit-testable, and it
/// deliberately REUSES the hub engine's primitives ([analyzeTraining],
/// [estimatedOneRepMax], [isWorkingSet], [computeGoal]) rather than re-deriving
/// them — so the direction the hub shows for an exercise and the direction its
/// detail page shows can never disagree.
///
/// The coaching stance, encoded in [_toneFor], is the important part: progress
/// is judged **intensity-first (estimated 1RM), not volume-first**. A heavier
/// load for fewer reps (40kg × 7 vs 35kg × 10) can be a real step forward even
/// though the rep count fell — because e1RM captures the load/rep trade-off
/// that raw tonnage misses. Volume is a secondary signal, only decisive when
/// strength is flat. Every conclusion here is computed from the numbers; the
/// prose in [CoachingInsight] is templated FROM those numbers (what happened →
/// why it matters → what to do), so the AI coach can later re-voice it without
/// ever inventing the underlying facts (product brief §4–5).
library;

import '../live_session.dart';
import '../logged_set.dart';
import '../planned_exercise.dart';
import '../progression.dart';
import '../rep_target.dart';
import '../session_status.dart';
import '../set_outcome.dart';
import '../set_type.dart';
import 'workout_analytics.dart';

/// Floating-point slack for load / e1RM equality (mirrors the hub engine's).
const double _eps = 0.0001;

/// How long an exercise can go untrained before the detail page notes the gap
/// in its coaching copy. Distinct from the plan-adherence "stale" threshold —
/// this is just the wording nudge on a lift you're still tracking.
const int kQuietExerciseDays = 14;

// ---- Value types ----------------------------------------------------------

/// One performed working set, reduced to the numbers the timeline and the
/// comparison reason over. Warm-ups are excluded upstream, so every
/// [PerformedSet] is training volume.
class PerformedSet {
  const PerformedSet({
    required this.reps,
    required this.weightKg,
    required this.e1rm,
    required this.type,
    required this.isTopSet,
  });

  final int? reps;
  final double? weightKg;

  /// Epley estimate for this set (null when unloaded or reps are unreliable).
  final double? e1rm;
  final SetType type;

  /// Whether this set carried the session's heaviest working load — the
  /// "top set" the intensity comparison anchors on.
  final bool isTopSet;

  /// reps × weight, or null when either is missing.
  double? get volumeKg =>
      (reps != null && weightKg != null) ? reps! * weightKg! : null;
}

/// Everything one completed session did for a single exercise — the working
/// sets plus the reductions a coach reads at a glance. Immutable; the derived
/// getters are the "performance metrics" the brief asks each session to show.
class ExerciseSessionRecord {
  const ExerciseSessionRecord({
    required this.sessionId,
    required this.date,
    required this.dayLabel,
    required this.sets,
    required this.isPrSession,
  });

  final String sessionId;

  /// When the session finished ([LiveSession.completedAt] ?? `startedAt`).
  final DateTime date;
  final String dayLabel;

  /// Working sets only, in the order performed.
  final List<PerformedSet> sets;

  /// Whether this session set at least one new all-time best (heaviest load,
  /// most reps, or best e1RM) for the exercise, relative to everything before
  /// it — the first appearance is a baseline, never a PR.
  final bool isPrSession;

  int get workingSetCount => sets.length;

  /// Σ reps over working sets.
  int get totalReps => sets.fold(0, (n, s) => n + (s.reps ?? 0));

  /// Σ reps × weight over working sets (the session's tonnage for this lift).
  double get totalVolumeKg {
    var v = 0.0;
    for (final s in sets) {
      v += s.volumeKg ?? 0;
    }
    return v;
  }

  /// Heaviest working load this session (null for an unloaded movement).
  double? get topWeightKg {
    double? top;
    for (final s in sets) {
      final w = s.weightKg;
      if (w != null && (top == null || w > top)) top = w;
    }
    return top;
  }

  /// Most reps on any single working set.
  int get topReps {
    var best = 0;
    for (final s in sets) {
      final r = s.reps;
      if (r != null && r > best) best = r;
    }
    return best;
  }

  /// Best estimated 1RM across the session's working sets — the session's
  /// intensity, robust to which set happened to be heaviest.
  double? get bestE1RM {
    double? best;
    for (final s in sets) {
      final e = s.e1rm;
      if (e != null && (best == null || e > best)) best = e;
    }
    return best;
  }

  /// Rep-weighted average load — total volume ÷ reps, over sets that carried a
  /// load. A single "how heavy did this session run" number that isn't thrown
  /// off by one light back-off set. Null when nothing was loaded.
  double? get avgLoadKg {
    var vol = 0.0;
    var reps = 0;
    for (final s in sets) {
      if (s.reps != null && s.weightKg != null) {
        vol += s.reps! * s.weightKg!;
        reps += s.reps!;
      }
    }
    return reps == 0 ? null : vol / reps;
  }

  /// The min–max rep span across working sets (null when no set logged reps).
  (int min, int max)? get repRange {
    int? lo;
    int? hi;
    for (final s in sets) {
      final r = s.reps;
      if (r == null) continue;
      if (lo == null || r < lo) lo = r;
      if (hi == null || r > hi) hi = r;
    }
    return (lo == null) ? null : (lo, hi!);
  }
}

/// The plain-language verdict of one session versus the one before it.
enum ExerciseTrendTone { improved, maintained, declined, mixed }

/// A single typed, measured change between two consecutive sessions — each a
/// FACT read straight off the numbers. The UI renders the arrow + word; the AI
/// phrases the sentence. Ordered by how a coach reads them (PR first, then the
/// strength signal, then the mechanics that produced it).
enum SessionChange {
  newPr,
  strengthUp,
  strengthDown,
  loadUp,
  loadDown,
  repsUp,
  repsDown,
  volumeUp,
  volumeDown,
  noChange,
}

/// The measured comparison of one session ([current]) against the previous one
/// ([previous]) for a single exercise — the "here's exactly what changed" the
/// brief asks for, computed from records, never narrated by an LLM.
class SessionComparison {
  const SessionComparison({
    required this.previous,
    required this.current,
    required this.loadChangeKg,
    required this.loadChangePercent,
    required this.topRepsChange,
    required this.totalRepsChange,
    required this.volumeChangeKg,
    required this.volumeChangePercent,
    required this.e1rmChangeKg,
    required this.e1rmChangePercent,
    required this.tags,
    required this.tone,
  });

  final ExerciseSessionRecord previous;
  final ExerciseSessionRecord current;

  /// Top-set load delta (current − previous), null unless both were loaded.
  final double? loadChangeKg;
  final double? loadChangePercent;

  /// Best-single-set rep delta, and total-reps delta across the session.
  final int topRepsChange;
  final int totalRepsChange;

  final double volumeChangeKg;

  /// Volume % change, null when the previous session had no volume.
  final double? volumeChangePercent;

  /// Best-e1RM delta, null unless both sessions carry a reliable estimate.
  final double? e1rmChangeKg;
  final double? e1rmChangePercent;

  /// The measured change flags, most salient first ([SessionChange] order).
  final List<SessionChange> tags;
  final ExerciseTrendTone tone;
}

/// The three-part coaching read the brief demands for every insight: what
/// happened (the data), why it matters (the interpretation), and what to do
/// (the practical step). Generated deterministically from the analysis so it
/// is always traceable to the numbers; the AI can re-voice the strings.
class CoachingInsight {
  const CoachingInsight({
    required this.tone,
    required this.whatHappened,
    required this.whyItMatters,
    required this.whatToDo,
  });

  final ProgressStatus tone;
  final String whatHappened;
  final String whyItMatters;
  final String whatToDo;
}

/// The whole picture for one exercise — the single object the detail page
/// renders. [sessions] and the two series run oldest→newest; [comparisons]
/// has one entry per adjacent pair ([comparisons][i] compares [sessions][i] to
/// [sessions][i+1]).
class ExerciseAnalysis {
  const ExerciseAnalysis({
    required this.exerciseId,
    required this.name,
    required this.muscleGroup,
    required this.status,
    required this.strengthChangePercent,
    required this.currentE1RM,
    required this.bestE1RM,
    required this.sessions,
    required this.comparisons,
    required this.records,
    required this.daysSinceLast,
    required this.sessionsPerWeek,
    required this.e1rmSeries,
    required this.volumeSeries,
    required this.nextStep,
    required this.insight,
  });

  final String exerciseId;
  final String name;
  final String? muscleGroup;

  /// The SAME direction the hub shows for this exercise (from [analyzeTraining]).
  final ProgressStatus status;
  final double? strengthChangePercent;

  /// Most-recent working e1RM, and the all-time best working e1RM.
  final double? currentE1RM;
  final double? bestE1RM;

  final List<ExerciseSessionRecord> sessions;
  final List<SessionComparison> comparisons;

  /// This exercise's all-time PRs by kind (derived from history, no ledger).
  final Map<PrKind, PrRecord> records;

  final int daysSinceLast;

  /// Completed sessions per week over the tracked span (null under 2 sessions).
  final double? sessionsPerWeek;

  final List<double?> e1rmSeries;
  final List<double?> volumeSeries;

  /// A concrete "next time, aim for …" via [computeGoal] (null when unweighted
  /// with no rep history to progress).
  final NextStepRecommendation? nextStep;

  final CoachingInsight insight;

  int get totalSessions => sessions.length;
  int get totalWorkingSets =>
      sessions.fold(0, (n, s) => n + s.workingSetCount);
  double get totalVolumeKg =>
      sessions.fold(0.0, (v, s) => v + s.totalVolumeKg);

  ExerciseSessionRecord get latest => sessions.last;
  SessionComparison? get latestComparison =>
      comparisons.isEmpty ? null : comparisons.last;

  /// Whether the movement is loaded (drives e1RM-first vs reps-first reads).
  bool get isWeighted =>
      currentE1RM != null || sessions.any((s) => s.topWeightKg != null);
}

// ---- The engine -----------------------------------------------------------

/// Reduces one session's working sets for [exerciseId] into an
/// [ExerciseSessionRecord] (folding a movement that appears more than once in
/// the session), or null when it had no working set for that exercise.
/// [isPrSession] is decided by the caller, which alone sees prior history.
ExerciseSessionRecord? _recordFor(
  LiveSession session,
  String exerciseId, {
  required bool isPrSession,
}) {
  final raw = <LoggedSet>[];
  for (final e in session.exercises) {
    if (e.exerciseId == exerciseId) raw.addAll(e.sets);
  }
  final working = raw.where(isWorkingSet).toList(growable: false);
  if (working.isEmpty) return null;

  double? top;
  for (final s in working) {
    final w = s.actualWeightKg;
    if (w != null && (top == null || w > top)) top = w;
  }

  final sets = <PerformedSet>[];
  for (final s in working) {
    final w = s.actualWeightKg;
    sets.add(PerformedSet(
      reps: s.actualReps,
      weightKg: w,
      e1rm: estimatedOneRepMax(w, s.actualReps),
      type: s.type,
      isTopSet: w != null && top != null && (w - top).abs() < _eps,
    ));
  }

  return ExerciseSessionRecord(
    sessionId: session.id,
    date: session.completedAt ?? session.startedAt,
    dayLabel: session.dayLabel,
    sets: sets,
    isPrSession: isPrSession,
  );
}

/// The one public entry point. Builds a full [ExerciseAnalysis] for
/// [exerciseId] from every known session (any status; it filters to
/// completed), or null when the exercise has no completed working history.
/// [planned] is the matching plan exercise if the caller has it — used only to
/// enrich the next-step target; the analysis stands without it.
ExerciseAnalysis? analyzeExercise({
  required String exerciseId,
  required List<LiveSession> sessions,
  required DateTime now,
  PlannedExercise? planned,
}) {
  final completed = sessions
      .where((s) => s.status == SessionStatus.completed)
      .toList(growable: false)
    ..sort((a, b) => (a.completedAt ?? a.startedAt)
        .compareTo(b.completedAt ?? b.startedAt));

  // Walk oldest→newest, tracking running bests so each session can be flagged
  // as PR-setting exactly the way the hub's detectNewPrs would (first
  // appearance is a baseline, not a celebrated PR).
  final records = <ExerciseSessionRecord>[];
  double? runBestWeight;
  double? runBestE1rm;
  int? runBestReps;
  var seenAny = false;
  String? name;
  String? muscle;

  for (final session in completed) {
    // Peek the working reduction first (without PR flag) to test the bests.
    final peek = _recordFor(session, exerciseId, isPrSession: false);
    if (peek == null) continue;

    final w = peek.topWeightKg;
    final e = peek.bestE1RM;
    final r = peek.topReps;
    final beatsWeight = w != null && (runBestWeight == null || w > runBestWeight + _eps);
    final beatsE1rm = e != null && (runBestE1rm == null || e > runBestE1rm + _eps);
    final beatsReps = r > 0 && (runBestReps == null || r > runBestReps);
    final isPr = seenAny && (beatsWeight || beatsE1rm || beatsReps);

    records.add(_recordFor(session, exerciseId, isPrSession: isPr)!);

    if (w != null && (runBestWeight == null || w > runBestWeight)) runBestWeight = w;
    if (e != null && (runBestE1rm == null || e > runBestE1rm)) runBestE1rm = e;
    if (r > 0 && (runBestReps == null || r > runBestReps)) runBestReps = r;
    seenAny = true;

    // Freshest name / muscle come from the most recent session carrying them.
    for (final ex in session.exercises) {
      if (ex.exerciseId == exerciseId) {
        name = ex.name;
        muscle = ex.muscleGroup;
      }
    }
  }

  if (records.isEmpty) return null;

  // Reuse the hub engine for the direction + windowed strength change, so the
  // detail page and the hub row read identically.
  final hub = analyzeTraining(sessions: sessions, now: now);
  ExercisePerformance? perf;
  for (final e in hub.exercises) {
    if (e.exerciseId == exerciseId) {
      perf = e;
      break;
    }
  }
  final status = perf?.status ?? ProgressStatus.building;

  // All-time PRs for this exercise (single-exercise slice of the hub engine).
  final prMap = personalRecords(completed)[exerciseId] ?? const <PrKind, PrRecord>{};

  // Consecutive comparisons.
  final comparisons = <SessionComparison>[];
  for (var i = 1; i < records.length; i++) {
    comparisons.add(_compare(records[i - 1], records[i]));
  }

  // Series, oldest→newest (null slots preserved for the sparkline).
  final e1rmSeries = [for (final r in records) r.bestE1RM];
  final volumeSeries = [for (final r in records) r.totalVolumeKg];

  final latest = records.last;
  final daysSinceLast = _daysBetween(latest.date, now);
  final sessionsPerWeek = _frequency(records, now);

  final nextStep = _nextStep(
    exerciseId: exerciseId,
    name: name ?? exerciseId,
    status: status,
    muscleGroup: muscle,
    latest: latest,
    planned: planned,
  );

  final insight = _buildInsight(
    name: name ?? exerciseId,
    status: status,
    strengthChangePercent: perf?.strengthChangePercent,
    latest: latest,
    latestComparison: comparisons.isEmpty ? null : comparisons.last,
    records: prMap,
    isWeighted: perf?.isWeighted ?? records.any((r) => r.topWeightKg != null),
    totalSessions: records.length,
    daysSinceLast: daysSinceLast,
    nextStep: nextStep,
  );

  return ExerciseAnalysis(
    exerciseId: exerciseId,
    name: name ?? exerciseId,
    muscleGroup: muscle,
    status: status,
    strengthChangePercent: perf?.strengthChangePercent,
    currentE1RM: latest.bestE1RM,
    bestE1RM: runBestE1rm,
    sessions: records,
    comparisons: comparisons,
    records: prMap,
    daysSinceLast: daysSinceLast,
    sessionsPerWeek: sessionsPerWeek,
    e1rmSeries: e1rmSeries,
    volumeSeries: volumeSeries,
    nextStep: nextStep,
    insight: insight,
  );
}

/// Measures [current] against [previous] — the deltas plus the typed change
/// flags and the intensity-first verdict.
SessionComparison _compare(
  ExerciseSessionRecord previous,
  ExerciseSessionRecord current,
) {
  final pW = previous.topWeightKg;
  final cW = current.topWeightKg;
  final loadChangeKg = (pW != null && cW != null) ? cW - pW : null;
  final loadChangePercent =
      (pW != null && pW > 0 && cW != null) ? (cW - pW) / pW * 100 : null;

  final topRepsChange = current.topReps - previous.topReps;
  final totalRepsChange = current.totalReps - previous.totalReps;

  final volumeChangeKg = current.totalVolumeKg - previous.totalVolumeKg;
  final volumeChangePercent = previous.totalVolumeKg > 0
      ? (current.totalVolumeKg - previous.totalVolumeKg) /
          previous.totalVolumeKg *
          100
      : null;

  final pE = previous.bestE1RM;
  final cE = current.bestE1RM;
  final e1rmChangeKg = (pE != null && cE != null) ? cE - pE : null;
  final e1rmChangePercent =
      (pE != null && pE > 0 && cE != null) ? (cE - pE) / pE * 100 : null;

  final weighted = pW != null || cW != null;
  final tone = _toneFor(
    e1rmChangePercent: e1rmChangePercent,
    volumeChangePercent: volumeChangePercent,
    topRepsChange: topRepsChange,
    weighted: weighted,
  );

  final tags = _tagsFor(
    isPr: current.isPrSession,
    weighted: weighted,
    e1rmChangePercent: e1rmChangePercent,
    loadChangeKg: loadChangeKg,
    topRepsChange: topRepsChange,
    volumeChangePercent: volumeChangePercent,
  );

  return SessionComparison(
    previous: previous,
    current: current,
    loadChangeKg: loadChangeKg,
    loadChangePercent: loadChangePercent,
    topRepsChange: topRepsChange,
    totalRepsChange: totalRepsChange,
    volumeChangeKg: volumeChangeKg,
    volumeChangePercent: volumeChangePercent,
    e1rmChangeKg: e1rmChangeKg,
    e1rmChangePercent: e1rmChangePercent,
    tags: tags,
    tone: tone,
  );
}

/// The coaching verdict for one session-to-session step. Intensity-first:
/// estimated 1RM decides when it moved meaningfully; only when strength is
/// flat does volume break the tie. Strength and volume pointing in opposite
/// meaningful directions is [ExerciseTrendTone.mixed] — the honest read of a
/// heavier-but-shorter or lighter-but-longer session.
ExerciseTrendTone _toneFor({
  required double? e1rmChangePercent,
  required double? volumeChangePercent,
  required int topRepsChange,
  required bool weighted,
}) {
  const t = kMeaningfulChangePct;
  final v = volumeChangePercent ?? 0;

  if (weighted && e1rmChangePercent != null) {
    final e = e1rmChangePercent;
    final sUp = e >= t, sDown = e <= -t;
    final vUp = v >= t, vDown = v <= -t;
    if (sUp && vDown) return ExerciseTrendTone.mixed;
    if (sDown && vUp) return ExerciseTrendTone.mixed;
    if (sUp) return ExerciseTrendTone.improved;
    if (sDown) return ExerciseTrendTone.declined;
    // Strength flat → volume is the secondary signal.
    if (vUp) return ExerciseTrendTone.improved;
    return ExerciseTrendTone.maintained;
  }

  // Unloaded / bodyweight → reps + volume.
  final vUp = v >= t, vDown = v <= -t;
  if (vUp || (topRepsChange > 0 && !vDown)) return ExerciseTrendTone.improved;
  if (vDown || topRepsChange < 0) return ExerciseTrendTone.declined;
  return ExerciseTrendTone.maintained;
}

List<SessionChange> _tagsFor({
  required bool isPr,
  required bool weighted,
  required double? e1rmChangePercent,
  required double? loadChangeKg,
  required int topRepsChange,
  required double? volumeChangePercent,
}) {
  const t = kMeaningfulChangePct;
  final out = <SessionChange>[];
  if (isPr) out.add(SessionChange.newPr);
  if (weighted && e1rmChangePercent != null) {
    if (e1rmChangePercent >= t) {
      out.add(SessionChange.strengthUp);
    } else if (e1rmChangePercent <= -t) {
      out.add(SessionChange.strengthDown);
    }
  }
  if (loadChangeKg != null) {
    if (loadChangeKg > _eps) {
      out.add(SessionChange.loadUp);
    } else if (loadChangeKg < -_eps) {
      out.add(SessionChange.loadDown);
    }
  }
  if (topRepsChange > 0) {
    out.add(SessionChange.repsUp);
  } else if (topRepsChange < 0) {
    out.add(SessionChange.repsDown);
  }
  if (volumeChangePercent != null) {
    if (volumeChangePercent >= t) {
      out.add(SessionChange.volumeUp);
    } else if (volumeChangePercent <= -t) {
      out.add(SessionChange.volumeDown);
    }
  }
  if (out.isEmpty) out.add(SessionChange.noChange);
  return out;
}

/// A concrete next-session target via the live [computeGoal] double-
/// progression engine on the latest session's top working set — the same
/// logic the live goal card uses, so guidance is consistent everywhere.
NextStepRecommendation? _nextStep({
  required String exerciseId,
  required String name,
  required ProgressStatus status,
  required String? muscleGroup,
  required ExerciseSessionRecord latest,
  required PlannedExercise? planned,
}) {
  if (status == ProgressStatus.building) {
    return NextStepRecommendation(
      exerciseId: exerciseId,
      name: name,
      text:
          'Keep logging $name — a couple more sessions and ZIVO can guide the load.',
    );
  }

  final prevWeight = latest.topWeightKg;
  final prevReps = latest.topReps > 0 ? latest.topReps : null;
  // The rep target the plan prescribes for this movement, if any — else a
  // sensible hypertrophy range so double-progression still has a top to hit.
  final target = _planTarget(planned) ?? const RepTarget.range(6, 8);
  final previous = prevReps == null
      ? null
      : LoggedSet(
          id: 'exercise-analysis-anchor',
          target: target,
          actualReps: prevReps,
          actualWeightKg: prevWeight,
          outcome: SetOutcome.completed,
        );
  final goal = computeGoal(
    target: target,
    targetWeightKg: prevWeight ?? _planWeight(planned),
    previous: previous,
    muscleGroup: muscleGroup,
  );

  final text = switch (status) {
    ProgressStatus.regressing =>
      '$name has trended down. Hold ${_kgOr(prevWeight, 'the weight')} and rebuild your reps before adding load — and check recovery.',
    ProgressStatus.plateauing =>
      "$name has been flat. Break the plateau: aim for ${goal.label}, or drop the load ~10% and build back up.",
    _ => 'Next time on $name: aim for ${goal.label}.',
  };
  return NextStepRecommendation(exerciseId: exerciseId, name: name, text: text);
}

/// The three-part coaching insight, grounded in the numbers. Leads with the
/// most recent measured change when there is one, and never claims anything
/// about the body — only about the training data (brief §4).
CoachingInsight _buildInsight({
  required String name,
  required ProgressStatus status,
  required double? strengthChangePercent,
  required ExerciseSessionRecord latest,
  required SessionComparison? latestComparison,
  required Map<PrKind, PrRecord> records,
  required bool isWeighted,
  required int totalSessions,
  required int daysSinceLast,
  required NextStepRecommendation? nextStep,
}) {
  final changed = latestComparison == null
      ? null
      : _describeChange(latestComparison, isWeighted: isWeighted);
  final quiet = daysSinceLast >= kQuietExerciseDays
      ? ' It has been $daysSinceLast days since you last trained it.'
      : '';
  final doStep = nextStep?.text ?? 'Keep logging $name to unlock guidance.';

  switch (status) {
    case ProgressStatus.building:
      // Too little history for a windowed direction — but a single measured
      // step is still a fact worth showing. Lead with it when there is one.
      final promising = latestComparison != null &&
          latestComparison.tone == ExerciseTrendTone.improved;
      return CoachingInsight(
        tone: status,
        whatHappened: changed ??
            "You've logged $name ${_sessionsWord(totalSessions)} so far.$quiet",
        whyItMatters: latestComparison == null
            ? 'Not enough history yet to call a direction — a couple more sessions and the trend becomes real.'
            : '${promising ? 'Encouraging' : 'Noted'}, but it’s only ${_sessionsWord(totalSessions)} — one or two more and ZIVO can confirm the trend rather than a single step.',
        whatToDo: doStep,
      );
    case ProgressStatus.progressing:
      return CoachingInsight(
        tone: status,
        whatHappened: changed ??
            '$name is trending up across your recent sessions.$quiet',
        whyItMatters: isWeighted
            ? 'Estimated 1RM is ${_signed(strengthChangePercent)} — real strength gain, not just extra volume. The heavier load is paying for any drop in reps.'
            : 'You’re doing more work at this movement — reps and volume are climbing.',
        whatToDo: doStep,
      );
    case ProgressStatus.maintaining:
      return CoachingInsight(
        tone: status,
        whatHappened: changed ??
            '$name has held about steady over your last few sessions.$quiet',
        whyItMatters:
            'Strength is stable — you’re holding, not building. Left alone it will stay here.',
        whatToDo: doStep,
      );
    case ProgressStatus.plateauing:
      return CoachingInsight(
        tone: status,
        whatHappened:
            '$name hasn’t moved meaningfully in several sessions.$quiet',
        whyItMatters:
            'A plateau this long usually means the current load and rep scheme have been fully adapted to.',
        whatToDo: doStep,
      );
    case ProgressStatus.regressing:
      return CoachingInsight(
        tone: status,
        whatHappened: changed ??
            '$name has trended down recently${strengthChangePercent == null ? '' : ' (${_signed(strengthChangePercent)} estimated strength)'}.$quiet',
        whyItMatters:
            'A short-term dip is often fatigue or recovery rather than lost strength — but worth acting on before it settles in.',
        whatToDo: doStep,
      );
  }
}

/// "load rose 35 → 40kg while top reps eased 10 → 7" — a plain description of
/// the latest measured step, built from the comparison so the copy always
/// matches the arrows the timeline shows.
String _describeChange(SessionComparison c, {required bool isWeighted}) {
  final parts = <String>[];
  final pW = c.previous.topWeightKg;
  final cW = c.current.topWeightKg;
  if (pW != null && cW != null && (cW - pW).abs() > _eps) {
    final dir = cW > pW ? 'rose' : 'eased';
    parts.add('working load $dir ${_kg(pW)} → ${_kg(cW)}kg');
  }
  final pr = c.previous.topReps;
  final cr = c.current.topReps;
  if (pr != cr && pr > 0 && cr > 0) {
    final dir = cr > pr ? 'up' : 'down';
    parts.add('top reps $dir $pr → $cr');
  }
  if (parts.isEmpty) {
    final v = c.volumeChangePercent;
    if (v != null && v.abs() >= kMeaningfulChangePct) {
      parts.add('working volume ${_signed(v)}');
    }
  }
  if (parts.isEmpty) return 'Little changed versus your previous session.';
  return 'Since last time, ${_join(parts)}.';
}

// ---- Small helpers --------------------------------------------------------

RepTarget? _planTarget(PlannedExercise? p) {
  if (p == null) return null;
  for (final s in p.sets) {
    if (s.type == SetType.working) return s.repTarget;
  }
  return p.sets.isNotEmpty ? p.sets.first.repTarget : null;
}

double? _planWeight(PlannedExercise? p) {
  if (p == null) return null;
  for (final s in p.sets) {
    if (s.type == SetType.working && s.targetWeightKg != null) {
      return s.targetWeightKg;
    }
  }
  return null;
}

int _daysBetween(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Completed sessions per week across the tracked span; null under 2 sessions
/// (a rate needs a gap) or a zero span.
double? _frequency(List<ExerciseSessionRecord> records, DateTime now) {
  if (records.length < 2) return null;
  final spanDays = _daysBetween(records.first.date, records.last.date);
  if (spanDays <= 0) return null;
  return records.length / (spanDays / 7.0);
}

String _kg(double v) =>
    v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _kgOr(double? v, String fallback) => v == null ? fallback : '${_kg(v)}kg';

String _signed(double? pct) =>
    pct == null ? '—' : '${pct > 0 ? '+' : ''}${pct.round()}%';

String _sessionsWord(int n) => n == 1 ? '1 session' : '$n sessions';

String _join(List<String> parts) {
  if (parts.length == 1) return parts.first;
  if (parts.length == 2) return '${parts[0]} while ${parts[1]}';
  return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
}
