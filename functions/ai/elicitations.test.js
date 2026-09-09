/**
 * Offline unit tests for the elicitation tool registry (`ask_choice`). Pure
 * `validate` — no store, no model, runs under `node --test`.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {ASK_CHOICE, ElicitationError} = require("./elicitations");

test("ask_choice is a non-executing elicitation tool", () => {
  assert.equal(ASK_CHOICE.elicits, true);
  assert.equal(ASK_CHOICE.messageKind, "choice_request");
  // It carries no execute/mutating half — it only ever pauses the turn.
  assert.equal(typeof ASK_CHOICE.execute, "undefined");
  assert.ok(!ASK_CHOICE.mutating);
});

test("validate normalizes {value,label} options and the flags", () => {
  const v = ASK_CHOICE.validate({
    prompt: "Which goal?",
    options: [
      {value: "gain", label: "Gain weight"},
      {value: "lose", label: "Lose fat"},
    ],
    allowMultiple: true,
  });
  assert.equal(v.prompt, "Which goal?");
  assert.deepEqual(v.options, [
    {value: "gain", label: "Gain weight"},
    {value: "lose", label: "Lose fat"},
  ]);
  assert.equal(v.allowMultiple, true);
  // The card spec the client renders comes straight from fields().
  assert.deepEqual(ASK_CHOICE.fields(v), {
    options: v.options, allowMultiple: true,
  });
  // The fallback line is the question itself.
  assert.equal(ASK_CHOICE.summarize(v), "Which goal?");
});

test("validate accepts bare-string options (value = label)", () => {
  const v = ASK_CHOICE.validate({prompt: "Pick one", options: ["A", "B"]});
  assert.deepEqual(v.options, [
    {value: "A", label: "A"},
    {value: "B", label: "B"},
  ]);
  assert.equal(v.allowMultiple, false);
});

test("validate collapses duplicate option values", () => {
  const v = ASK_CHOICE.validate({
    prompt: "Pick one",
    options: [
      {value: "x", label: "First"},
      {value: "x", label: "Dup"},
      {value: "y", label: "Second"},
    ],
  });
  assert.deepEqual(v.options.map((o) => o.value), ["x", "y"]);
});

test("validate caps at five options", () => {
  const many = Array.from({length: 9}, (_, i) => `opt-${i}`);
  const v = ASK_CHOICE.validate({prompt: "Pick", options: many});
  assert.equal(v.options.length, 5);
});

test("validate rejects a missing prompt", () => {
  assert.throws(
      () => ASK_CHOICE.validate({options: ["A", "B"]}), ElicitationError);
});

test("validate rejects fewer than two options", () => {
  assert.throws(
      () => ASK_CHOICE.validate({prompt: "Q", options: ["only"]}),
      ElicitationError);
  assert.throws(
      () => ASK_CHOICE.validate({prompt: "Q", options: []}),
      ElicitationError);
});

test("validate rejects when de-duping leaves fewer than two", () => {
  assert.throws(
      () => ASK_CHOICE.validate({
        prompt: "Q",
        options: [{value: "x", label: "a"}, {value: "x", label: "b"}],
      }),
      ElicitationError);
});
