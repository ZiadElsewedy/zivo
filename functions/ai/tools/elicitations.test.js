/**
 * Offline unit tests for the elicitation tool registry (`ask_choice`). Pure
 * `validate` — no store, no model, runs under `node --test`.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {ASK_CHOICE, REQUEST_INPUT, ElicitationError} =
    require("./elicitations");

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

// ---- request_input (the form) --------------------------------------------

test("request_input is a non-executing elicitation tool", () => {
  assert.equal(REQUEST_INPUT.elicits, true);
  assert.equal(REQUEST_INPUT.messageKind, "input_request");
  assert.equal(typeof REQUEST_INPUT.execute, "undefined");
  assert.ok(!REQUEST_INPUT.mutating);
});

test("request_input validate normalizes fields and defaults", () => {
  const v = REQUEST_INPUT.validate({
    prompt: "A couple of details first",
    fields: [
      {key: "heightCm", label: "Height", type: "number", unit: "cm"},
      {key: "note", label: "Anything else?"},
    ],
  });
  assert.equal(v.prompt, "A couple of details first");
  assert.deepEqual(v.fields, [
    {key: "heightCm", label: "Height", type: "number", required: true,
      unit: "cm"},
    // type defaults to text; required defaults true; no unit key when absent.
    {key: "note", label: "Anything else?", type: "text", required: true},
  ]);
  assert.deepEqual(REQUEST_INPUT.fields(v), {fields: v.fields});
  assert.equal(REQUEST_INPUT.summarize(v), "A couple of details first");
});

test("request_input: required:false honoured, unknown type falls to text", () => {
  const v = REQUEST_INPUT.validate({
    prompt: "P",
    fields: [{key: "x", label: "X", type: "slider", required: false}],
  });
  assert.equal(v.fields[0].type, "text");
  assert.equal(v.fields[0].required, false);
});

test("request_input validates a choice field's options", () => {
  const v = REQUEST_INPUT.validate({
    prompt: "P",
    fields: [{
      key: "goal", label: "Goal", type: "choice",
      options: [{value: "gain", label: "Gain"}, {value: "lose", label: "Lose"}],
    }],
  });
  assert.deepEqual(v.fields[0].options, [
    {value: "gain", label: "Gain"},
    {value: "lose", label: "Lose"},
  ]);
  // A choice field with too few options is rejected.
  assert.throws(
      () => REQUEST_INPUT.validate({
        prompt: "P",
        fields: [{key: "g", label: "G", type: "choice", options: ["only"]}],
      }),
      ElicitationError);
});

test("request_input caps at four fields and de-dupes keys", () => {
  const v = REQUEST_INPUT.validate({
    prompt: "P",
    fields: [
      {key: "a", label: "A"},
      {key: "a", label: "dup"},
      {key: "b", label: "B"},
      {key: "c", label: "C"},
      {key: "d", label: "D"},
      {key: "e", label: "E"},
    ],
  });
  assert.deepEqual(v.fields.map((f) => f.key), ["a", "b", "c", "d"]);
});

test("request_input rejects a missing prompt or empty fields", () => {
  assert.throws(
      () => REQUEST_INPUT.validate({fields: [{key: "a", label: "A"}]}),
      ElicitationError);
  assert.throws(
      () => REQUEST_INPUT.validate({prompt: "P", fields: []}),
      ElicitationError);
});

test("request_input rejects a field missing key or label", () => {
  assert.throws(
      () => REQUEST_INPUT.validate({prompt: "P", fields: [{label: "no key"}]}),
      ElicitationError);
  assert.throws(
      () => REQUEST_INPUT.validate({prompt: "P", fields: [{key: "x"}]}),
      ElicitationError);
});
