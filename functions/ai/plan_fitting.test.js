/**
 * Offline unit tests for `./plan_fitting.js` — the deterministic half of plan
 * generation. No model, no catalog: pricing is injected.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  fitDayToTarget,
  findAllergen,
  isScalable,
  roundQuantity,
} = require("./plan_fitting");

/**
 * A pricing stub: kcal is proportional to quantity, 2 kcal per unit, so the
 * arithmetic under test is obvious by inspection.
 * @param {!Object} item
 * @param {number} quantity
 * @return {!Object}
 */
function price(item, quantity) {
  return {...item, quantity, calories: Math.round(quantity * 2)};
}

/**
 * @param {string} name
 * @param {number} quantity
 * @param {string} unit
 * @param {number} calories
 * @return {!Object}
 */
function item(name, quantity, unit, calories) {
  return {name, quantity, unit, calories};
}

test("fitDayToTarget: scales gram amounts to land on the target", () => {
  const items = [item("Rice", 100, "g", 200), item("Chicken", 100, "g", 200)];

  const result = fitDayToTarget(items, 600, price);

  assert.equal(result.fitted, true);
  // 600 needed / 400 proposed = 1.5×, applied to both weighable items.
  assert.equal(result.items[0].quantity, 150);
  assert.equal(result.items[1].quantity, 150);
  assert.equal(
      result.items.reduce((s, i) => s + i.calories, 0), 600);
});

test("fitDayToTarget: count-based items are left alone and worked around", () => {
  // Two eggs are two eggs; the rice absorbs the whole adjustment.
  const items = [item("Eggs", 2, "piece", 140), item("Rice", 100, "g", 200)];

  const result = fitDayToTarget(items, 500, price);

  assert.equal(result.items[0].quantity, 2, "eggs untouched");
  // 500 - 140 fixed = 360 from the rice → 180 g at 2 kcal/g. One pass lands
  // exactly on the target because the fixed energy is subtracted first.
  assert.equal(result.items[1].quantity, 180);
  assert.equal(result.items[1].calories, 360);
  assert.equal(result.items.reduce((s, i) => s + i.calories, 0), 500);
});

test("fitDayToTarget: won't stretch the weighable part past 2x to cover " +
  "countable items", () => {
  // Two eggs plus 100 g of rice cannot honestly become a 600 kcal day: the
  // rice would have to more than double as the entire adjustment.
  const items = [item("Eggs", 2, "piece", 140), item("Rice", 100, "g", 200)];

  const result = fitDayToTarget(items, 600, price);

  assert.equal(result.fitted, false);
  assert.equal(result.reason, "out-of-range");
});

test("fitDayToTarget: leaves a day already within 5% alone", () => {
  const items = [item("Rice", 100, "g", 200)];

  const result = fitDayToTarget(items, 205, price);

  assert.equal(result.fitted, true);
  assert.equal(result.factor, 1);
  assert.equal(result.items[0].quantity, 100, "no 102.5g portions");
});

test("fitDayToTarget: refuses to distort a plan that is the wrong shape", () => {
  const items = [item("Rice", 100, "g", 200)];

  // 3× would mean 300g of rice as the whole day — a distortion, not a fit.
  const result = fitDayToTarget(items, 600 * 3, price);

  assert.equal(result.fitted, false);
  assert.equal(result.reason, "out-of-range");
  assert.equal(result.items[0].quantity, 100, "returned as proposed");
});

test("fitDayToTarget: reports when nothing can be scaled", () => {
  const items = [item("Eggs", 2, "piece", 140)];

  const result = fitDayToTarget(items, 600, price);

  assert.equal(result.fitted, false);
  assert.equal(result.reason, "nothing-scalable");
});

test("fitDayToTarget: reports when the countable items alone overshoot", () => {
  const items = [item("Eggs", 12, "piece", 840), item("Rice", 50, "g", 100)];

  const result = fitDayToTarget(items, 600, price);

  assert.equal(result.fitted, false);
  assert.equal(result.reason, "fixed-items-exceed");
});

test("fitDayToTarget: with no target, portions stand as proposed", () => {
  const items = [item("Rice", 100, "g", 200)];

  const result = fitDayToTarget(items, 0, price);

  assert.equal(result.fitted, false);
  assert.equal(result.reason, "no-target");
  assert.equal(result.items[0].quantity, 100);
});

test("roundQuantity: keeps portions weighable", () => {
  assert.equal(roundQuantity(147.3, "g"), 145);
  assert.equal(roundQuantity(2.4, "g"), 5, "never rounds a food away to zero");
  assert.equal(roundQuantity(2.44, "piece"), 2.4);
});

test("isScalable: grams and millilitres, nothing else", () => {
  assert.equal(isScalable("g"), true);
  assert.equal(isScalable("ml"), true);
  assert.equal(isScalable("piece"), false);
  assert.equal(isScalable("slice"), false);
});

test("findAllergen: catches the allergen inside a compound food name", () => {
  const found = findAllergen(
      [{name: "Peanut butter"}], ["peanuts"]);

  assert.ok(found);
  assert.equal(found.item.name, "Peanut butter");
});

test("findAllergen: matches either way round, singular or plural", () => {
  assert.ok(findAllergen([{name: "Boiled eggs"}], ["egg"]));
  assert.ok(findAllergen([{name: "Egg white"}], ["eggs"]));
  assert.ok(findAllergen([{name: "Whole milk"}], ["milk"]));
});

test("findAllergen: passes a plan that contains none of them", () => {
  const found = findAllergen(
      [{name: "Chicken breast"}, {name: "White rice"}],
      ["peanuts", "shellfish"]);

  assert.equal(found, null);
});

test("findAllergen: no allergies means nothing to check", () => {
  assert.equal(findAllergen([{name: "Peanut butter"}], []), null);
  assert.equal(findAllergen([{name: "Peanut butter"}], undefined), null);
});
