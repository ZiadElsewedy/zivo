/**
 * The server half of the shared diet-state vectors.
 *
 * `test/fixtures/diet_state_vectors.json` is run by BOTH this file and
 * `test/diet/diet_state_test.dart`. The Diet screen renders a state built in
 * Dart; the coach reads one built here. Change either implementation and the
 * other's test fails until they agree again — which is the point
 * (docs/DIET_COACH_AUDIT.md, T13).
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

const {buildDietState, isSupplement, mealCalories} = require("./state");
const {resolveDietDay} = require("../ai/dates");

const REPO_ROOT = path.join(__dirname, "..", "..");
const VECTORS = JSON.parse(fs.readFileSync(
    path.join(REPO_ROOT, "test/fixtures/diet_state_vectors.json"), "utf8"));

test("golden vectors: every state case rebuilds exactly", () => {
  for (const spec of VECTORS.cases) {
    const state = buildDietState({
      ...spec.input,
      consumedMealIds: new Set(spec.input.consumedMealIds),
    });
    assert.deepEqual(state, spec.expected, spec.name);
  }
});

test("golden vectors: the plan-day resolver agrees for every weekday", () => {
  // `dayForDate` (Dart) and `resolveDietDay` (JS) are separate implementations
  // of one rule. A disagreement means the screen and the coach are looking at
  // different days of the plan.
  for (const spec of VECTORS.resolutions) {
    const days = VECTORS.plans[spec.plan];
    const date = new Date(`${spec.dayKey}T12:00:00Z`);
    const resolved = resolveDietDay(days, date, 0);
    assert.equal(
        (resolved || {}).label || null,
        spec.expectedLabel,
        `${spec.plan} on ${spec.dayKey}`,
    );
  }
});

test("an empty log is 'nothing logged', never a measured zero", () => {
  // The distinction that stops a coach telling someone to eat when they have.
  const state = buildDietState({
    dayKey: "2026-08-30", weekday: 7,
    targets: {goal: "fatLoss", calories: 2000, proteinG: null,
      carbsG: null, fatG: null, source: "manual"},
    planName: "Cut", day: VECTORS.planDay,
    consumedMealIds: new Set(), log: [],
  });
  assert.equal(state.consumed.basis, "nothingLogged");
  assert.equal(state.quality.nothingLogged, true);
  assert.equal(state.quality.consumedIsAssumed, false);
  assert.match(state.consumed.basisLabel, /nothing logged/);
});

test("supplements are tracked but never counted", () => {
  const state = buildDietState({
    dayKey: "2026-08-30", weekday: 7, targets: null,
    planName: "Cut", day: VECTORS.planDay,
    consumedMealIds: new Set(["m3-supplements"]), log: [],
  });
  // Present in the meal list...
  assert.ok(state.meals.some((m) => m.id === "m3-supplements" && m.isSupplement));
  // ...but not in the counts or the budget.
  assert.equal(state.mealsTotal, 2);
  assert.equal(state.mealsEaten, 0);
  assert.equal(state.consumed.kcal, 0);
  assert.equal(state.plannedKcal, 760);
});

test("a plan's own sum is reported apart from the user's target", () => {
  // Conflating them is how a coach ends up coaching against a number nobody
  // chose.
  const state = buildDietState({
    dayKey: "2026-08-30", weekday: 7,
    targets: {goal: "fatLoss", calories: 2200, proteinG: null,
      carbsG: null, fatG: null, source: "manual"},
    planName: "Cut", day: VECTORS.planDay,
    consumedMealIds: new Set(), log: [],
  });
  assert.equal(state.targets.calories, 2200);
  assert.equal(state.plannedKcal, 760);
});

test("untracked macros are listed rather than silently zeroed", () => {
  const state = buildDietState({
    dayKey: "2026-08-30", weekday: 7,
    targets: {goal: "maintain", calories: 2000, proteinG: 150,
      carbsG: null, fatG: null, source: "manual"},
    planName: null, day: null, consumedMealIds: new Set(), log: [],
  });
  assert.deepEqual(state.quality.untrackedMacros, ["carbs", "fat"]);
  assert.equal(state.remaining.proteinG, 150);
  assert.equal(state.remaining.carbsG, null);
  assert.equal(state.remaining.fatG, null);
});

test("meal helpers match the Dart rules they mirror", () => {
  assert.equal(isSupplement({label: "Supplements"}), true);
  assert.equal(isSupplement({label: "daily supplement stack"}), true);
  assert.equal(isSupplement({label: "Lunch"}), false);
  // Absent, not zero.
  assert.equal(mealCalories({items: [{name: "x"}]}), null);
  assert.equal(mealCalories({items: [{calories: 10}, {name: "x"}]}), 10);
});
