/**
 * The server half of the shared coaching vectors, plus the rules' own
 * behaviour.
 *
 * `test/fixtures/coaching_vectors.json` is run by BOTH this file and
 * `test/diet/coaching_rules_test.dart`. The engine decides what the coach
 * says; two implementations of that decision disagreeing means the app and the
 * coach recommend different things from the same data.
 *
 * Half of these assert the NEGATIVES. A rules engine is defined as much by
 * what it stays quiet about, and "generic nagging" is exactly the failure mode
 * this replaces.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

const {buildDietState} = require("./state");
const {coachingFindings, MAX_FINDINGS} = require("./rules");

const REPO_ROOT = path.join(__dirname, "..", "..");
const VECTORS = JSON.parse(fs.readFileSync(
    path.join(REPO_ROOT, "test/fixtures/coaching_vectors.json"), "utf8"));

/**
 * @param {!Object} spec A vector case's `input`.
 * @return {!Object}
 */
function stateFor(spec) {
  return buildDietState({
    dayKey: "2026-08-30",
    weekday: 7,
    targets: spec.targets,
    planName: "Cut",
    day: spec.day,
    consumedMealIds: new Set(spec.consumedMealIds),
    log: spec.log,
    energy: spec.energy || null,
  });
}

const targets = (patch) => ({
  goal: "fatLoss", calories: 2200, proteinG: 160, carbsG: 250, fatG: 73,
  source: "manual", ...patch,
});

const entry = (patch) => ({
  id: "e1", foodId: "usda:1", foodName: "Food",
  quantity: 100, unit: "g", grams: 100,
  kcal: 500, proteinG: 20, carbsG: 40, fatG: 15,
  source: "usdaFdc", sourceRef: "1", origin: "logged",
  estimated: false, mealId: null, ...patch,
});

/**
 * @param {!Object} patch
 * @param {?number=} hour
 * @return {!Array<Object>}
 */
function findingsFor(patch, hour) {
  return coachingFindings(stateFor({
    targets: targets({}), day: VECTORS.planDay,
    consumedMealIds: [], log: [],
    ...patch,
  }), hour);
}

const codes = (findings) => findings.map((f) => f.code);

test("golden vectors: every case produces the same findings", () => {
  for (const spec of VECTORS.cases) {
    const findings = coachingFindings(stateFor(spec.input), spec.localHour);
    assert.deepEqual(findings, spec.expected, spec.name);
  }
});

test("no turn is handed more than three findings", () => {
  // A coach who lists six things has told you nothing.
  for (const spec of VECTORS.cases) {
    const findings = coachingFindings(stateFor(spec.input), spec.localHour);
    assert.ok(findings.length <= MAX_FINDINGS, spec.name);
  }
});

test("every finding names the state it rests on", () => {
  // "Why is this being said?" has to be answerable, not asserted.
  for (const spec of VECTORS.cases) {
    const found = coachingFindings(stateFor(spec.input), spec.localHour);
    for (const finding of found) {
      assert.ok(finding.evidence.length > 0, finding.code);
      assert.ok(finding.text.length > 0, finding.code);
      assert.ok(
          ["observation", "analysis", "recommendation", "warning",
            "encouragement", "clarification"].includes(finding.kind),
          `${finding.code}: ${finding.kind}`);
    }
  }
});

test("a target below the safety floor always survives the cap", () => {
  // The one finding that must never be crowded out by progress notes.
  const findings = findingsFor({
    targets: targets({calories: 900}),
    log: [entry({})],
  }, 12);
  assert.equal(findings[0].code, "target_below_safety_floor");
  assert.equal(findings[0].kind, "warning");
  assert.equal(findings[0].severity, "urgent");
});

// ── The negatives: what the engine must NOT say ──────────────────────────

test("a met protein target produces encouragement and NO shortfall", () => {
  const findings = findingsFor({
    log: [entry({kcal: 1900, proteinG: 175})],
  }, 19);
  assert.ok(codes(findings).includes("protein_met"));
  assert.ok(!codes(findings).includes("protein_shortfall"));
});

test("a protein gap early in the day stays quiet", () => {
  // There is a whole day left to close it. Saying so would be the generic
  // nagging this engine exists to replace.
  const findings = findingsFor({
    log: [entry({kcal: 400, proteinG: 25})],
  }, 9);
  assert.ok(!codes(findings).includes("protein_shortfall"));
});

test("the same gap fires once the calorie budget is running out", () => {
  const findings = findingsFor({
    log: [entry({kcal: 1850, proteinG: 125})],
  }, 19);
  const shortfall = findings.find((f) => f.code === "protein_shortfall");
  assert.ok(shortfall);
  assert.equal(shortfall.kind, "recommendation");
  // The recommendation carries its own reason and the budget it has to work
  // within — that is the difference between coaching and a slogan.
  assert.match(shortfall.text, /35g short of the 160g protein target/);
  assert.match(shortfall.text, /350 kcal left/);
});

test("a trivial protein gap is inside the noise and is not raised", () => {
  const findings = findingsFor({
    log: [entry({kcal: 2100, proteinG: 150})],
  }, 20);
  assert.ok(!codes(findings).includes("protein_shortfall"));
});

test("an empty day produces no overshoot and no shortfall", () => {
  const findings = findingsFor({}, 12);
  assert.deepEqual(codes(findings), ["nothing_logged"]);
  assert.ok(!codes(findings).includes("calories_over_target"));
  assert.ok(!codes(findings).includes("protein_shortfall"));
  assert.ok(!codes(findings).includes("protein_met"));
});

test("an empty log is never reported as 'you haven't eaten'", () => {
  const morning = findingsFor({}, 9);
  const evening = findingsFor({}, 21);
  assert.equal(morning[0].severity, "info");
  assert.equal(evening[0].severity, "notable");
  for (const set of [morning, evening]) {
    assert.match(set[0].text, /logged/);
    assert.doesNotMatch(set[0].text, /you haven't eaten/i);
  }
});

test("with no targets, only the blocker fires — no invented analysis", () => {
  const findings = findingsFor({targets: null, log: [entry({})]}, 14);
  assert.deepEqual(codes(findings), ["targets_unset"]);
});

test("time-dependent rules stay quiet when the hour is unknown", () => {
  const findings = findingsFor({}, null);
  assert.equal(findings[0].code, "nothing_logged");
  assert.equal(findings[0].severity, "info");
});

test("an untracked macro is named so nobody is told they're over on it", () => {
  const findings = findingsFor({
    targets: targets({carbsG: null, fatG: null}),
    log: [entry({})],
  }, 14);
  const untracked = findings.find((f) => f.code === "untracked_macros");
  assert.ok(untracked);
  assert.match(untracked.text, /carbs, fat/);
});
