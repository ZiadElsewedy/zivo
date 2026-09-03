/**
 * The server's mirror of the per-exercise drill-down engines:
 *   - `lib/features/workout/domain/analytics/exercise_analysis.dart`
 *   - `lib/features/workout/domain/analytics/plan_adherence.dart`
 *
 * This is the deep layer BENEATH `workout_analytics.js` (the hub engine). It
 * turns one exercise's `workoutSessions` history into the same structured
 * coaching context the app's Exercise Analysis screen shows — session-by-
 * session records, session-to-session deltas, an intensity-first verdict, PRs,
 * frequency — and joins the active plan against history to see what's being
 * skipped. **The model never computes any of this; it explains it.**
 *
 * A deliberate transliteration of the Dart engines, reusing the hub mirror's
 * primitives (`analyzeTraining`, `estimatedOneRepMax`, `isWorkingSet`,
 * `personalRecords`, `completedAtOf`) so the app screen and the coach can never
 * disagree about whether a lift improved. The numeric facts + the verdict/tags
 * enums are pinned cross-engine by the shared golden-vectors fixture
 * (both suites run it); the human-readable insight prose is generated per side
 * from those same facts and is intentionally NOT pinned (same convention the
 * hub's `findings`/`nextStep` prose follows).
 *
 * Pure and store-seamed: no SDK imports, runs offline under `node --test`.
 */

const {
  analyzeTraining,
  estimatedOneRepMax,
  isWorkingSet,
  personalRecords,
  completedAtOf,
  MEANINGFUL_CHANGE_PCT,
  EPS,
} = require("./workout_analytics");

const DAY_MS = 24 * 60 * 60 * 1000;

/** A planned movement goes "stale" after this long without a working set. */
const STALE_PLANNED_EXERCISE_DAYS = 14;

/** The detail view notes the gap in its copy past this many quiet days. */
const QUIET_EXERCISE_DAYS = 14;

// ---- Per-session reduction ------------------------------------------------

/**
 * Reduces one session's working sets for `exerciseId` into a record with the
 * coach metrics, or null when it had no working set for that exercise. The PR
 * flag is decided by the caller, which alone sees prior history.
 * @param {!Object} session
 * @param {string} exerciseId
 * @param {boolean} isPrSession
 * @return {?Object}
 */
function reduceRecord(session, exerciseId, isPrSession) {
  const raw = [];
  for (const e of session.exercises || []) {
    if (e.exerciseId === exerciseId) {
      for (const s of e.sets || []) raw.push(s);
    }
  }
  const working = raw.filter(isWorkingSet);
  if (working.length === 0) return null;

  let top = null;
  for (const s of working) {
    const w = s.actualWeightKg;
    if (w != null && (top == null || w > top)) top = w;
  }

  const sets = working.map((s) => {
    const w = s.actualWeightKg;
    return {
      reps: s.actualReps,
      weightKg: w,
      e1rm: estimatedOneRepMax(w, s.actualReps),
      type: s.type || "working",
      isTopSet: w != null && top != null && Math.abs(w - top) < EPS,
      volumeKg: (s.actualReps != null && w != null) ? s.actualReps * w : null,
    };
  });

  let totalReps = 0;
  let totalVolumeKg = 0;
  let topReps = 0;
  let bestE1RM = null;
  let loadedVol = 0;
  let loadedReps = 0;
  let repLo = null;
  let repHi = null;
  for (const s of sets) {
    if (s.reps != null) totalReps += s.reps;
    if (s.volumeKg != null) totalVolumeKg += s.volumeKg;
    if (s.reps != null && s.reps > topReps) topReps = s.reps;
    if (s.e1rm != null && (bestE1RM == null || s.e1rm > bestE1RM)) {
      bestE1RM = s.e1rm;
    }
    if (s.reps != null && s.weightKg != null) {
      loadedVol += s.reps * s.weightKg;
      loadedReps += s.reps;
    }
    if (s.reps != null) {
      if (repLo == null || s.reps < repLo) repLo = s.reps;
      if (repHi == null || s.reps > repHi) repHi = s.reps;
    }
  }

  return {
    sessionId: session.id,
    date: completedAtOf(session),
    dayLabel: session.dayLabel || "",
    sets,
    isPrSession,
    workingSetCount: sets.length,
    totalReps,
    totalVolumeKg,
    topWeightKg: top,
    topReps,
    bestE1RM,
    avgLoadKg: loadedReps === 0 ? null : loadedVol / loadedReps,
    repRange: repLo == null ? null : {min: repLo, max: repHi},
  };
}

// ---- Verdict + tags (intensity-first) -------------------------------------

/**
 * The coaching verdict for one session-to-session step. Estimated 1RM leads;
 * volume only breaks a tie when strength is flat; strength and volume pointing
 * opposite ways is "mixed". Mirrors the Dart `_toneFor`.
 * @param {?number} e1rmChangePercent
 * @param {?number} volumeChangePercent
 * @param {number} topRepsChange
 * @param {boolean} weighted
 * @return {string}
 */
function toneFor(e1rmChangePercent, volumeChangePercent, topRepsChange,
    weighted) {
  const t = MEANINGFUL_CHANGE_PCT;
  const v = volumeChangePercent == null ? 0 : volumeChangePercent;
  if (weighted && e1rmChangePercent != null) {
    const e = e1rmChangePercent;
    const sUp = e >= t; const sDown = e <= -t;
    const vUp = v >= t; const vDown = v <= -t;
    if (sUp && vDown) return "mixed";
    if (sDown && vUp) return "mixed";
    if (sUp) return "improved";
    if (sDown) return "declined";
    if (vUp) return "improved";
    return "maintained";
  }
  const vUp = v >= t; const vDown = v <= -t;
  if (vUp || (topRepsChange > 0 && !vDown)) return "improved";
  if (vDown || topRepsChange < 0) return "declined";
  return "maintained";
}

/**
 * The ordered, typed change flags for a comparison. Mirrors `_tagsFor`.
 * @param {!Object} args
 * @return {!Array<string>}
 */
function tagsFor({isPr, weighted, e1rmChangePercent, loadChangeKg,
  topRepsChange, volumeChangePercent}) {
  const t = MEANINGFUL_CHANGE_PCT;
  const out = [];
  if (isPr) out.push("newPr");
  if (weighted && e1rmChangePercent != null) {
    if (e1rmChangePercent >= t) out.push("strengthUp");
    else if (e1rmChangePercent <= -t) out.push("strengthDown");
  }
  if (loadChangeKg != null) {
    if (loadChangeKg > EPS) out.push("loadUp");
    else if (loadChangeKg < -EPS) out.push("loadDown");
  }
  if (topRepsChange > 0) out.push("repsUp");
  else if (topRepsChange < 0) out.push("repsDown");
  if (volumeChangePercent != null) {
    if (volumeChangePercent >= t) out.push("volumeUp");
    else if (volumeChangePercent <= -t) out.push("volumeDown");
  }
  if (out.length === 0) out.push("noChange");
  return out;
}

/**
 * Measures `current` against `previous`. Mirrors the Dart `_compare`.
 * @param {!Object} previous
 * @param {!Object} current
 * @return {!Object}
 */
function compare(previous, current) {
  const pW = previous.topWeightKg;
  const cW = current.topWeightKg;
  const loadChangeKg = (pW != null && cW != null) ? cW - pW : null;
  const loadChangePercent =
    (pW != null && pW > 0 && cW != null) ? (cW - pW) / pW * 100 : null;

  const topRepsChange = current.topReps - previous.topReps;
  const totalRepsChange = current.totalReps - previous.totalReps;

  const volumeChangeKg = current.totalVolumeKg - previous.totalVolumeKg;
  const volumeChangePercent = previous.totalVolumeKg > 0 ?
    (current.totalVolumeKg - previous.totalVolumeKg) /
      previous.totalVolumeKg * 100 : null;

  const pE = previous.bestE1RM;
  const cE = current.bestE1RM;
  const e1rmChangeKg = (pE != null && cE != null) ? cE - pE : null;
  const e1rmChangePercent =
    (pE != null && pE > 0 && cE != null) ? (cE - pE) / pE * 100 : null;

  const weighted = pW != null || cW != null;
  const tone = toneFor(
      e1rmChangePercent, volumeChangePercent, topRepsChange, weighted);
  const tags = tagsFor({
    isPr: current.isPrSession, weighted, e1rmChangePercent, loadChangeKg,
    topRepsChange, volumeChangePercent,
  });

  return {
    previousSessionId: previous.sessionId,
    currentSessionId: current.sessionId,
    loadChangeKg,
    loadChangePercent,
    topRepsChange,
    totalRepsChange,
    volumeChangeKg,
    volumeChangePercent,
    e1rmChangeKg,
    e1rmChangePercent,
    tags,
    tone,
  };
}

// ---- The engine -----------------------------------------------------------

/**
 * Builds the full per-exercise analysis, or null when the exercise has no
 * completed working history. Mirrors the Dart `analyzeExercise`.
 * @param {{exerciseId: string, sessions: !Array<Object>, now: !Date}} args
 * @return {?Object}
 */
function analyzeExercise({exerciseId, sessions, now}) {
  const completed = (sessions || [])
      .filter((s) => s.status === "completed")
      .sort((a, b) => completedAtOf(a) - completedAtOf(b));

  const records = [];
  let runBestWeight = null;
  let runBestE1rm = null;
  let runBestReps = null;
  let seenAny = false;
  let name = null;
  let muscle = null;

  for (const session of completed) {
    const peek = reduceRecord(session, exerciseId, false);
    if (!peek) continue;

    const w = peek.topWeightKg;
    const e = peek.bestE1RM;
    const r = peek.topReps;
    const beatsWeight =
      w != null && (runBestWeight == null || w > runBestWeight + EPS);
    const beatsE1rm =
      e != null && (runBestE1rm == null || e > runBestE1rm + EPS);
    const beatsReps = r > 0 && (runBestReps == null || r > runBestReps);
    const isPr = seenAny && (beatsWeight || beatsE1rm || beatsReps);

    records.push(reduceRecord(session, exerciseId, isPr));

    if (w != null && (runBestWeight == null || w > runBestWeight)) {
      runBestWeight = w;
    }
    if (e != null && (runBestE1rm == null || e > runBestE1rm)) runBestE1rm = e;
    if (r > 0 && (runBestReps == null || r > runBestReps)) runBestReps = r;
    seenAny = true;

    for (const ex of session.exercises || []) {
      if (ex.exerciseId === exerciseId) {
        name = ex.name || exerciseId;
        muscle = ex.muscleGroup || null;
      }
    }
  }

  if (records.length === 0) return null;

  // Reuse the hub engine for the direction + windowed strength change.
  const hub = analyzeTraining({sessions, now});
  const perf = hub.exercises.find((e) => e.exerciseId === exerciseId) || null;
  const status = perf ? perf.status : "building";

  const prMap = personalRecords(completed).get(exerciseId) || {};

  const comparisons = [];
  for (let i = 1; i < records.length; i++) {
    comparisons.push(compare(records[i - 1], records[i]));
  }

  const e1rmSeries = records.map((r) => r.bestE1RM);
  const volumeSeries = records.map((r) => r.totalVolumeKg);

  const latest = records[records.length - 1];
  const daysSinceLast = daysBetween(latest.date, now);
  const sessionsPerWeek = frequency(records, now);
  const isWeighted = (perf && perf.currentE1RM != null) ||
    records.some((r) => r.topWeightKg != null);

  const latestComparison = comparisons.length === 0 ?
    null : comparisons[comparisons.length - 1];

  const insight = buildInsight({
    name: name || exerciseId,
    status,
    strengthChangePercent: perf ? perf.strengthChangePercent : null,
    latestComparison,
    latest,
    isWeighted,
    totalSessions: records.length,
    daysSinceLast,
  });

  return {
    exerciseId,
    name: name || exerciseId,
    muscleGroup: muscle,
    status,
    strengthChangePercent: perf ? perf.strengthChangePercent : null,
    currentE1RM: latest.bestE1RM,
    bestE1RM: runBestE1rm,
    totalSessions: records.length,
    totalWorkingSets: records.reduce((n, r) => n + r.workingSetCount, 0),
    totalVolumeKg: records.reduce((v, r) => v + r.totalVolumeKg, 0),
    daysSinceLast,
    sessionsPerWeek,
    isWeighted,
    sessions: records,
    comparisons,
    records: prMap,
    e1rmSeries,
    volumeSeries,
    verdict: status,
    latestTone: latestComparison ? latestComparison.tone : null,
    insight,
  };
}

/**
 * The three-part coaching insight, grounded in the numbers. Directional
 * next-step (no per-kg goal server-side — same convention as the hub's
 * `nextStep`). Never claims anything about the body, only the training data.
 * @param {!Object} args
 * @return {!Object}
 */
function buildInsight({name, status, strengthChangePercent, latestComparison,
  latest, isWeighted, totalSessions, daysSinceLast}) {
  const changed = latestComparison ?
    describeChange(latestComparison, latest) : null;
  const quiet = daysSinceLast >= QUIET_EXERCISE_DAYS ?
    ` It has been ${daysSinceLast} days since you last trained it.` : "";

  const doByStatus = {
    building:
      `Keep logging ${name} — a couple more sessions and ZIVO can guide the load.`,
    progressing:
      `You're ready to progress ${name} — nudge the load or reps up next session.`,
    maintaining:
      `Push for one more rep or a small load bump on ${name} to restart progression.`,
    plateauing:
      `${name} has been flat — try a small load bump, or drop the reps and build back up.`,
    regressing:
      `Hold the weight on ${name} and rebuild your reps before adding load — and check recovery.`,
  };
  const whatToDo = doByStatus[status] || doByStatus.building;

  switch (status) {
    case "building": {
      const promising = latestComparison &&
        latestComparison.tone === "improved";
      return {
        whatHappened: changed ||
          `You've logged ${name} ${sessionsWord(totalSessions)} so far.${quiet}`,
        whyItMatters: !latestComparison ?
          "Not enough history yet to call a direction — a couple more sessions and the trend becomes real." :
          `${promising ? "Encouraging" : "Noted"}, but it's only ${sessionsWord(totalSessions)} — one or two more and ZIVO can confirm the trend rather than a single step.`,
        whatToDo,
      };
    }
    case "progressing":
      return {
        whatHappened: changed ||
          `${name} is trending up across your recent sessions.${quiet}`,
        whyItMatters: isWeighted ?
          `Estimated 1RM is ${signed(strengthChangePercent)} — real strength gain, not just extra volume. The heavier load is paying for any drop in reps.` :
          "You're doing more work at this movement — reps and volume are climbing.",
        whatToDo,
      };
    case "maintaining":
      return {
        whatHappened: changed ||
          `${name} has held about steady over your last few sessions.${quiet}`,
        whyItMatters:
          "Strength is stable — you're holding, not building. Left alone it will stay here.",
        whatToDo,
      };
    case "plateauing":
      return {
        whatHappened:
          `${name} hasn't moved meaningfully in several sessions.${quiet}`,
        whyItMatters:
          "A plateau this long usually means the current load and rep scheme have been fully adapted to.",
        whatToDo,
      };
    case "regressing":
      return {
        whatHappened: changed ||
          `${name} has trended down recently${strengthChangePercent == null ? "" : ` (${signed(strengthChangePercent)} estimated strength)`}.${quiet}`,
        whyItMatters:
          "A short-term dip is often fatigue or recovery rather than lost strength — but worth acting on before it settles in.",
        whatToDo,
      };
    default:
      return {whatHappened: "", whyItMatters: "", whatToDo};
  }
}

/**
 * "Since last time, working load rose 35 → 40kg while top reps down 10 → 7."
 * Mirrors the Dart `_describeChange` (reads off the comparison + records).
 * @param {!Object} c
 * @param {!Object} current
 * @return {string}
 */
function describeChange(c, current) {
  const parts = [];
  // The comparison carries deltas; the previous session's absolutes come off
  // (current - delta) so the copy always matches the arrows.
  const cW = current.topWeightKg;
  const pW = cW != null && c.loadChangeKg != null ? cW - c.loadChangeKg : null;
  if (pW != null && cW != null && Math.abs(cW - pW) > EPS) {
    parts.push(`working load ${cW > pW ? "rose" : "eased"} ${kg(pW)} → ${kg(cW)}kg`);
  }
  const cr = current.topReps;
  const pr = cr - c.topRepsChange;
  if (pr !== cr && pr > 0 && cr > 0) {
    parts.push(`top reps ${cr > pr ? "up" : "down"} ${pr} → ${cr}`);
  }
  if (parts.length === 0 && c.volumeChangePercent != null &&
      Math.abs(c.volumeChangePercent) >= MEANINGFUL_CHANGE_PCT) {
    parts.push(`working volume ${signed(c.volumeChangePercent)}`);
  }
  if (parts.length === 0) return "Little changed versus your previous session.";
  return `Since last time, ${joinParts(parts)}.`;
}

// ---- Plan adherence -------------------------------------------------------

/**
 * Joins the active plan against completed history to flag what's being skipped.
 * Mirrors the Dart `analyzePlanAdherence`. Returns an empty result when there's
 * no plan, no planned movement, or no completed history to judge against.
 * @param {{plan: ?Object, sessions: !Array<Object>, now: !Date}} args
 * @return {!Object}
 */
function analyzePlanAdherence({plan, sessions, now}) {
  if (!plan || !(plan.days || []).length) {
    return {neglected: [], plannedExerciseCount: 0};
  }

  const completed = (sessions || []).filter((s) => s.status === "completed");
  const plannedIds = new Set();
  for (const day of plan.days) {
    for (const ex of day.exercises || []) plannedIds.add(ex.id);
  }
  if (completed.length === 0) {
    return {neglected: [], plannedExerciseCount: plannedIds.size};
  }

  const lastTrained = new Map();
  const appearances = new Map();
  for (const session of completed) {
    const at = completedAtOf(session);
    const seen = new Set();
    for (const ex of session.exercises || []) {
      if ((ex.sets || []).some(isWorkingSet)) seen.add(ex.exerciseId);
    }
    for (const id of seen) {
      appearances.set(id, (appearances.get(id) || 0) + 1);
      const prev = lastTrained.get(id);
      if (prev == null || at.getTime() > prev.getTime()) {
        lastTrained.set(id, at);
      }
    }
  }

  const planned = new Set();
  const out = [];
  for (const day of plan.days) {
    for (const ex of day.exercises || []) {
      if (planned.has(ex.id)) continue;
      planned.add(ex.id);
      const count = appearances.get(ex.id) || 0;
      if (count === 0) {
        out.push({
          exerciseId: ex.id,
          name: ex.name || ex.id,
          muscleGroup: ex.muscleGroup || null,
          dayLabel: day.label || "",
          reason: "neverTrained",
          appearances: 0,
          daysSinceLast: null,
        });
        continue;
      }
      const days = daysBetween(lastTrained.get(ex.id), now);
      if (days >= STALE_PLANNED_EXERCISE_DAYS) {
        out.push({
          exerciseId: ex.id,
          name: ex.name || ex.id,
          muscleGroup: ex.muscleGroup || null,
          dayLabel: day.label || "",
          reason: "stale",
          appearances: count,
          daysSinceLast: days,
        });
      }
    }
  }

  out.sort((a, b) => {
    if (a.reason !== b.reason) return a.reason === "neverTrained" ? -1 : 1;
    return (b.daysSinceLast == null ? 1 << 30 : b.daysSinceLast) -
      (a.daysSinceLast == null ? 1 << 30 : a.daysSinceLast);
  });

  return {neglected: out, plannedExerciseCount: planned.size};
}

// ---- Helpers --------------------------------------------------------------

/**
 * @param {!Date} from
 * @param {!Date} to
 * @return {number}
 */
function daysBetween(from, to) {
  const a = new Date(from.getFullYear(), from.getMonth(), from.getDate());
  const b = new Date(to.getFullYear(), to.getMonth(), to.getDate());
  return Math.round((b.getTime() - a.getTime()) / DAY_MS);
}

/**
 * Completed sessions per week across the span; null under 2 sessions or a zero
 * span.
 * @param {!Array<Object>} records
 * @param {!Date} now
 * @return {?number}
 */
function frequency(records, now) {
  if (records.length < 2) return null;
  const spanDays =
    daysBetween(records[0].date, records[records.length - 1].date);
  if (spanDays <= 0) return null;
  return records.length / (spanDays / 7.0);
}

const kg = (v) => Number.isInteger(v) ? String(v) : v.toFixed(1);
const signed = (pct) =>
  pct == null ? "—" : `${pct > 0 ? "+" : ""}${Math.round(pct)}%`;
const sessionsWord = (n) => n === 1 ? "1 session" : `${n} sessions`;

/**
 * @param {!Array<string>} parts
 * @return {string}
 */
function joinParts(parts) {
  if (parts.length === 1) return parts[0];
  if (parts.length === 2) return `${parts[0]} while ${parts[1]}`;
  return `${parts.slice(0, -1).join(", ")} and ${parts[parts.length - 1]}`;
}

module.exports = {
  analyzeExercise,
  analyzePlanAdherence,
  STALE_PLANNED_EXERCISE_DAYS,
};
