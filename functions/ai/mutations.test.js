/**
 * Offline unit tests for the mutating-tool `validate()` functions
 * (`./mutations.js`). Pure input→normalized-payload (or throw); no Firestore,
 * so this runs under plain `node --test`.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {mutatingToolsByName, ValidationError} = require("./mutations");

const createExpense = mutatingToolsByName.get("create_expense");
const editExpense = mutatingToolsByName.get("edit_expense");
const deleteExpense = mutatingToolsByName.get("delete_expense");
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
  for (const tool of [createExpense, editExpense, deleteExpense, markMealEaten]) {
    assert.equal(tool.mutating, true);
    assert.equal(typeof tool.summarize, "function");
    assert.equal(typeof tool.fields, "function");
    assert.equal(typeof tool.result, "function");
  }
});

test("edit_expense: keeps only the fields being changed, plus id and label",
    () => {
      const v = editExpense.validate({
        expenseId: "exp-1",
        label: "coffee 40.00 EGP",
        amountMinor: 6000,
      });
      assert.deepEqual(v, {
        expenseId: "exp-1",
        label: "coffee 40.00 EGP",
        amountMinor: 6000,
      });
      // The card/history fields carry the verb and the new value.
      const f = editExpense.fields(v);
      assert.equal(f.action, "edit");
      assert.equal(f.amount, "60.00");
      assert.match(editExpense.result(v), /Updated expense · coffee 40\.00 EGP/);
    });

test("edit_expense: normalizes currency/category and validates them", () => {
  const v = editExpense.validate({
    expenseId: "exp-2",
    category: "food",
    currency: "usd",
  });
  assert.deepEqual(v, {
    expenseId: "exp-2",
    label: null,
    category: "food",
    currency: "USD",
  });
  assert.throws(
      () => editExpense.validate({expenseId: "x", category: "rent"}),
      ValidationError);
  assert.throws(
      () => editExpense.validate({expenseId: "x", amountMinor: 0}),
      ValidationError);
});

test("edit_expense: rejects a missing id and a no-op edit (nothing to change)",
    () => {
      assert.throws(() => editExpense.validate({amountMinor: 100}), ValidationError);
      assert.throws(
          () => editExpense.validate({expenseId: "exp-3", label: "coffee"}),
          ValidationError);
    });

test("delete_expense: requires an id; carries display-only context", () => {
  const v = deleteExpense.validate({
    expenseId: "exp-9",
    label: "coffee 40.00 EGP",
    amountMinor: 4000,
    currency: "egp",
    category: "coffee",
  });
  assert.deepEqual(v, {
    expenseId: "exp-9",
    label: "coffee 40.00 EGP",
    amountMinor: 4000,
    currency: "EGP",
    category: "coffee",
  });
  assert.equal(deleteExpense.fields(v).action, "delete");
  assert.match(deleteExpense.result(v), /Deleted expense · coffee 40\.00 EGP/);
  assert.throws(() => deleteExpense.validate({}), ValidationError);
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
