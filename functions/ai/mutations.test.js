/**
 * Offline unit tests for the mutating-tool `validate()` functions
 * (`./mutations.js`). Pure input→normalized-payload (or throw); no Firestore,
 * so this runs under plain `node --test`.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {mutatingToolsByName, ValidationError} = require("./mutations");

const createExpense = mutatingToolsByName.get("create_expense");

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
  for (const tool of [createExpense]) {
    assert.equal(tool.mutating, true);
    assert.equal(typeof tool.summarize, "function");
    assert.equal(typeof tool.fields, "function");
    assert.equal(typeof tool.result, "function");
  }
});
