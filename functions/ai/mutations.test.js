/**
 * Offline unit tests for the mutating-tool `validate()` functions
 * (`./mutations.js`). Pure input→normalized-payload (or throw); no Firestore,
 * so this runs under plain `node --test`.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {mutatingToolsByName, ValidationError} = require("./mutations");

const createExpense = mutatingToolsByName.get("create_expense");
const markMealEaten = mutatingToolsByName.get("mark_meal_eaten");

test("create_expense: valid input normalizes; currency defaults to EGP", () => {
  const v = createExpense.validate({amountMinor: 1200, category: "coffee"});
  assert.deepEqual(v, {
    amountMinor: 1200,
    currency: "EGP",
    category: "coffee",
    note: null,
    spentAtIso: null,
  });
});

test("create_expense: rejects zero, negative, and non-integer amounts", () => {
  assert.throws(() => createExpense.validate({amountMinor: 0, category: "food"}), ValidationError);
  assert.throws(() => createExpense.validate({amountMinor: -5, category: "food"}), ValidationError);
  assert.throws(() => createExpense.validate({amountMinor: 12.5, category: "food"}), ValidationError);
});

test("create_expense: rejects an unknown category", () => {
  assert.throws(
      () => createExpense.validate({amountMinor: 100, category: "rent"}),
      ValidationError);
});

test("every mutating tool exposes card fields and a result line", () => {
  for (const tool of [createExpense, markMealEaten]) {
    assert.equal(tool.mutating, true);
    assert.equal(typeof tool.summarize, "function");
    assert.equal(typeof tool.fields, "function");
    assert.equal(typeof tool.result, "function");
  }
});

test("mark_meal_eaten: eaten defaults to true; label and date default to null",
    () => {
      const v = markMealEaten.validate({mealId: "breakfast-1"});
      assert.deepEqual(v, {
        mealId: "breakfast-1",
        label: null,
        eaten: true,
        dateIso: null,
      });
    });

test("mark_meal_eaten: accepts eaten:false, a label, and a date", () => {
  const v = markMealEaten.validate({
    mealId: "lunch-2",
    label: "Lunch",
    eaten: false,
    date: "2026-08-25T00:00:00.000Z",
  });
  assert.deepEqual(v, {
    mealId: "lunch-2",
    label: "Lunch",
    eaten: false,
    dateIso: "2026-08-25T00:00:00.000Z",
  });
});

test("mark_meal_eaten: rejects a missing/blank mealId; coerces odd eaten",
    () => {
      assert.throws(() => markMealEaten.validate({}), ValidationError);
      assert.throws(
          () => markMealEaten.validate({mealId: "   "}), ValidationError);
      // Anything other than exactly true reads as "not eaten" — the boolean
      // is a deliberate toggle, not free text.
      const v = markMealEaten.validate({mealId: "m1", eaten: "nope"});
      assert.equal(v.eaten, false);
    });
