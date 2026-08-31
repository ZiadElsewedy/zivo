#!/usr/bin/env node
/**
 * Generates `test/fixtures/coaching_vectors.json` — the shared golden vectors
 * for the coaching rules engine.
 *
 * The engine decides what the coach says; the model only phrases it. Two
 * implementations of that decision (Dart for the app, JS for the server) must
 * agree exactly, or the app and the coach recommend different things from the
 * same data. Both suites run this fixture.
 *
 * The cases deliberately include the NEGATIVES — a met protein target must
 * produce no shortfall, an empty day must produce no overshoot — because a
 * rules engine is defined as much by what it stays quiet about.
 *
 * Usage: node scripts/nutrition/build_coaching_vectors.js
 */

const fs = require("node:fs");
const {buildDietState} = require("../../functions/diet/state");
const {coachingFindings} = require("../../functions/diet/rules");

const PLAN_DAY = {
  label: "Every day",
  meals: [
    {
      id: "m1-breakfast",
      label: "Breakfast",
      items: [{name: "Oats", quantity: 60, unit: "g", calories: 220,
        proteinG: 8, carbsG: 38, fatG: 4, estimated: true}],
    },
    {
      id: "m2-lunch",
      label: "Lunch",
      items: [{name: "Chicken", quantity: 200, unit: "g", calories: 330,
        proteinG: 62, carbsG: 0, fatG: 7}],
    },
  ],
};

/** @param {!Object} patch @return {!Object} */
const targets = (patch) => ({
  goal: "fatLoss", calories: 2200, proteinG: 160, carbsG: 250, fatG: 73,
  source: "manual", ...patch,
});

/** @param {!Object} patch @return {!Object} */
const entry = (patch) => ({
  id: "e1", foodId: "usda:1", foodName: "Food",
  quantity: 100, unit: "g", grams: 100,
  kcal: 500, proteinG: 20, carbsG: 40, fatG: 15,
  source: "usdaFdc", sourceRef: "1", origin: "logged",
  estimated: false, mealId: null, ...patch,
});

const CASES = [
  {
    name: "a low target outranks everything else",
    localHour: 12,
    input: {targets: targets({calories: 900}), day: PLAN_DAY,
      consumedMealIds: [], log: [entry({})]},
  },
  {
    name: "no targets: the blocker is the coaching",
    localHour: 12,
    input: {targets: null, day: PLAN_DAY, consumedMealIds: [], log: [entry({})]},
  },
  {
    name: "nothing logged in the morning is unremarkable",
    localHour: 9,
    input: {targets: targets({}), day: PLAN_DAY, consumedMealIds: [], log: []},
  },
  {
    name: "nothing logged in the evening is worth a nudge",
    localHour: 21,
    input: {targets: targets({}), day: PLAN_DAY, consumedMealIds: [], log: []},
  },
  {
    name: "the worked example: protein short with the budget running out",
    localHour: 19,
    input: {
      targets: targets({}), day: PLAN_DAY, consumedMealIds: [],
      log: [entry({kcal: 1850, proteinG: 125, carbsG: 200, fatG: 60})],
    },
  },
  {
    name: "the same protein gap early in the day stays quiet",
    localHour: 9,
    input: {
      targets: targets({}), day: PLAN_DAY, consumedMealIds: [],
      log: [entry({kcal: 400, proteinG: 25, carbsG: 40, fatG: 12})],
    },
  },
  {
    name: "protein met produces encouragement and NO shortfall",
    localHour: 19,
    input: {
      targets: targets({}), day: PLAN_DAY, consumedMealIds: [],
      log: [entry({kcal: 1900, proteinG: 175, carbsG: 200, fatG: 60})],
    },
  },
  {
    name: "over target is named, never clamped away",
    localHour: 20,
    input: {
      targets: targets({}), day: PLAN_DAY, consumedMealIds: [],
      log: [entry({kcal: 2500, proteinG: 170, carbsG: 260, fatG: 90})],
    },
  },
  {
    name: "a day of ticked meals is flagged as assumed, not measured",
    localHour: 14,
    input: {
      targets: targets({}), day: PLAN_DAY, consumedMealIds: ["m1-breakfast"],
      log: [],
    },
  },
  {
    name: "untracked macros are named so nobody is told they're over on them",
    localHour: 14,
    input: {
      targets: targets({proteinG: 160, carbsG: null, fatG: null}),
      day: PLAN_DAY, consumedMealIds: [], log: [entry({})],
    },
  },
  {
    name: "an unknown hour: time-dependent rules stay quiet",
    localHour: null,
    input: {targets: targets({}), day: PLAN_DAY, consumedMealIds: [], log: []},
  },
  {
    name: "a fat-loss target ABOVE maintenance is called out",
    localHour: 12,
    input: {
      targets: targets({calories: 3000}), day: PLAN_DAY,
      consumedMealIds: [], log: [entry({})],
      energy: {maintenanceKcal: 2500, source: "estimated"},
    },
  },
  {
    name: "a muscle-gain target BELOW maintenance is called out too",
    localHour: 12,
    input: {
      targets: targets({goal: "muscleGain", calories: 2100}), day: PLAN_DAY,
      consumedMealIds: [], log: [entry({})],
      energy: {maintenanceKcal: 2800, source: "measured"},
    },
  },
  {
    name: "a target that serves its goal draws no objection",
    localHour: 12,
    input: {
      targets: targets({calories: 2100}), day: PLAN_DAY,
      consumedMealIds: [], log: [entry({})],
      energy: {maintenanceKcal: 2800, source: "measured"},
    },
  },
  {
    name: "a target sitting ON maintenance disagrees with a fat-loss goal",
    localHour: 12,
    input: {
      targets: targets({calories: 2520}), day: PLAN_DAY,
      consumedMealIds: [], log: [entry({})],
      energy: {maintenanceKcal: 2500, source: "stated"},
    },
  },
  {
    name: "a maintain goal at maintenance is exactly right, and stays quiet",
    localHour: 12,
    input: {
      targets: targets({goal: "maintain", calories: 2520}), day: PLAN_DAY,
      consumedMealIds: [], log: [entry({})],
      energy: {maintenanceKcal: 2500, source: "stated"},
    },
  },
  {
    name: "with no body data the objection cannot be made, so it isn't",
    localHour: 12,
    input: {
      targets: targets({calories: 3000}), day: PLAN_DAY,
      consumedMealIds: [], log: [entry({})],
    },
  },
];

function main() {
  const cases = CASES.map((spec) => {
    const state = buildDietState({
      dayKey: "2026-08-30",
      weekday: 7,
      targets: spec.input.targets,
      planName: "Cut",
      day: spec.input.day,
      consumedMealIds: new Set(spec.input.consumedMealIds),
      log: spec.input.log,
      energy: spec.input.energy || null,
    });
    return {
      ...spec,
      expected: coachingFindings(state, spec.localHour),
    };
  });

  const vectors = {
    schemaVersion: 1,
    note:
      "Golden vectors for the coaching rules engine. Run by BOTH flutter " +
      "test and node --test; regenerate with " +
      "scripts/nutrition/build_coaching_vectors.js. Cases deliberately " +
      "include the negatives: a rules engine is defined as much by what it " +
      "stays quiet about.",
    planDay: PLAN_DAY,
    cases,
  };

  fs.writeFileSync(
      "test/fixtures/coaching_vectors.json",
      `${JSON.stringify(vectors, null, 2)}\n`,
  );
  process.stdout.write(
      `test/fixtures/coaching_vectors.json\n  cases: ${cases.length}\n`);
}

if (require.main === module) main();
