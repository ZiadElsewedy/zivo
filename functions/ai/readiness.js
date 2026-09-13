/**
 * The server's mirror of the pure combination layer in
 * `lib/features/readiness/domain/readiness.dart` (`readinessFromSignals`).
 *
 * The Daily Readiness call — train hard / go light / rest — fused from last
 * night's sleep, the training stall/deload signal, how recently the user
 * trained, and their body-weight trend. **The coach explains this call; it
 * never derives its own.** A deliberate transliteration of the Dart engine —
 * the constants and rules below are line-for-line the same — pinned by
 * `test/fixtures/readiness_vectors.json`, which BOTH suites run; change one
 * side and the other fails until they agree.
 *
 * Pure and store-seamed like the rest of `./ai/`: no SDK imports, runs offline
 * under `node --test`. The assembly of these primitive signals from the user's
 * stored data lives in the `get_readiness` tool (`tools.js`).
 */

// ---- Thresholds (identical to the Dart engine) ----------------------------

const SLEEP_SHORT_MINUTES = 30;
const SLEEP_SEVERE_MINUTES = 90;
const DELOAD_STALLED_COUNT = 2;
const RECOVERED_REST_DAYS = 2;
const RAPID_LOSS_KG = 2.0;
const DEFAULT_SLEEP_TARGET_MINUTES = 8 * 60;

/**
 * Whether the workout analysis says a deload is due: a cluster of stalled lifts
 * or an overall regression.
 * @param {number} stalledCount
 * @param {boolean} overallRegressing
 * @return {boolean}
 */
function readinessDeloadDueFrom(stalledCount, overallRegressing) {
  return stalledCount >= DELOAD_STALLED_COUNT || overallRegressing;
}

const PULL = {limits: 2, caution: 1, supports: 0};

/**
 * Fuse primitive signals into a readiness call, or null on the gate (no recent
 * sleep, no training, no weigh-in). Mirrors Dart `readinessFromSignals`.
 *
 * @param {!Object} signals Optional fields: `sleepDurationMinutes`,
 *   `sleepTargetMinutes`, `stalledCount`, `overallStatusRegressing`,
 *   `lastSessionDaysAgo`, `weightChangeKg` (the nullable ones gate to null).
 * @return {?Object} `{verdict, factors}`, or null on the gate.
 */
function readinessFromSignals(signals) {
  const sleepDurationMinutes = signals.sleepDurationMinutes ?? null;
  const sleepTargetMinutes = signals.sleepTargetMinutes ?? null;
  const stalledCount = signals.stalledCount ?? 0;
  const overallStatusRegressing = signals.overallStatusRegressing ?? false;
  const lastSessionDaysAgo = signals.lastSessionDaysAgo ?? null;
  const weightChangeKg = signals.weightChangeKg ?? null;

  const factors = [];

  // Sleep.
  if (sleepDurationMinutes !== null) {
    const target = sleepTargetMinutes ?? DEFAULT_SLEEP_TARGET_MINUTES;
    const delta = sleepDurationMinutes - target;
    const direction = delta <= -SLEEP_SEVERE_MINUTES ?
      "limits" :
      delta <= -SLEEP_SHORT_MINUTES ? "caution" : "supports";
    factors.push({
      kind: "sleep",
      direction,
      sleepDurationMinutes,
      sleepDeltaMinutes: delta,
    });
  }

  // Deload.
  if (readinessDeloadDueFrom(stalledCount, overallStatusRegressing)) {
    factors.push({
      kind: "deload",
      direction: "caution",
      deloadExerciseCount: stalledCount,
    });
  }

  // Recent load / recovery.
  if (lastSessionDaysAgo !== null) {
    if (lastSessionDaysAgo >= RECOVERED_REST_DAYS) {
      factors.push({
        kind: "recentLoad",
        direction: "supports",
        restDays: lastSessionDaysAgo,
      });
    } else if (lastSessionDaysAgo <= 0) {
      factors.push({
        kind: "recentLoad",
        direction: "caution",
        restDays: lastSessionDaysAgo,
      });
    }
    // A single rest day is neutral.
  }

  // Body weight.
  if (weightChangeKg !== null && weightChangeKg <= -RAPID_LOSS_KG) {
    factors.push({
      kind: "bodyWeight",
      direction: "caution",
      weightChangeKg,
    });
  }

  // Gate: no notable signal ⇒ no call (nothing to cite).
  if (factors.length === 0) return null;

  // Combine.
  let limits = 0;
  let cautions = 0;
  let supports = 0;
  for (const f of factors) {
    if (f.direction === "limits") limits++;
    else if (f.direction === "caution") cautions++;
    else supports++;
  }
  const debt = limits * 2 + cautions;
  let verdict;
  if (debt >= 3) verdict = "rest";
  else if (debt >= 1) verdict = "goLight";
  else verdict = supports >= 1 ? "trainHard" : "goLight";

  // Stable sort, strongest-pull first (matches the Dart List.sort ordering).
  factors.sort((a, b) => PULL[b.direction] - PULL[a.direction]);

  return {verdict, factors};
}

module.exports = {readinessFromSignals, readinessDeloadDueFrom};
