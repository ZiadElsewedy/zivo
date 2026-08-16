/**
 * Offline unit tests for the mutating-tool `validate()` functions
 * (`./mutations.js`). Pure input→normalized-payload (or throw); no Firestore,
 * so this runs under plain `node --test`.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {mutatingToolsByName, ValidationError} = require("./mutations");

const createTask = mutatingToolsByName.get("create_task");
const createExpense = mutatingToolsByName.get("create_expense");
const createEvent = mutatingToolsByName.get("create_event");

test("create_task: title only normalizes with sane defaults", () => {
  const v = createTask.validate({title: "  Submit report  "});
  assert.deepEqual(v, {title: "Submit report", dueIso: null, priority: false});
});

test("create_task: due + high priority are captured", () => {
  const v = createTask.validate({
    title: "Submit report",
    due: "2026-08-22T09:00:00Z",
    priority: "high",
  });
  assert.equal(v.priority, true);
  assert.equal(v.dueIso, "2026-08-22T09:00:00.000Z");
});

test("create_task: empty title throws", () => {
  assert.throws(() => createTask.validate({title: "   "}), ValidationError);
});

test("create_task: invalid due date throws", () => {
  assert.throws(
      () => createTask.validate({title: "x", due: "not-a-date"}),
      ValidationError);
});

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

test("create_event: valid start; end-before-start throws", () => {
  const v = createEvent.validate({title: "Gym", start: "2026-08-22T18:00:00Z"});
  assert.equal(v.title, "Gym");
  assert.equal(v.startIso, "2026-08-22T18:00:00.000Z");
  assert.equal(v.endIso, null);

  assert.throws(
      () => createEvent.validate({
        title: "Gym",
        start: "2026-08-22T18:00:00Z",
        end: "2026-08-22T17:00:00Z",
      }),
      ValidationError);
});

test("create_event: missing start throws", () => {
  assert.throws(() => createEvent.validate({title: "Gym"}), ValidationError);
});

test("every mutating tool exposes card fields and a result line", () => {
  for (const tool of [createTask, createExpense, createEvent]) {
    assert.equal(tool.mutating, true);
    assert.equal(typeof tool.summarize, "function");
    assert.equal(typeof tool.fields, "function");
    assert.equal(typeof tool.result, "function");
  }
});
