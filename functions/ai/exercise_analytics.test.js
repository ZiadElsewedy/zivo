/**
 * Offline tests for the Node per-exercise engine (`./exercise_analytics.js`) —
 * the mirror of `lib/features/workout/domain/analytics/exercise_analysis.dart`
 * and `plan_adherence.dart`.
 *
 * The `golden vectors` blocks load the shared vectors fixture,
 * the SAME file the Dart suite runs, so the two engines can't drift on the
 * numeric facts, the verdict/tone, the change tags, or the adherence reasons.
 * The scenario tests mirror the Dart engine's own.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

const {analyzeExercise, analyzePlanAdherence} = require("./exercise_analytics");

const REPO_ROOT = path.join(__dirname, "..", "..");
const VECTORS = JSON.parse(fs.readFileSync(
    path.join(REPO_ROOT, "test/fixtures/workout_analytics_vectors.json"),
    "utf8"));

const DAY_MS = 24 * 60 * 60 * 1000;
const NOW = new Date("2026-09-02T18:00:00");
const daysAgo = (from, d) => new Date(from.getTime() - d * DAY_MS);
const close = (a, b) => a != null && b != null && Math.abs(a - b) < 0.01;
const sign = (x) => (x == null ? 0 : x > 0 ? 1 : x < 0 ? -1 : 0);

const set = (id, {reps = null, weight = null, type = "working",
  outcome = "completed"} = {}) =>
  ({id, actualReps: reps, actualWeightKg: weight, type, outcome});

const ex = (exerciseId, sets, {name, muscleGroup = null} = {}) => ({
  id: exerciseId,
  exerciseId,
  name: name || `Exercise ${exerciseId}`,
  muscleGroup,
  restSeconds: 90,
  sets,
});

const session = (id, at, exercises, status = "completed") => ({
  id,
  planId: "plan-1",
  dayId: "day-a",
  dayLabel: "Push",
  status,
  startedAt: new Date(at.getTime() - 45 * 60000),
  completedAt: at,
  exercises,
});

// ---- Golden vectors: analyzeExercise (shared with the Dart suite) ---------

test("golden vectors: analyzeExercise matches the Dart engine", () => {
  for (const v of VECTORS.exerciseAnalysis) {
    const now = new Date(v.now);
    const sessions = v.sessions.map((s) =>
      session(s.id, daysAgo(now, s.daysAgo),
          [ex(v.exerciseId, s.sets.map((x, i) =>
            set(`${s.id}-${i}`, {reps: x.reps, weight: x.weight})))]));
    const a = analyzeExercise({exerciseId: v.exerciseId, sessions, now});
    assert.ok(a, v.name);
    const e = v.expect;

    assert.equal(a.totalSessions, e.totalSessions, `${v.name} totalSessions`);
    if (e.status) assert.equal(a.status, e.status, `${v.name} status`);
    if ("isWeighted" in e) {
      assert.equal(a.isWeighted, e.isWeighted, `${v.name} isWeighted`);
    }
    if ("currentE1RM" in e) {
      if (e.currentE1RM === null) {
        assert.equal(a.currentE1RM, null, `${v.name} currentE1RM null`);
      } else {
        assert.ok(close(a.currentE1RM, e.currentE1RM), `${v.name} currentE1RM`);
      }
    }

    const latest = a.sessions[a.sessions.length - 1];
    const previous = a.sessions[a.sessions.length - 2];
    if (e.latest) assertRecord(latest, e.latest, `${v.name} latest`);
    if (e.previous) assertRecord(previous, e.previous, `${v.name} previous`);

    if (e.latestComparison) {
      const c = a.comparisons[a.comparisons.length - 1];
      const ec = e.latestComparison;
      assert.equal(c.tone, ec.tone, `${v.name} tone`);
      assert.deepEqual(c.tags, ec.tags, `${v.name} tags`);
      assert.equal(c.loadChangeKg, ec.loadChangeKg, `${v.name} loadChangeKg`);
      assert.equal(c.topRepsChange, ec.topRepsChange, `${v.name} topRepsChange`);
      assert.equal(sign(c.e1rmChangePercent), ec.e1rmChangeSign,
          `${v.name} e1rmChangeSign`);
      assert.equal(sign(c.volumeChangePercent), ec.volumeChangeSign,
          `${v.name} volumeChangeSign`);
    }
  }
});

/**
 * @param {!Object} rec
 * @param {!Object} exp
 * @param {string} label
 */
function assertRecord(rec, exp, label) {
  for (const [k, want] of Object.entries(exp)) {
    if (k === "bestE1RM") {
      assert.ok(close(rec.bestE1RM, want), `${label} bestE1RM`);
    } else {
      assert.equal(rec[k], want, `${label} ${k}`);
    }
  }
}

// ---- Golden vectors: analyzePlanAdherence (shared with the Dart suite) -----

test("golden vectors: analyzePlanAdherence matches the Dart engine", () => {
  for (const v of VECTORS.planAdherence) {
    const now = new Date(v.now);
    const plan = {days: v.plan.days};
    const sessions = v.trained.map((t) =>
      session(`did-${t.exerciseId}`, daysAgo(now, t.daysAgo),
          [ex(t.exerciseId, [set("s", {reps: 8, weight: 40})])]));
    const a = analyzePlanAdherence({plan, sessions, now});
    assert.equal(a.plannedExerciseCount, v.expect.plannedExerciseCount, v.name);
    assert.equal(a.neglected.length, v.expect.neglected.length,
        `${v.name} neglected count`);
    v.expect.neglected.forEach((exp, i) => {
      const got = a.neglected[i];
      assert.equal(got.exerciseId, exp.exerciseId, `${v.name} [${i}] id`);
      assert.equal(got.reason, exp.reason, `${v.name} [${i}] reason`);
      assert.equal(got.daysSinceLast, exp.daysSinceLast, `${v.name} [${i}] days`);
    });
  }
});

// ---- Scenario tests -------------------------------------------------------

test("analyzeExercise: null when never trained", () => {
  assert.equal(analyzeExercise({exerciseId: "x", sessions: [], now: NOW}), null);
});

test("analyzeExercise: warm-up-only work is not history", () => {
  const sessions = [session("s1", daysAgo(NOW, 1),
      [ex("bench", [set("w", {reps: 8, weight: 40, type: "warmup"})])])];
  assert.equal(
      analyzeExercise({exerciseId: "bench", sessions, now: NOW}), null);
});

test("analyzeExercise: the deltas reach the payload as computed", () => {
  const sessions = [
    session("last", daysAgo(NOW, 7),
        [ex("incline", [set("a", {reps: 8, weight: 35}),
          set("b", {reps: 10, weight: 35})])]),
    session("this", daysAgo(NOW, 1),
        [ex("incline", [set("a", {reps: 7, weight: 40}),
          set("b", {reps: 7, weight: 40}), set("c", {reps: 6, weight: 37})])]),
  ];
  const a = analyzeExercise({exerciseId: "incline", sessions, now: NOW});
  const c = a.comparisons[a.comparisons.length - 1];
  assert.equal(c.tone, "improved");
  assert.equal(c.loadChangeKg, 5);
  assert.equal(c.topRepsChange, -3);
  assert.ok(c.e1rmChangePercent > 0);
  assert.ok(c.volumeChangePercent > 0);
  assert.ok(c.tags.includes("strengthUp"));
  assert.ok(c.tags.includes("newPr"));
  // The verdict rides along for the coach to explain, not recompute.
  assert.equal(a.verdict, a.status);
  assert.equal(a.latestTone, "improved");
});

test("analyzePlanAdherence: no plan / no history → empty", () => {
  assert.deepEqual(
      analyzePlanAdherence({plan: null, sessions: [], now: NOW}),
      {neglected: [], plannedExerciseCount: 0});
  const plan = {days: [{label: "Push", exercises: [{id: "bench", name: "B"}]}]};
  const empty = analyzePlanAdherence({plan, sessions: [], now: NOW});
  assert.deepEqual(empty.neglected, []);
  assert.equal(empty.plannedExerciseCount, 1);
});

test("analyzePlanAdherence: flags never-trained and stale", () => {
  const plan = {days: [{label: "Push", exercises: [
    {id: "bench", name: "Bench"}, {id: "ohp", name: "OHP"}, {id: "fly", name: "Fly"},
  ]}]};
  const sessions = [
    session("s1", daysAgo(NOW, 2), [ex("bench", [set("a", {reps: 8, weight: 60})])]),
    session("s2", daysAgo(NOW, 20), [ex("ohp", [set("a", {reps: 8, weight: 40})])]),
  ];
  const a = analyzePlanAdherence({plan, sessions, now: NOW});
  assert.equal(a.neglected.length, 2);
  assert.equal(a.neglected[0].exerciseId, "fly");
  assert.equal(a.neglected[0].reason, "neverTrained");
  assert.equal(a.neglected[1].exerciseId, "ohp");
  assert.equal(a.neglected[1].reason, "stale");
  assert.equal(a.neglected[1].daysSinceLast, 20);
});
