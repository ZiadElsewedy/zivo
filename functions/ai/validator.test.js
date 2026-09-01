/**
 * Offline tests for the advice validator + safety intercept (`./validator.js`,
 * Diet Coach Phase 7). Pure: a reply string + a diet-payload context in, an
 * outcome out. No model, no store.
 *
 * The non-firing tests matter as much as the firing ones — the whole design
 * bets on precision, because a false rejection replaces a good specific reply
 * with terser deterministic text.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {validateAdvice, SAFETY_MESSAGE} = require("./validator");

// A representative diet payload: a fat-loss target, a real logged day, protein
// tracked but carbs/fat not, and the findings the rules engine produced.
const CTX = {
  date: "2026-08-17",
  targets: {
    goal: "fatLoss", calories: 2200, proteinG: 160,
    carbsG: null, fatG: null, source: "manual",
  },
  consumed: {
    kcal: 1180, proteinG: 90, carbsG: 120, fatG: 35,
    basis: "logged", basisLabel: "logged by you",
    estimated: false, entryCount: 2, loggedCount: 2,
  },
  remaining: {kcal: 1020, proteinG: 70, carbsG: null, fatG: null},
  findings: [
    {
      code: "calories_consumed", kind: "observation", severity: "info",
      text: "1,180 of 2,200 kcal so far (logged by you).",
      evidence: ["consumed.kcal", "targets.calories"],
    },
    {
      code: "protein_shortfall", kind: "recommendation", severity: "important",
      text: "70g short of the 160g protein target, with 1020 kcal left. A " +
        "lean protein source closes most of that gap.",
      evidence: ["remaining.proteinG"],
    },
  ],
  quality: {
    targetsUnset: false, noPlanForDay: false, nothingLogged: false,
    consumedIsAssumed: false, hasEstimatedValues: false,
    untrackedMacros: ["carbs", "fat"],
  },
  plannedKcal: null,
  meals: [],
  logEntries: [
    {food: "Chicken breast", kcal: 330}, {food: "Rice", kcal: 195},
  ],
  history: {days: 7, daysWithLog: 3, averageKcal: null},
};

test("no context (no diet tool used) always passes", () => {
  const r = validateAdvice("You've eaten a wild 9,000 calories.", null);
  assert.equal(r.ok, true);
});

test("an accurate reply passes untouched", () => {
  const r = validateAdvice(
      "You're at about 1,180 calories so far, so you've got roughly 1,020 " +
      "left against your 2,200 target. Protein's a touch behind.", CTX);
  assert.equal(r.ok, true);
  assert.equal(r.replacement, null);
});

test("a consumed figure the state can't account for is rejected", () => {
  const r = validateAdvice(
      "Nice work — you've eaten about 1,850 calories today.", CTX);
  assert.equal(r.ok, false);
  assert.equal(r.safe, true);
  assert.equal(r.violations[0].code, "numeric_contradiction");
  // Falls back to the findings' own correct sentences.
  assert.match(r.replacement, /1,180 of 2,200/);
});

test("a wrong 'calories left' figure is rejected", () => {
  const r = validateAdvice("You've got 300 calories left for today.", CTX);
  assert.equal(r.ok, false);
  assert.equal(r.violations[0].code, "numeric_contradiction");
});

test("a component figure the coach may cite (a logged food) passes", () => {
  // 330 and 195 are the logged foods; naming them is coaching, not invention.
  const r = validateAdvice(
      "The chicken breast (330) and rice (195) are what put you at 1,180 so " +
      "far.", CTX);
  assert.equal(r.ok, true);
});

test("a general-knowledge per-100g fact is not treated as a day claim", () => {
  const r = validateAdvice(
      "For reference, chicken breast is about 165 calories per 100g.", CTX);
  assert.equal(r.ok, true);
});

test("a hypothetical projection is not checked against the day's totals", () => {
  const r = validateAdvice(
      "If you added a protein shake you'd be at around 1,500 calories, still " +
      "under target.", CTX);
  assert.equal(r.ok, true);
});

test("claiming the user ate, when nothing is logged, is rejected", () => {
  const empty = {
    ...CTX,
    consumed: {
      kcal: 0, proteinG: 0, carbsG: 0, fatG: 0,
      basis: "nothingLogged", basisLabel: "nothing logged yet",
      estimated: false, entryCount: 0, loggedCount: 0,
    },
    remaining: {kcal: 2200, proteinG: 160, carbsG: null, fatG: null},
    logEntries: [],
    findings: [{
      code: "nothing_logged", kind: "clarification", severity: "info",
      text: "Nothing's logged yet today, so there's nothing to read into the " +
        "zero.", evidence: ["quality.nothingLogged"],
    }],
    quality: {...CTX.quality, nothingLogged: true},
  };
  const r = validateAdvice(
      "Great day — you've eaten really well and hit your protein.", empty);
  assert.equal(r.ok, false);
  assert.equal(r.violations[0].code, "ate_but_nothing_logged");
  assert.match(r.replacement, /Nothing's logged/);
});

test("calling the user over/under on an untracked macro is rejected", () => {
  const r = validateAdvice(
      "You're running a bit over on carbs today, ease off the rice.", CTX);
  assert.equal(r.ok, false);
  assert.equal(r.violations[0].code, "untracked_macro_claim");
});

test("advice on a TRACKED macro is fine (protein has a target here)", () => {
  const r = validateAdvice(
      "You're a little under on protein — a lean source would help.", CTX);
  assert.equal(r.ok, true);
});

test("a target figure that isn't the user's set target is rejected", () => {
  const r = validateAdvice(
      "You're comfortably under your 1,800 calorie goal.", CTX);
  assert.equal(r.ok, false);
  assert.equal(r.violations[0].code, "numeric_contradiction");
});

test("referencing a target when none is set is rejected", () => {
  const noTarget = {
    ...CTX,
    targets: null,
    remaining: null,
    quality: {
      ...CTX.quality, targetsUnset: true,
      untrackedMacros: ["protein", "carbs", "fat"],
    },
    findings: [{
      code: "targets_unset", kind: "clarification", severity: "important",
      text: "No daily target is set, so there's nothing to measure today " +
        "against.", evidence: ["quality.targetsUnset"],
    }],
  };
  const r = validateAdvice(
      "You're well under your 2,000 calorie goal for the day.", noTarget);
  assert.equal(r.ok, false);
  assert.equal(r.violations[0].code, "target_but_unset");
  assert.match(r.replacement, /No daily target is set/);
});

// --- safety intercept -------------------------------------------------------

test("recommending a sub-floor calorie intake is intercepted", () => {
  const r = validateAdvice(
      "To speed up fat loss, aim for around 900 calories a day.", CTX);
  assert.equal(r.ok, false);
  assert.equal(r.safe, false);
  assert.equal(r.violations[0].code, "unsafe_low_calorie_advice");
  assert.equal(r.replacement, SAFETY_MESSAGE);
});

test("'eat only 800 calories' is intercepted", () => {
  const r = validateAdvice(
      "Honestly, just eat 800 calories and you'll drop weight fast.", CTX);
  assert.equal(r.ok, false);
  assert.equal(r.safe, false);
});

test("WARNING about a sub-floor number is not mistaken for recommending it",
    () => {
      // Relaying the safety finding cites 1000 and 1200 in a warning context —
      // that is the coach doing its job, not prescribing a starvation diet.
      const subFloor = {
        ...CTX,
        targets: {...CTX.targets, calories: 1000},
        remaining: {kcal: -180, proteinG: 70, carbsG: null, fatG: null},
        findings: [{
          code: "target_below_safety_floor", kind: "warning", severity: "urgent",
          text: "The daily target is set to 1000 kcal, below the 1200 kcal " +
            "floor ZIVO will coach to.", evidence: ["targets.calories"],
        }],
      };
      const r = validateAdvice(
          "Heads up: your target is set to 1,000 kcal, which is below the " +
          "1,200 floor ZIVO coaches to — worth checking with a doctor first.",
          subFloor);
      assert.equal(r.ok, true);
    });

test("an empty reply passes (nothing to validate)", () => {
  assert.equal(validateAdvice("", CTX).ok, true);
  assert.equal(validateAdvice("   ", CTX).ok, true);
});
