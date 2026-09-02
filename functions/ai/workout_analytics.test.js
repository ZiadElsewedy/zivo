/**
 * Offline tests for the Node workout analytics engine
 * (`./workout_analytics.js`) — the mirror of
 * `lib/features/workout/domain/analytics/workout_analytics.dart`.
 *
 * The `golden vectors` blocks load
 * `test/fixtures/workout_analytics_vectors.json`, the SAME file the Dart suite
 * runs, so the two engines can't drift on the drift-prone primitives (e1RM,
 * muscle normalization). The scenario tests mirror the Dart engine's own.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

const {
  analyzeTraining,
  estimatedOneRepMax,
  normalizeMuscleGroup,
  personalRecords,
} = require("./workout_analytics");

const REPO_ROOT = path.join(__dirname, "..", "..");
const VECTORS = JSON.parse(fs.readFileSync(
    path.join(REPO_ROOT, "test/fixtures/workout_analytics_vectors.json"),
    "utf8"));

const NOW = new Date("2026-09-02T18:00:00");
const daysAgo = (d) => new Date(NOW.getTime() - d * 24 * 60 * 60 * 1000);

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

// ---- Golden vectors (shared with the Dart suite) --------------------------

test("golden vectors: estimated 1RM matches the Dart engine", () => {
  for (const spec of VECTORS.e1rm) {
    const got = estimatedOneRepMax(spec.weightKg, spec.reps);
    if (spec.expected === null) {
      assert.equal(got, null, JSON.stringify(spec));
    } else {
      assert.ok(Math.abs(got - spec.expected) < 0.001, JSON.stringify(spec));
    }
  }
});

test("golden vectors: muscle normalization matches the Dart engine", () => {
  for (const spec of VECTORS.muscle) {
    assert.equal(
        normalizeMuscleGroup(spec.raw), spec.expected, JSON.stringify(spec));
  }
});

// ---- Warm-ups -------------------------------------------------------------

test("warm-ups are excluded from PRs and volume", () => {
  const s = session("s1", daysAgo(1), [
    ex("bench", [
      set("w1", {reps: 5, weight: 200, type: "warmup"}),
      set("a1", {reps: 8, weight: 100}),
    ]),
  ]);
  const prs = personalRecords([s]).get("bench");
  assert.equal(prs.heaviestWeight.weightKg, 100);
  assert.equal(prs.bestEstimatedStrength.weightKg, 100);
});

// ---- Empty ----------------------------------------------------------------

test("no completed sessions → building, not a guess", () => {
  const analysis = analyzeTraining({sessions: [], now: NOW});
  assert.equal(analysis.completedSessionCount, 0);
  assert.equal(analysis.overallStatus, "building");
  assert.deepEqual(analysis.recentPrs, []);
});

// ---- Progression ----------------------------------------------------------

test("needs 3 appearances before a direction", () => {
  const sessions = [
    session("s1", daysAgo(20), [ex("bench", [set("a", {reps: 8, weight: 100})])]),
    session("s2", daysAgo(10), [ex("bench", [set("a", {reps: 8, weight: 105})])]),
  ];
  const bench = analyzeTraining({sessions, now: NOW})
      .exercises.find((e) => e.exerciseId === "bench");
  assert.equal(bench.appearances, 2);
  assert.equal(bench.status, "building");
});

test("rep-only increase at same weight counts as progression", () => {
  const sessions = [
    session("s1", daysAgo(28), [ex("bench", [set("a", {reps: 8, weight: 100})])]),
    session("s2", daysAgo(21), [ex("bench", [set("a", {reps: 8, weight: 100})])]),
    session("s3", daysAgo(7), [ex("bench", [set("a", {reps: 10, weight: 100})])]),
    session("s4", daysAgo(1), [ex("bench", [set("a", {reps: 10, weight: 100})])]),
  ];
  const bench = analyzeTraining({sessions, now: NOW})
      .exercises.find((e) => e.exerciseId === "bench");
  assert.equal(bench.status, "progressing");
  assert.ok(bench.strengthChangePercent > 0);
});

test("one fewer rep on one day does NOT read as regressing", () => {
  const sessions = [
    session("s1", daysAgo(28), [ex("bench", [set("a", {reps: 8, weight: 100})])]),
    session("s2", daysAgo(21), [ex("bench", [set("a", {reps: 8, weight: 100})])]),
    session("s3", daysAgo(14), [ex("bench", [set("a", {reps: 8, weight: 100})])]),
    session("s4", daysAgo(2), [ex("bench", [set("a", {reps: 7, weight: 100})])]),
  ];
  const bench = analyzeTraining({sessions, now: NOW})
      .exercises.find((e) => e.exerciseId === "bench");
  assert.notEqual(bench.status, "regressing");
});

test("flat across many sessions reads as plateauing", () => {
  const sessions = [];
  for (let i = 5; i >= 1; i--) {
    sessions.push(session(`s${i}`, daysAgo(i * 5),
        [ex("bench", [set("a", {reps: 8, weight: 100})])]));
  }
  const bench = analyzeTraining({sessions, now: NOW})
      .exercises.find((e) => e.exerciseId === "bench");
  assert.equal(bench.status, "plateauing");
});

test("sustained decline reads as regressing", () => {
  const sessions = [
    session("s1", daysAgo(28), [ex("bench", [set("a", {reps: 8, weight: 110})])]),
    session("s2", daysAgo(21), [ex("bench", [set("a", {reps: 8, weight: 108})])]),
    session("s3", daysAgo(7), [ex("bench", [set("a", {reps: 8, weight: 100})])]),
    session("s4", daysAgo(1), [ex("bench", [set("a", {reps: 8, weight: 98})])]),
  ];
  const bench = analyzeTraining({sessions, now: NOW})
      .exercises.find((e) => e.exerciseId === "bench");
  assert.equal(bench.status, "regressing");
  assert.ok(bench.strengthChangePercent < 0);
});

// ---- Volume ---------------------------------------------------------------

test("weekly working volume, warm-ups excluded", () => {
  const sessions = [
    session("s1", daysAgo(10), [ex("bench", [set("a", {reps: 8, weight: 100})])]),
    session("s2", daysAgo(2), [ex("bench", [
      set("w", {reps: 10, weight: 40, type: "warmup"}),
      set("a", {reps: 10, weight: 100}),
    ])]),
  ];
  const {volume} = analyzeTraining({sessions, now: NOW});
  assert.equal(volume.thisWeekKg, 1000);
  assert.equal(volume.lastWeekKg, 800);
  assert.ok(Math.abs(volume.changePercent - 25) < 0.001);
});
