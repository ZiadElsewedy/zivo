/**
 * Offline tests for the Node training-day engine (`./training_days.js`) — the
 * mirror of `lib/features/workout/domain/training_days.dart`.
 *
 * The golden-vector test loads `test/fixtures/training_days_vectors.json`, the
 * SAME file the Dart suite runs, so the Today card and the AI coach can never
 * disagree about what was planned and what happened.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

const {
  classifyTrainingDayRecords,
  summarizeTrainingDays,
  nextWorkoutDay,
} = require("./training_days");

const REPO_ROOT = path.join(__dirname, "..", "..", "..");
const VECTORS = JSON.parse(fs.readFileSync(
    path.join(REPO_ROOT, "test/fixtures/training_days_vectors.json"),
    "utf8"));

test("golden vectors: every case matches the shared engine", () => {
  assert.ok(VECTORS.cases.length > 0);
  for (const vec of VECTORS.cases) {
    const records = classifyTrainingDayRecords(vec.input);
    assert.deepEqual(
        records.map((r) => ({day: r.day, planned: r.planned,
          outcome: r.outcome, dueDayId: r.dueDayId})),
        vec.expected.records, `${vec.name}: records`);
    assert.deepEqual(summarizeTrainingDays(vec.input.plan, records),
        vec.expected.summary, `${vec.name}: summary`);
  }
});

test("the next workout never lands on a rest slot", () => {
  const days = [
    {id: "a", order: 0},
    {id: "r", order: 1, type: "rest"},
    {id: "b", order: 2},
  ];
  assert.equal(nextWorkoutDay(days, 1).id, "b");
  assert.equal(nextWorkoutDay([{id: "r", order: 0, type: "rest"}], 0), null);
});

test("a plan with no workouts classifies nothing", () => {
  assert.deepEqual(classifyTrainingDayRecords({
    plan: {createdDay: "2026-09-01", cycleCursor: 0,
      days: [{id: "r", order: 0, type: "rest"}]},
    trainedDayIds: {}, userRestDays: [], from: "2026-09-01",
    today: "2026-09-03",
  }), []);
});
