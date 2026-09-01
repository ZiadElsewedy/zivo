#!/usr/bin/env node
/**
 * Generates `test/fixtures/diet_state_vectors.json` — the shared golden
 * vectors for the diet-state builder and the plan-day resolver.
 *
 * The Diet screen renders a `DietState` built in Dart; the coach is handed one
 * built in JavaScript. Two implementations agreeing by comment discipline is
 * not a guarantee. This fixture is: both suites run it, so changing one side
 * fails the other until they match again (docs/DIET_COACH_AUDIT.md, T13).
 *
 * Expectations are produced by the JS implementation and asserted by both.
 *
 * Usage: node scripts/nutrition/build_state_vectors.js
 */

const fs = require("node:fs");
const {buildDietState} = require("../../functions/diet/state");
const {resolveDietDay, isoWeekday, dayKeyFor} = require("../../functions/ai/dates");

const PLAN_DAY = {
  label: "Every day",
  meals: [
    {
      id: "m1-breakfast",
      label: "Breakfast",
      items: [
        {name: "Oats", quantity: 60, unit: "g", calories: 220,
          proteinG: 8, carbsG: 38, fatG: 4, estimated: true},
      ],
    },
    {
      id: "m2-lunch",
      label: "Lunch",
      items: [
        {name: "Rice", quantity: 150, unit: "g", calories: 210,
          proteinG: 4, carbsG: 45, fatG: 0.5},
        {name: "Chicken", quantity: 200, unit: "g", calories: 330,
          proteinG: 62, carbsG: 0, fatG: 7},
      ],
    },
    {
      id: "m3-supplements",
      label: "Supplements",
      items: [{name: "Creatine", quantity: 5, unit: "g", calories: 20}],
    },
  ],
};

const TARGETS = {
  goal: "fatLoss", calories: 2200, proteinG: 160, carbsG: 250, fatG: 73,
  source: "manual",
};

const LOGGED = {
  id: "e1", foodId: "usda:171477", foodName: "Chicken breast, roasted",
  quantity: 200, unit: "g", grams: 200,
  kcal: 330, proteinG: 62, carbsG: 0, fatG: 7.2,
  source: "usdaFdc", sourceRef: "171477", origin: "logged",
  estimated: false, mealId: null,
};

const MATERIALISED = {
  id: "p1", foodId: "plan:m1-breakfast#0", foodName: "Oats",
  quantity: 60, unit: "g", grams: 60,
  kcal: 220, proteinG: 8, carbsG: 38, fatG: 4,
  source: "dietPlan", sourceRef: "m1-breakfast#0", origin: "plannedMeal",
  estimated: true, mealId: "m1-breakfast",
};

// Each case pins one rule the two implementations must agree on.
const CASES = [
  {
    name: "a full day: targets, a plan, and logged food",
    input: {
      dayKey: "2026-08-30", weekday: 7, targets: TARGETS,
      planName: "Cut", day: PLAN_DAY,
      consumedMealIds: ["m1-breakfast"], log: [LOGGED],
    },
  },
  {
    name: "the log wins over the ticked meal's planned figures",
    input: {
      dayKey: "2026-08-30", weekday: 7, targets: TARGETS,
      planName: "Cut", day: PLAN_DAY,
      consumedMealIds: ["m1-breakfast", "m2-lunch"], log: [LOGGED],
    },
  },
  {
    name: "a day of only materialised entries is flagged as assumed",
    input: {
      dayKey: "2026-08-30", weekday: 7, targets: TARGETS,
      planName: "Cut", day: PLAN_DAY,
      consumedMealIds: ["m1-breakfast"], log: [MATERIALISED],
    },
  },
  {
    name: "an empty log falls back to ticked meals, and says so",
    input: {
      dayKey: "2026-08-30", weekday: 7, targets: TARGETS,
      planName: "Cut", day: PLAN_DAY,
      consumedMealIds: ["m2-lunch"], log: [],
    },
  },
  {
    name: "nothing ticked and nothing logged is 'nothing logged', not zero",
    input: {
      dayKey: "2026-08-30", weekday: 7, targets: TARGETS,
      planName: "Cut", day: PLAN_DAY, consumedMealIds: [], log: [],
    },
  },
  {
    name: "supplements never count toward meals or the energy budget",
    input: {
      dayKey: "2026-08-30", weekday: 7, targets: TARGETS,
      planName: "Cut", day: PLAN_DAY,
      consumedMealIds: ["m3-supplements"], log: [],
    },
  },
  {
    name: "no targets: remaining is null, macros are all untracked",
    input: {
      dayKey: "2026-08-30", weekday: 7, targets: null,
      planName: "Cut", day: PLAN_DAY,
      consumedMealIds: ["m2-lunch"], log: [],
    },
  },
  {
    name: "targets with only a protein figure leave the rest null, not zero",
    input: {
      dayKey: "2026-08-30", weekday: 7,
      targets: {goal: "maintain", calories: 2000, proteinG: 150,
        carbsG: null, fatG: null, source: "manual"},
      planName: "Cut", day: PLAN_DAY, consumedMealIds: [], log: [LOGGED],
    },
  },
  {
    name: "no plan for the day, but logged food still counts",
    input: {
      dayKey: "2026-08-30", weekday: 7, targets: TARGETS,
      planName: null, day: null, consumedMealIds: [], log: [LOGGED],
    },
  },
  {
    name: "maintenance is carried through, with where it came from",
    input: {
      dayKey: "2026-08-30", weekday: 7, targets: TARGETS,
      planName: "Cut", day: PLAN_DAY,
      consumedMealIds: [], log: [LOGGED],
      energy: {maintenanceKcal: 2771, source: "estimated"},
    },
  },
  {
    name: "a target above maintenance reports a positive difference",
    input: {
      dayKey: "2026-08-30", weekday: 7,
      targets: {goal: "muscleGain", calories: 3000, proteinG: 170,
        carbsG: null, fatG: null, source: "manual"},
      planName: "Cut", day: PLAN_DAY, consumedMealIds: [], log: [LOGGED],
      energy: {maintenanceKcal: 2771, source: "measured"},
    },
  },
  {
    name: "no body data: energy is null and so is the comparison",
    input: {
      dayKey: "2026-08-30", weekday: 7, targets: TARGETS,
      planName: "Cut", day: PLAN_DAY, consumedMealIds: [], log: [LOGGED],
    },
  },
  {
    name: "maintenance with no target compares to nothing",
    input: {
      dayKey: "2026-08-30", weekday: 7, targets: null,
      planName: "Cut", day: PLAN_DAY, consumedMealIds: [], log: [LOGGED],
      energy: {maintenanceKcal: 2500, source: "stated"},
    },
  },
  {
    name: "over target reports a negative remainder, never a clamped zero",
    input: {
      dayKey: "2026-08-30", weekday: 7,
      targets: {goal: "fatLoss", calories: 300, proteinG: 10,
        carbsG: null, fatG: null, source: "manual"},
      planName: "Cut", day: PLAN_DAY, consumedMealIds: [], log: [LOGGED],
    },
  },
];

// The plan-day resolver: every weekday, plus the every-day template and the
// ambiguous case. `dayForDate` (Dart) and `resolveDietDay` (JS) are separate
// implementations of one rule, and this is what keeps them honest.
const WEEKDAY_PLANS = {
  perWeekday: [
    {weekday: 1, label: "Monday"},
    {weekday: 3, label: "Wednesday"},
    {weekday: 7, label: "Sunday"},
  ],
  everyDay: [{weekday: null, label: "Every day"}],
  singleSpecific: [{weekday: 2, label: "Tuesday only"}],
  ambiguous: [
    {weekday: 2, label: "Tuesday"},
    {weekday: 4, label: "Thursday"},
  ],
};

function main() {
  const cases = CASES.map((spec) => ({
    ...spec,
    expected: buildDietState({
      ...spec.input,
      consumedMealIds: new Set(spec.input.consumedMealIds),
    }),
  }));

  // 2026-08-31 is a Monday; walk a full week from there.
  const resolutions = [];
  for (const [planName, days] of Object.entries(WEEKDAY_PLANS)) {
    for (let i = 0; i < 7; i++) {
      const date = new Date(Date.UTC(2026, 7, 31 + i, 12));
      resolutions.push({
        plan: planName,
        dayKey: dayKeyFor(date, 0),
        weekday: isoWeekday(date, 0),
        expectedLabel: (resolveDietDay(days, date, 0) || {}).label || null,
      });
    }
  }

  const vectors = {
    schemaVersion: 1,
    note:
      "Golden vectors for the diet-state builder and the plan-day resolver. " +
      "Run by BOTH flutter test and node --test; regenerate with " +
      "scripts/nutrition/build_state_vectors.js. If one implementation " +
      "changes, the other's test fails until they agree again.",
    plans: WEEKDAY_PLANS,
    planDay: PLAN_DAY,
    cases,
    resolutions,
  };

  fs.writeFileSync(
      "test/fixtures/diet_state_vectors.json",
      `${JSON.stringify(vectors, null, 2)}\n`,
  );
  process.stdout.write(
      "test/fixtures/diet_state_vectors.json\n" +
      `  state cases:      ${cases.length}\n` +
      `  day resolutions:  ${resolutions.length}\n`,
  );
}

if (require.main === module) main();
