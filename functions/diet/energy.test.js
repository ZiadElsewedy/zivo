/**
 * Offline vector tests for `./energy.js`. The Dart suite runs the SAME fixture
 * (`test/diet/energy_vectors_test.dart`) — if either implementation drifts,
 * the other's test fails.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

const {calibrateMaintenance, energyFor} = require("./energy");

const REPO_ROOT = path.join(__dirname, "..", "..");
const VECTORS = JSON.parse(fs.readFileSync(
    path.join(REPO_ROOT, "test/fixtures/energy_vectors.json"), "utf8"));

test("golden vectors: every calibration case measures the same", () => {
  for (const spec of VECTORS.calibration) {
    assert.deepEqual(
        calibrateMaintenance(spec.input), spec.expected, spec.name);
  }
});

test("golden vectors: every maintenance case resolves the same", () => {
  for (const spec of VECTORS.energy) {
    assert.deepEqual(energyFor(spec.input), spec.expected, spec.name);
  }
});

test("the precedence is stated over measured over estimated", () => {
  const profile = {
    heightCm: 178, sex: "male", activity: "moderate",
    statedMaintenanceKcal: 2700,
  };
  assert.equal(
      energyFor({profile, weightKg: 82, age: 30,
        measuredMaintenanceKcal: 2950}).source,
      "stated");
  assert.equal(
      energyFor({profile: {...profile, statedMaintenanceKcal: null},
        weightKg: 82, age: 30, measuredMaintenanceKcal: 2950}).source,
      "measured");
  assert.equal(
      energyFor({profile: {...profile, statedMaintenanceKcal: null},
        weightKg: 82, age: 30, measuredMaintenanceKcal: null}).source,
      "estimated");
});
