/**
 * Offline tests for the Node readiness engine (`./readiness.js`) — the mirror
 * of the pure combination layer in
 * `lib/features/readiness/domain/readiness.dart` (`readinessFromSignals`).
 *
 * The golden-vector test loads `test/fixtures/readiness_vectors.json`, the SAME
 * file the Dart suite runs, so the Today card and the AI coach can never phrase
 * the same call two different ways. Change one engine and the other fails until
 * they agree.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

const {readinessFromSignals, readinessDeloadDueFrom} = require("./readiness");

const REPO_ROOT = path.join(__dirname, "..", "..");
const VECTORS = JSON.parse(fs.readFileSync(
    path.join(REPO_ROOT, "test/fixtures/readiness_vectors.json"),
    "utf8"));

/** Serialise a factor to the vector's canonical shape (present fields only). */
function serializeFactor(f) {
  const out = {kind: f.kind, direction: f.direction};
  if (f.sleepDurationMinutes !== undefined) {
    out.sleepDurationMinutes = f.sleepDurationMinutes;
  }
  if (f.sleepDeltaMinutes !== undefined) {
    out.sleepDeltaMinutes = f.sleepDeltaMinutes;
  }
  if (f.deloadExerciseCount !== undefined) {
    out.deloadExerciseCount = f.deloadExerciseCount;
  }
  if (f.restDays !== undefined) out.restDays = f.restDays;
  if (f.weightChangeKg !== undefined) out.weightChangeKg = f.weightChangeKg;
  return out;
}

test("golden vectors: every case matches the shared engine", () => {
  for (const vec of VECTORS.cases) {
    const result = readinessFromSignals(vec.input);
    if (vec.expected === null) {
      assert.equal(result, null, `${vec.name}: expected the gate`);
      continue;
    }
    const got = {
      verdict: result.verdict,
      factors: result.factors.map(serializeFactor),
    };
    assert.deepEqual(got, vec.expected, vec.name);
  }
});

test("the deload predicate reads the workout verdicts", () => {
  assert.equal(readinessDeloadDueFrom(2, false), true);
  assert.equal(readinessDeloadDueFrom(0, true), true);
  assert.equal(readinessDeloadDueFrom(1, false), false);
});
