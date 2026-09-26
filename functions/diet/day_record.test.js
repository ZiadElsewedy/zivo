/**
 * Offline tests for the daily diet record (`./day_record.js`).
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  buildDietDayRecord, offsetFromLocalMidnight, MealStatus,
} = require("./day_record");

const DAY = "2026-09-25";

const PLAN = {
  id: "p1",
  name: "Cut",
  days: [{weekday: null, label: "Every day", meals: [
    {id: "m0", label: "Breakfast", items: [
      {name: "Oats", quantity: 60, unit: "g", calories: 228, proteinG: 8.1,
        carbsG: 40.2, fatG: 4.1},
      {name: "Milk", quantity: 200, unit: "ml", calories: 100, proteinG: 7,
        carbsG: 10, fatG: 3},
    ]},
    {id: "m1", label: "Lunch", items: [
      {name: "Chicken", quantity: 200, unit: "g", calories: 330,
        proteinG: 62, carbsG: 0, fatG: 7, estimated: true},
    ]},
    {id: "m2", label: "Dinner", items: [
      {name: "Eggs", quantity: 2, unit: "piece", calories: 140, proteinG: 12,
        carbsG: 1, fatG: 10},
    ]},
    {id: "s", label: "Supplements", items: [
      {name: "Creatine", quantity: 5, unit: "g", calories: 0},
    ]},
  ]}],
};

/**
 * The entries ticking a meal materialises (`planned_meal_log.dart`).
 * @param {!Object} meal
 * @param {string=} day
 * @return {!Array<!Object>}
 */
function ticks(meal, day = DAY) {
  return meal.items.map((it, i) => ({
    id: `${day}__${meal.id}-${i}`, foodName: it.name, quantity: it.quantity,
    unit: it.unit, kcal: Math.round(it.calories || 0),
    proteinG: it.proteinG || 0, carbsG: it.carbsG || 0, fatG: it.fatG || 0,
    origin: "plannedMeal", estimated: it.estimated === true, mealId: meal.id,
  }));
}

const meal = (id) => PLAN.days[0].meals.find((m) => m.id === id);
const TARGETS = {goal: "fatLoss", calories: 2000, proteinG: 160, carbsG: null,
  fatG: null, source: "calculated"};

const build = (over) => buildDietDayRecord(Object.assign({
  dayKey: DAY, isPast: false, offsetMinutes: 180, plan: PLAN,
  planDay: PLAN.days[0], targets: TARGETS, entries: [], log: [],
  existing: null,
}, over));

test("a day where nothing happened has no record (absent, not zero)", () => {
  assert.equal(build(), null);
});

test("ticked as planned, modified, skipped and unmarked meals", () => {
  const breakfastTicks = ticks(meal("m0"));
  const r = build({
    entries: [
      {mealId: "m0", eaten: true},
      {mealId: "m1", eaten: true},
      {mealId: "m2", eaten: false, status: "skipped"},
    ],
    // Lunch: ticked, then one amount was changed in the log.
    log: [...breakfastTicks, Object.assign(ticks(meal("m1"))[0],
        {quantity: 150, kcal: 248, proteinG: 46.5})],
  });
  const status = Object.fromEntries(r.meals.map((m) => [m.mealId, m.status]));
  assert.deepEqual(status, {
    m0: MealStatus.EATEN, m1: MealStatus.MODIFIED, m2: MealStatus.SKIPPED,
    s: MealStatus.UNMARKED,
  });
  assert.deepEqual(r.adherence,
      {mealsPlanned: 3, eaten: 1, modified: 1, skipped: 1, unmarked: 0});
  // What was eaten comes from the log; the plan side is kept alongside.
  assert.equal(r.meals[1].actual.kcal, 248);
  assert.equal(r.meals[1].planned.kcal, 330);
  assert.equal(r.consumed.kcal, 228 + 100 + 248);
  assert.equal(r.consumed.basis, "tickedPlanMeals");
  assert.equal(r.planned.kcal, 228 + 100 + 330 + 140);
  assert.equal(r.targets.calories, 2000);
});

test("every log row is in exactly one place: a ticked meal or unplanned",
    () => {
      const apple = {id: "x", foodName: "Apple", quantity: 1, unit: "piece",
        kcal: 95, proteinG: 0.5, carbsG: 25, fatG: 0.3, origin: "logged",
        estimated: false, mealId: null};
      const r = build({
        entries: [{mealId: "m1", eaten: true}],
        log: [...ticks(meal("m1")), apple],
      });
      assert.deepEqual(r.unplanned,
          {kcal: 95, proteinG: 0.5, carbsG: 25, fatG: 0.3, count: 1});
      const inMeals = r.meals.reduce(
          (n, m) => n + (m.actual ? m.actual.kcal : 0), 0);
      assert.equal(inMeals + r.unplanned.kcal, r.consumed.kcal);
      // A logged food makes the day "logged", not an assumption.
      assert.equal(r.consumed.basis, "logged");
    });

test("a meal ticked with no log rows (older builds) counts as eaten " +
    "from its planned figures", () => {
  const r = build({entries: [{mealId: "m2", eaten: true}]});
  assert.equal(r.meals[2].status, MealStatus.EATEN);
  assert.equal(r.meals[2].actual, null);
  assert.equal(r.consumed.kcal, 140);
  assert.equal(r.consumed.basis, "tickedPlanMeals");
});

test("a past day keeps its snapshot when the plan has changed since", () => {
  const yesterday = build({entries: [{mealId: "m0", eaten: true}],
    log: ticks(meal("m0"))});
  // The user edits the plan today: breakfast is now 500 kcal, lunch removed.
  const edited = {id: "p1", name: "Cut v2", days: [{weekday: null,
    label: "Every day", meals: [{id: "m0", label: "Breakfast", items: [
      {name: "Oats", quantity: 120, unit: "g", calories: 500}]}]}]};
  const rebuilt = build({isPast: true, plan: edited, planDay: edited.days[0],
    existing: yesterday, entries: [{mealId: "m0", eaten: true}],
    log: ticks(meal("m0"))});
  assert.equal(rebuilt.plan.name, "Cut");
  assert.equal(rebuilt.meals.length, 4);
  assert.equal(rebuilt.meals[0].planned.kcal, 328);
  assert.equal(rebuilt.meals[0].status, MealStatus.EATEN);
  assert.equal(rebuilt.plannedReconstructed, false);
  assert.deepEqual(rebuilt, yesterday);
});

test("today follows the plan as it's edited", () => {
  const before = build({entries: [{mealId: "m0", eaten: true}],
    log: ticks(meal("m0"))});
  const edited = JSON.parse(JSON.stringify(PLAN));
  edited.days[0].meals[2].items[0].calories = 210;
  const after = build({plan: edited, planDay: edited.days[0],
    existing: before, entries: [{mealId: "m0", eaten: true}],
    log: ticks(meal("m0"))});
  assert.equal(after.meals[2].planned.kcal, 210);
});

test("a past day first seen now is marked reconstructed", () => {
  const r = build({isPast: true, entries: [{mealId: "m0", eaten: true}]});
  assert.equal(r.plannedReconstructed, true);
});

test("a meal ticked that the snapshot doesn't hold is still counted", () => {
  const r = build({entries: [{mealId: "gone", eaten: true}], log: [
    {id: `${DAY}__gone-0`, foodName: "Rice", quantity: 100, unit: "g",
      kcal: 130, proteinG: 2.7, carbsG: 28, fatG: 0.3, origin: "plannedMeal",
      estimated: false, mealId: "gone"},
  ]});
  const gone = r.meals.find((m) => m.mealId === "gone");
  assert.equal(gone.planned, null);
  assert.equal(gone.actual.kcal, 130);
  assert.equal(r.unplanned.count, 0);
});

test("the same inputs build the same record (a no-op rebuild)", () => {
  const args = {entries: [{mealId: "m0", eaten: true}],
    log: ticks(meal("m0"))};
  assert.deepEqual(build(args), build(args));
});

test("the user's offset is read off the app's local-midnight date", () => {
  // Cairo (UTC+3): local midnight of the 25th is 21:00Z on the 24th.
  assert.equal(offsetFromLocalMidnight(DAY,
      new Date("2026-09-24T21:00:00Z")), 180);
  assert.equal(offsetFromLocalMidnight(DAY,
      new Date("2026-09-25T05:00:00Z")), -300);
  // UTC midnight (server-written, or a UTC user) can't say.
  assert.equal(offsetFromLocalMidnight(DAY,
      new Date("2026-09-25T00:00:00Z")), null);
  assert.equal(offsetFromLocalMidnight(DAY, null), null);
});

test("the shared vector: this builder still produces the record the app " +
    "parses (test/fixtures/diet_day_record_vectors.json)", () => {
  const path = require("node:path");
  const vector = require(path.join(__dirname, "..", "..", "test", "fixtures",
      "diet_day_record_vectors.json"));
  assert.deepEqual(buildDietDayRecord(vector.input), vector.record);
});
