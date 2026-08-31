#!/usr/bin/env node
/**
 * Generates `test/fixtures/energy_vectors.json` — the shared golden vectors
 * for the maintenance calculation and its calibration.
 *
 * The Diet screen computes what the user burns in Dart; the coach computes it
 * in JavaScript. If the two ever disagree, the app tells someone their target
 * is 300 kcal over maintenance while the coach congratulates them for hitting
 * it. Both suites run this fixture, so a change to one side fails the other
 * until they agree again.
 *
 * Expectations are produced by the JS implementation and asserted by both.
 *
 * Usage: node scripts/nutrition/build_energy_vectors.js
 */

const fs = require("node:fs");
const {calibrateMaintenance, energyFor} = require("../../functions/diet/energy");

/** A day's intake, `daysAgo` before the anchor date. */
const DAY_MS = 24 * 60 * 60 * 1000;
const ANCHOR = Date.UTC(2026, 7, 31); // 2026-08-31

/**
 * @param {number} count
 * @param {number} kcal
 * @param {number} startDaysAgo
 * @return {!Array<Object>}
 */
function intake(count, kcal, startDaysAgo) {
  const out = [];
  for (let i = 0; i < count; i++) {
    const ms = ANCHOR - (startDaysAgo - i) * DAY_MS;
    const d = new Date(ms);
    const pad = (n, w) => String(n).padStart(w, "0");
    out.push({
      dayKey: `${pad(d.getUTCFullYear(), 4)}-${pad(d.getUTCMonth() + 1, 2)}-` +
        `${pad(d.getUTCDate(), 2)}`,
      kcal,
    });
  }
  return out;
}

/**
 * @param {number} weightKg
 * @param {number} daysAgo
 * @return {!Object}
 */
const weighIn = (weightKg, daysAgo) => ({
  weightKg,
  loggedAtMs: ANCHOR - daysAgo * DAY_MS,
});

const CALIBRATION_CASES = [
  {
    name: "gaining: maintenance is below what they ate",
    input: {weighIns: [weighIn(82, 28), weighIn(82.8, 0)],
      intake: intake(28, 2600, 28)},
  },
  {
    name: "losing: maintenance is above what they ate",
    input: {weighIns: [weighIn(82, 28), weighIn(81, 0)],
      intake: intake(28, 2000, 28)},
  },
  {
    name: "steady: maintenance is what they ate",
    input: {weighIns: [weighIn(82, 28), weighIn(82, 0)],
      intake: intake(28, 2450, 28)},
  },
  {
    name: "one weigh-in measures nothing",
    input: {weighIns: [weighIn(82, 0)], intake: intake(28, 2600, 28)},
  },
  {
    name: "a fortnight is the floor; ten days is water weight",
    input: {weighIns: [weighIn(82, 10), weighIn(81.2, 0)],
      intake: intake(11, 2600, 10)},
  },
  {
    name: "a half-logged window is refused",
    input: {weighIns: [weighIn(82, 28), weighIn(82.8, 0)],
      intake: intake(12, 2600, 28)},
  },
  {
    name: "logging outside the window doesn't count toward it",
    input: {weighIns: [weighIn(82, 20), weighIn(82.5, 0)],
      intake: intake(30, 2600, 60)},
  },
  {
    name: "the widest pair of weigh-ins defines the window",
    input: {
      weighIns: [weighIn(82, 28), weighIn(82.5, 14), weighIn(82.8, 0)],
      intake: intake(28, 2600, 28),
    },
  },
];

const PROFILE = {
  heightCm: 178, sex: "male", activity: "moderate",
  statedMaintenanceKcal: null,
};

const ENERGY_CASES = [
  {
    name: "the equation, when there is nothing better",
    input: {profile: PROFILE, weightKg: 82, age: 30,
      measuredMaintenanceKcal: null},
  },
  {
    name: "a measurement replaces the equation",
    input: {profile: PROFILE, weightKg: 82, age: 30,
      measuredMaintenanceKcal: 2950},
  },
  {
    name: "what the user stated outranks the measurement",
    input: {profile: {...PROFILE, statedMaintenanceKcal: 2700},
      weightKg: 82, age: 30, measuredMaintenanceKcal: 2950},
  },
  {
    name: "no body profile: no maintenance, and no guess",
    input: {profile: null, weightKg: 82, age: 30,
      measuredMaintenanceKcal: null},
  },
  {
    name: "a profile with no weigh-in cannot run the equation",
    input: {profile: PROFILE, weightKg: null, age: 30,
      measuredMaintenanceKcal: null},
  },
  {
    name: "activity level moves the figure",
    input: {profile: {...PROFILE, activity: "athlete"}, weightKg: 82, age: 30,
      measuredMaintenanceKcal: null},
  },
];

function main() {
  const vectors = {
    schemaVersion: 1,
    note:
      "Golden vectors for the maintenance calculation and its calibration. " +
      "Run by BOTH flutter test and node --test; regenerate with " +
      "scripts/nutrition/build_energy_vectors.js. The coach and the Diet " +
      "screen must reach the same figure for the same person.",
    anchorMs: ANCHOR,
    calibration: CALIBRATION_CASES.map((spec) => ({
      ...spec,
      expected: calibrateMaintenance(spec.input),
    })),
    energy: ENERGY_CASES.map((spec) => ({
      ...spec,
      expected: energyFor(spec.input),
    })),
  };

  fs.writeFileSync(
      "test/fixtures/energy_vectors.json",
      `${JSON.stringify(vectors, null, 2)}\n`,
  );
  process.stdout.write(
      `test/fixtures/energy_vectors.json\n` +
      `  calibration cases: ${vectors.calibration.length}\n` +
      `  energy cases:      ${vectors.energy.length}\n`);
}

if (require.main === module) main();
