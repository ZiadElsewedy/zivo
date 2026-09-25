const assert = require("node:assert/strict");
const {test} = require("node:test");

const {makeResolver, IDENTITY} = require("./exercise_identity");

// Mirrors the Dart `ExerciseIdentityResolver` contract (ADR-017).

test("canonicalIdOf follows chains and survives a cycle", () => {
  const r = makeResolver([
    {legacyId: "a", canonicalId: "b"},
    {legacyId: "b", canonicalId: "c"},
    {legacyId: "x", canonicalId: "y"},
    {legacyId: "y", canonicalId: "x"},
  ]);
  assert.equal(r.canonicalIdOf("a"), "c");
  assert.equal(r.canonicalIdOf("c"), "c");
  // A corrupt loop degrades to "not merged" rather than hanging.
  assert.ok(["x", "y"].includes(r.canonicalIdOf("x")));
  assert.equal(IDENTITY.canonicalIdOf("anything"), "anything");
});

test("canonicalize rewrites ids in memory and never mutates the input", () => {
  const session = {
    id: "s1",
    exercises: [
      {exerciseId: "push-e1", name: "Pec Deck"},
      {exerciseId: "push-e2", name: "Bench"},
    ],
  };
  const r = makeResolver([{legacyId: "push-e1", canonicalId: "x-pec"}]);
  const [out] = r.canonicalize([session]);
  assert.equal(out.exercises[0].exerciseId, "x-pec");
  assert.equal(out.exercises[1], session.exercises[1]);
  assert.equal(session.exercises[0].exerciseId, "push-e1",
      "the stored record is never rewritten");
});

test("no aliases → the same array back, nothing allocated", () => {
  const sessions = [{id: "s", exercises: []}];
  assert.equal(IDENTITY.canonicalize(sessions), sessions);
});
