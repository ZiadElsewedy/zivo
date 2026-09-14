/**
 * The server's mirror of
 * `lib/features/workout/domain/analytics/workout_analytics.dart`.
 *
 * **The workout coach's numbers are computed HERE, deterministically — the
 * model never derives them.** This turns a user's `workoutSessions` history
 * into the same structured analysis the app's Progress screen shows: estimated
 * 1RM, PRs, per-exercise direction, a simple per-muscle rollup, working
 * volume, and typed `findings` the model leads with and may not contradict.
 *
 * A deliberate transliteration of the Dart engine — the constants and rules
 * below are line-for-line the same, so the AI and the screen can never
 * disagree about whether a lift is progressing. Pinned by
 * `test/fixtures/workout_analytics_vectors.json`, which BOTH the Dart and Node
 * suites run; change one side and the other fails until they agree again.
 *
 * Pure and store-seamed like the rest of `./ai/`: no SDK imports, so it runs
 * offline under `node --test`.
 */

// ---- Tunables (mirror lib/.../workout_analytics.dart) ---------------------

const MAX_RELIABLE_REPS_FOR_E1RM = 12;
const MIN_APPEARANCES = 3;
const PLATEAU_APPEARANCES = 4;
const MEANINGFUL_CHANGE_PCT = 2.5;
// Beyond this magnitude a per-exercise strength change isn't a trustworthy
// figure (a near-empty / first-exposure baseline); the direction stands but the
// number is withheld (null). Mirrors the Dart kMaxReliableStrengthChangePct.
const MAX_RELIABLE_STRENGTH_CHANGE_PCT = 100.0;
const MUSCLE_VOLUME_DROP_PCT = 20.0;
const WEEK_WINDOW_DAYS = 7;
const STRENGTH_WINDOW_DAYS = 42;
const RECENT_PR_WINDOW_DAYS = 30;
const EPS = 0.0001;
const DAY_MS = 24 * 60 * 60 * 1000;

// Statuses as plain strings (the model reads these directly).
const PROGRESSING = "progressing";
const MAINTAINING = "maintaining";
const PLATEAUING = "plateauing";
const REGRESSING = "regressing";
const BUILDING = "building";

/**
 * Epley estimated 1RM from one working set. The ONLY place the formula lives
 * server-side. Null when unloaded, non-positive, or too many reps to trust.
 * @param {?number} weightKg
 * @param {?number} reps
 * @return {?number}
 */
function estimatedOneRepMax(weightKg, reps) {
  if (weightKg == null || reps == null) return null;
  if (weightKg <= 0 || reps < 1 || reps > MAX_RELIABLE_REPS_FOR_E1RM) {
    return null;
  }
  if (reps === 1) return weightKg;
  return weightKg * (1 + reps / 30.0);
}

/**
 * Folds a free-text muscle label into one of six buckets, or null.
 * @param {?string} raw
 * @return {?string}
 */
function normalizeMuscleGroup(raw) {
  if (raw == null) return null;
  const s = String(raw).toLowerCase();
  const has = (keys) => keys.some((k) => s.includes(k));
  if (has(["chest", "pec", "bench"])) return "Chest";
  if (has(["back", "lat", "row", "pull", "trap", "rhomboid", "erector"])) {
    return "Back";
  }
  if (has(["quad", "hamstring", "glute", "calf", "calves", "leg", "squat",
    "lunge", "hip"])) {
    return "Legs";
  }
  if (has(["shoulder", "delt", "ohp", "press (overhead)", "lateral raise"])) {
    return "Shoulders";
  }
  if (has(["bicep", "tricep", "forearm", "arm", "curl"])) return "Arms";
  if (has(["ab", "core", "oblique"])) return "Core";
  return null;
}

/**
 * A performed, non-warm-up set. Mirrors `_isWorkingSet`.
 * @param {!Object} set
 * @return {boolean}
 */
function isWorkingSet(set) {
  return set && set.outcome === "completed" && set.type !== "warmup";
}

/**
 * Local-calendar-day start (ms) for a Date.
 * @param {!Date} date
 * @return {number}
 */
function dayStartMs(date) {
  const d = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  return d.getTime();
}

/**
 * A session's effective timestamp — its completion, or its start.
 * @param {!Object} session
 * @return {!Date}
 */
function completedAtOf(session) {
  return session.completedAt || session.startedAt;
}

/**
 * Reduces one session's working sets for an exercise to an appearance, or null.
 * @param {!Object} session
 * @param {string} exerciseId
 * @return {?Object}
 */
function appearanceFor(session, exerciseId) {
  const working = [];
  for (const ex of session.exercises || []) {
    if (ex.exerciseId !== exerciseId) continue;
    for (const s of ex.sets || []) {
      if (isWorkingSet(s)) working.push(s);
    }
  }
  if (working.length === 0) return null;
  let bestE1RM = null;
  let topWeight = null;
  let volume = 0;
  let bestReps = 0;
  let bestRepsWeight = null;
  for (const s of working) {
    const reps = s.actualReps;
    const w = s.actualWeightKg;
    if (reps != null && w != null) volume += reps * w;
    if (w != null && (topWeight == null || w > topWeight)) topWeight = w;
    const e = estimatedOneRepMax(w, reps);
    if (e != null && (bestE1RM == null || e > bestE1RM)) bestE1RM = e;
    if (reps != null && reps > bestReps) {
      bestReps = reps;
      bestRepsWeight = w;
    }
  }
  return {
    date: completedAtOf(session),
    bestE1RM,
    topWeightKg: topWeight,
    workingVolumeKg: volume,
    bestReps,
    bestRepsWeightKg: bestRepsWeight,
  };
}

/**
 * Every exerciseId → its completed working appearances (oldest→newest) plus
 * the freshest display name and normalized muscle.
 * @param {!Array<Object>} completed
 * @return {!Map<string, Object>}
 */
function historyByExercise(completed) {
  const byId = new Map();
  for (const session of completed) {
    for (const ex of session.exercises || []) {
      const appearance = appearanceFor(session, ex.exerciseId);
      if (!appearance) continue;
      let entry = byId.get(ex.exerciseId);
      if (!entry) {
        entry = {
          name: ex.name || ex.exerciseId,
          muscleGroup: normalizeMuscleGroup(ex.muscleGroup),
          appearances: [],
        };
        byId.set(ex.exerciseId, entry);
      }
      entry.appearances.push(appearance);
    }
  }
  for (const entry of byId.values()) {
    entry.appearances.sort((a, b) => a.date - b.date);
  }
  return byId;
}

/**
 * Best reps across appearances — a bodyweight movement's only progression
 * signal (used when nothing was ever loaded).
 * @param {!Array<Object>} apps
 * @return {?number}
 */
function bestReps(apps) {
  let best = null;
  for (const a of apps) {
    if (a.bestReps > 0 && (best == null || a.bestReps > best)) {
      best = a.bestReps;
    }
  }
  return best;
}

/**
 * The best e1RM across appearances.
 * @param {!Array<Object>} apps
 * @return {?number}
 */
function bestE1RMOf(apps) {
  let best = null;
  for (const a of apps) {
    if (a.bestE1RM != null && (best == null || a.bestE1RM > best)) {
      best = a.bestE1RM;
    }
  }
  return best;
}

/**
 * Classifies one exercise from its oldest→newest appearances.
 * @param {string} id
 * @param {!Object} h
 * @return {!Object}
 */
function classify(id, h) {
  const apps = h.appearances;
  const last = apps[apps.length - 1];
  const series = apps.filter((a) => a.bestE1RM != null).map((a) => a.bestE1RM);

  let status = BUILDING;
  let changePercent = null;
  let baseline = null;
  if (apps.length >= MIN_APPEARANCES) {
    const recentCount = apps.length >= 2 ? 2 : 1;
    const recentApps = apps.slice(apps.length - recentCount);
    const earlierApps = apps.slice(0, apps.length - recentCount);
    // Compare on ONE metric so kilograms and reps are never divided by each
    // other: estimated 1RM for a loaded lift, best reps for a bodyweight one.
    const weighted = apps.some((a) => a.bestE1RM != null);
    const recentScore =
      weighted ? bestE1RMOf(recentApps) : bestReps(recentApps);
    const baselineScore =
      weighted ? bestE1RMOf(earlierApps) : bestReps(earlierApps);
    if (recentScore == null || baselineScore == null || baselineScore <= 0) {
      // A loaded lift whose baseline window has no logged weight has no
      // comparable strength number — "building", never a reps-vs-kg ratio.
      status = BUILDING;
    } else {
      const raw = (recentScore - baselineScore) / baselineScore * 100;
      baseline = weighted ? bestE1RMOf(earlierApps) : null;
      if (raw >= MEANINGFUL_CHANGE_PCT) {
        status = PROGRESSING;
      } else if (raw <= -MEANINGFUL_CHANGE_PCT) {
        status = REGRESSING;
      } else if (apps.length >= PLATEAU_APPEARANCES) {
        status = PLATEAUING;
      } else {
        status = MAINTAINING;
      }
      // Direction stands; report the % only when the baseline is trustworthy.
      changePercent =
        Math.abs(raw) <= MAX_RELIABLE_STRENGTH_CHANGE_PCT ? raw : null;
    }
  }

  return {
    exerciseId: id,
    name: h.name,
    muscleGroup: h.muscleGroup,
    status,
    appearances: apps.length,
    currentE1RM: last.bestE1RM,
    baselineE1RM: baseline,
    strengthChangePercent: changePercent,
    lastPerformedAt: last.date,
    e1rmSeries: series,
  };
}

/**
 * All-time PRs per exercise, derived purely from history. Map keyed by
 * exerciseId → {heaviestWeight, mostReps, bestEstimatedStrength}.
 * @param {!Array<Object>} completed
 * @return {!Map<string, Object>}
 */
function personalRecords(completed) {
  const ordered = [...completed].sort(
      (a, b) => completedAtOf(a) - completedAtOf(b));
  const byId = new Map();
  for (const session of ordered) {
    const at = completedAtOf(session);
    for (const ex of session.exercises || []) {
      for (const s of ex.sets || []) {
        if (!isWorkingSet(s)) continue;
        const reps = s.actualReps;
        const w = s.actualWeightKg;
        if (reps == null) continue;
        let records = byId.get(ex.exerciseId);
        if (!records) {
          records = {};
          byId.set(ex.exerciseId, records);
        }

        if (w != null) {
          const cur = records.heaviestWeight;
          if (!cur || w > (cur.weightKg || 0) + EPS) {
            records.heaviestWeight = pr(ex, "heaviestWeight", w, reps, at);
          }
        }

        const repPr = records.mostReps;
        const beatsReps = !repPr || reps > repPr.reps ||
          (reps === repPr.reps && (w || 0) > (repPr.weightKg || 0) + EPS);
        if (beatsReps) {
          records.mostReps = pr(ex, "mostReps", w, reps, at);
        }

        const e = estimatedOneRepMax(w, reps);
        if (e != null) {
          const cur = records.bestEstimatedStrength;
          if (!cur || e > (cur.estimatedOneRepMax || 0) + EPS) {
            records.bestEstimatedStrength =
              pr(ex, "bestEstimatedStrength", w, reps, at);
          }
        }
      }
    }
  }
  return byId;
}

/**
 * Builds one PR record.
 * @param {!Object} ex
 * @param {string} kind
 * @param {?number} weightKg
 * @param {number} reps
 * @param {!Date} at
 * @return {!Object}
 */
function pr(ex, kind, weightKg, reps, at) {
  return {
    exerciseId: ex.exerciseId,
    name: ex.name || ex.exerciseId,
    kind,
    weightKg: weightKg == null ? null : weightKg,
    reps,
    estimatedOneRepMax: estimatedOneRepMax(weightKg, reps),
    achievedAt: at,
  };
}

/**
 * Working volume (Σ reps × weight) inside [fromDaysAgo, toDaysAgo) back from
 * now, over completed sessions.
 * @param {!Array<Object>} completed
 * @param {!Date} now
 * @param {number} fromDaysAgo
 * @param {number} toDaysAgo
 * @return {number}
 */
function windowVolume(completed, now, fromDaysAgo, toDaysAgo) {
  const today = dayStartMs(now);
  const start = today - fromDaysAgo * DAY_MS;
  const end = today - toDaysAgo * DAY_MS;
  let total = 0;
  for (const session of completed) {
    const day = dayStartMs(completedAtOf(session));
    if (day < start || day >= end) continue;
    for (const ex of session.exercises || []) {
      for (const s of ex.sets || []) {
        if (!isWorkingSet(s)) continue;
        const reps = s.actualReps;
        const w = s.actualWeightKg;
        if (reps != null && w != null) total += reps * w;
      }
    }
  }
  return total;
}

/**
 * Strength change for one exercise over the headline window: best e1RM recent
 * vs prior. Null unless both windows carry a reliable estimate.
 * @param {!Object} h
 * @param {!Date} now
 * @return {?number}
 */
function strengthChangeOverWindow(h, now) {
  const nowMs = now.getTime();
  const recentStart = nowMs - STRENGTH_WINDOW_DAYS * DAY_MS;
  const priorStart = nowMs - STRENGTH_WINDOW_DAYS * 2 * DAY_MS;
  let recentBest = null;
  let priorBest = null;
  for (const a of h.appearances) {
    if (a.bestE1RM == null) continue;
    const t = a.date.getTime();
    if (t > recentStart) {
      if (recentBest == null || a.bestE1RM > recentBest) {
        recentBest = a.bestE1RM;
      }
    } else if (t > priorStart) {
      if (priorBest == null || a.bestE1RM > priorBest) {
        priorBest = a.bestE1RM;
      }
    }
  }
  if (recentBest == null || priorBest == null || priorBest === 0) return null;
  return (recentBest - priorBest) / priorBest * 100;
}

/**
 * Simple per-muscle weekly rollup: working sets this week and volume trend.
 * @param {!Array<Object>} completed
 * @param {!Date} now
 * @return {!Array<Object>}
 */
function muscleRollup(completed, now) {
  const today = dayStartMs(now);
  const weekStart = today - WEEK_WINDOW_DAYS * DAY_MS;
  const priorStart = today - WEEK_WINDOW_DAYS * 2 * DAY_MS;
  const setsThisWeek = new Map();
  const volThisWeek = new Map();
  const volPriorWeek = new Map();
  for (const session of completed) {
    const day = dayStartMs(completedAtOf(session));
    const inThisWeek = day >= weekStart && day <= today;
    const inPriorWeek = day >= priorStart && day < weekStart;
    if (!inThisWeek && !inPriorWeek) continue;
    for (const ex of session.exercises || []) {
      const muscle = normalizeMuscleGroup(ex.muscleGroup);
      if (muscle == null) continue;
      for (const s of ex.sets || []) {
        if (!isWorkingSet(s)) continue;
        const reps = s.actualReps;
        const w = s.actualWeightKg;
        const vol = (reps != null && w != null) ? reps * w : 0;
        if (inThisWeek) {
          setsThisWeek.set(muscle, (setsThisWeek.get(muscle) || 0) + 1);
          volThisWeek.set(muscle, (volThisWeek.get(muscle) || 0) + vol);
        } else {
          volPriorWeek.set(muscle, (volPriorWeek.get(muscle) || 0) + vol);
        }
      }
    }
  }
  const muscles = new Set([...setsThisWeek.keys(), ...volPriorWeek.keys()]);
  const out = [];
  for (const m of muscles) {
    const vThis = volThisWeek.get(m) || 0;
    const vPrior = volPriorWeek.get(m) || 0;
    const change = vPrior <= 0 ? null : (vThis - vPrior) / vPrior * 100;
    let status;
    if (change == null) status = BUILDING;
    else if (change >= MEANINGFUL_CHANGE_PCT) status = PROGRESSING;
    else if (change <= -MUSCLE_VOLUME_DROP_PCT) status = REGRESSING;
    else status = MAINTAINING;
    out.push({
      muscle: m,
      weeklyWorkingSets: setsThisWeek.get(m) || 0,
      status,
      volumeChangePercent: change,
    });
  }
  out.sort((a, b) => b.weeklyWorkingSets - a.weeklyWorkingSets);
  return out;
}

/**
 * The median of a non-empty list.
 * @param {!Array<number>} values
 * @return {number}
 */
function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

const pctStr = (v) => `${Math.round(v)}%`;
const signedPct = (v) => `${v > 0 ? "+" : ""}${Math.round(v)}%`;

/**
 * The overall status + summary copy. Mirrors the Dart `_overall`.
 * @param {!Object} args
 * @return {!Object}
 */
function overall({overallStrength, recentPrCount, improving, needsAttention}) {
  const prPart = recentPrCount === 0 ? "" :
    `, and you've set ${recentPrCount} new PR${recentPrCount === 1 ? "" : "s"}`;
  if (overallStrength != null && overallStrength >= MEANINGFUL_CHANGE_PCT) {
    return {
      status: PROGRESSING,
      headline: "You're progressing",
      detail: `Your strength is up ${pctStr(overallStrength)} over the last ` +
        `6 weeks${prPart}.`,
    };
  }
  if (overallStrength != null && overallStrength <= -MEANINGFUL_CHANGE_PCT) {
    return {
      status: REGRESSING,
      headline: "Progress may be slowing",
      detail: `Your main lifts are down ${pctStr(Math.abs(overallStrength))} ` +
        "over the last 6 weeks — worth easing off or checking recovery.",
    };
  }
  if (recentPrCount > 0) {
    return {
      status: MAINTAINING,
      headline: "Progress is steady",
      detail: `Most of your main lifts are holding, with ${recentPrCount} ` +
        `new PR${recentPrCount === 1 ? "" : "s"} this month.`,
    };
  }
  if (needsAttention.length > 0 && improving.length === 0) {
    return {
      status: PLATEAUING,
      headline: "Progress may be slowing",
      detail: "A few lifts have been flat recently — small changes could get " +
        "them moving again.",
    };
  }
  return {
    status: MAINTAINING,
    headline: "Progress is steady",
    detail: "You're holding your performance. Keep logging and ZIVO will " +
      "surface where you're trending.",
  };
}

/**
 * Typed, evidenced findings the model leads with. Mirrors `_buildFindings`.
 * @param {!Object} args
 * @return {!Array<Object>}
 */
function buildFindings({
  overallStrength, recentPrs, improving, needsAttention, muscles, volume,
}) {
  const out = [];
  if (overallStrength != null) {
    out.push({
      kind: "observation",
      confidence: "fact",
      text: overallStrength >= 0 ?
        `Overall estimated strength is up ${pctStr(overallStrength)} over ` +
          "the last 6 weeks." :
        `Overall estimated strength is down ${pctStr(Math.abs(overallStrength))} ` +
          "over the last 6 weeks.",
      evidence: ["overallStrengthChangePercent"],
    });
  }
  if (recentPrs.length > 0) {
    out.push({
      kind: "encouragement",
      confidence: "fact",
      text: `${recentPrs.length} new PR${recentPrs.length === 1 ? "" : "s"} ` +
        `in the last month — including ${recentPrs[0].name}.`,
      evidence: ["recentPrs"],
    });
  }
  for (const e of improving.slice(0, 2)) {
    out.push({
      kind: "analysis",
      confidence: "interpretation",
      text: e.strengthChangePercent == null ?
        `${e.name} is progressing.` :
        `${e.name} is progressing — estimated strength ` +
          `${signedPct(e.strengthChangePercent)}.`,
      evidence: ["exercises"],
    });
  }
  for (const e of needsAttention.slice(0, 2)) {
    const line = e.status === REGRESSING ?
      (e.strengthChangePercent == null ?
        `${e.name} has been trending down recently.` :
        `${e.name} has been trending down recently ` +
          `(${signedPct(e.strengthChangePercent)}).`) :
      `${e.name} has stayed about the same for several sessions.`;
    out.push({
      kind: "warning",
      confidence: "interpretation",
      text: line,
      evidence: ["exercises"],
    });
  }
  const dropped = muscles.find(
      (m) => (m.volumeChangePercent || 0) <= -MUSCLE_VOLUME_DROP_PCT);
  if (dropped) {
    out.push({
      kind: "observation",
      confidence: "fact",
      text: `${dropped.muscle} working volume is down ` +
        `${pctStr(Math.abs(dropped.volumeChangePercent))} vs last week.`,
      evidence: ["muscles"],
    });
  }
  if (volume.changePercent != null &&
      Math.abs(volume.changePercent) >= MEANINGFUL_CHANGE_PCT) {
    out.push({
      kind: "observation",
      confidence: "fact",
      text: `Weekly working volume is ${signedPct(volume.changePercent)} vs ` +
        "last week.",
      evidence: ["volume"],
    });
  }
  return out;
}

/**
 * The one entry point. Builds the full analysis from raw sessions (any status;
 * it filters to completed) as of `now`.
 * @param {{sessions: !Array<Object>, now: !Date}} args
 * @return {!Object}
 */
function analyzeTraining({sessions, now}) {
  const completed = (sessions || []).filter((s) => s.status === "completed");
  if (completed.length === 0) {
    return {
      overallStatus: BUILDING,
      summaryHeadline: "Let's get started",
      summaryDetail:
        "Log a few sessions and ZIVO will start tracking how you progress.",
      overallStrengthChangePercent: null,
      exercises: [],
      muscles: [],
      volume: {thisWeekKg: 0, lastWeekKg: 0, changePercent: null},
      recentPrs: [],
      improving: [],
      needsAttention: [],
      nextStep: null,
      findings: [],
      completedSessionCount: 0,
    };
  }

  const history = historyByExercise(completed);
  const exercises = [...history.entries()]
      .map(([id, h]) => classify(id, h))
      .sort((a, b) => {
        const ca = a.strengthChangePercent == null ?
          -1 : Math.abs(a.strengthChangePercent);
        const cb = b.strengthChangePercent == null ?
          -1 : Math.abs(b.strengthChangePercent);
        if (ca !== cb) return cb - ca;
        return b.lastPerformedAt - a.lastPerformedAt;
      });

  const strengthChanges = [];
  for (const h of history.values()) {
    const change = strengthChangeOverWindow(h, now);
    if (change != null) strengthChanges.push(change);
  }
  const overallStrength =
    strengthChanges.length === 0 ? null : median(strengthChanges);

  const thisWeek = windowVolume(completed, now, WEEK_WINDOW_DAYS, 0);
  const lastWeek =
    windowVolume(completed, now, WEEK_WINDOW_DAYS * 2, WEEK_WINDOW_DAYS);
  const volume = {
    thisWeekKg: thisWeek,
    lastWeekKg: lastWeek,
    changePercent:
      lastWeek <= 0 ? null : (thisWeek - lastWeek) / lastWeek * 100,
  };

  const muscles = muscleRollup(completed, now);

  const prMap = personalRecords(completed);
  const cutoff = now.getTime() - RECENT_PR_WINDOW_DAYS * DAY_MS;
  const recentPrs = [];
  for (const byKind of prMap.values()) {
    for (const rec of Object.values(byKind)) {
      if (rec.achievedAt.getTime() > cutoff) recentPrs.push(rec);
    }
  }
  recentPrs.sort((a, b) => b.achievedAt - a.achievedAt);

  // Status already encodes the threshold, so a big-but-withheld % (null) still
  // counts as improving.
  const improving = exercises.filter((e) => e.status === PROGRESSING);
  const needsAttention = exercises.filter((e) =>
    e.status === REGRESSING || e.status === PLATEAUING);

  const o = overall({
    overallStrength,
    recentPrCount: recentPrs.length,
    improving,
    needsAttention,
  });

  const findings = buildFindings({
    overallStrength, recentPrs, improving, needsAttention, muscles, volume,
  });

  return {
    overallStatus: o.status,
    summaryHeadline: o.headline,
    summaryDetail: o.detail,
    overallStrengthChangePercent: overallStrength,
    exercises,
    muscles,
    volume,
    recentPrs,
    improving,
    needsAttention,
    nextStep: nextStep(exercises),
    findings,
    completedSessionCount: completed.length,
  };
}

/**
 * A concise next step for the model. Server-side we don't rebuild the full
 * double-progression phrasing (that's the app's live goal card); we point at
 * the exercise and let the deterministic status carry the direction.
 * @param {!Array<Object>} exercises
 * @return {?Object}
 */
function nextStep(exercises) {
  if (exercises.length === 0) return null;
  let target = exercises.find((e) =>
    e.currentE1RM != null &&
    (e.status === PROGRESSING || e.status === MAINTAINING));
  if (!target) {
    target = exercises.find((e) =>
      e.status === PLATEAUING || e.status === REGRESSING) || exercises[0];
  }
  let text;
  switch (target.status) {
    case PROGRESSING:
    case MAINTAINING:
      text = `Keep progressing ${target.name} — you're ready to nudge the ` +
        "load or reps up.";
      break;
    case PLATEAUING:
      text = `${target.name} has been flat for a few sessions — a small load ` +
        "bump, or dropping reps and building back, could restart it.";
      break;
    case REGRESSING:
      text = `${target.name} has trended down — hold the weight, rebuild ` +
        "reps, and check recovery before adding load.";
      break;
    default:
      text = `Keep logging ${target.name} so ZIVO can guide the load.`;
  }
  return {exerciseId: target.exerciseId, name: target.name, text};
}

module.exports = {
  analyzeTraining,
  personalRecords,
  estimatedOneRepMax,
  normalizeMuscleGroup,
  isWorkingSet,
  // Exposed for the per-exercise drill-down mirror (`exercise_analytics.js`),
  // so it reads a session's timestamp the exact same way the hub engine does.
  completedAtOf,
  MEANINGFUL_CHANGE_PCT,
  EPS,
};
