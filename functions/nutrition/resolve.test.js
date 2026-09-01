/**
 * Offline tests for the composite food resolver (`./resolve.js`) — the server
 * mirror of the Dart `CompositeFoodResolver`. Runs against the REAL bundled
 * catalog (`./foods.json`), so a resolution here is the same one the coach
 * makes in production, and layers a synthetic custom-food list over it.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  resolveComposite,
  resolveAndCompute,
  normalizeItem,
} = require("./resolve");

// A user-defined food that has no USDA analogue, plus one that deliberately
// collides with a real catalog entry to prove custom wins.
const KOSHARI = {
  id: "k1",
  name: "Koshari",
  kcalPer100g: 150,
  proteinPer100g: 5,
  carbsPer100g: 27,
  fatPer100g: 3,
  preparation: "cooked",
  portions: [{label: "bowl", grams: 400}],
  createdAt: new Date("2026-08-01T00:00:00Z"),
};

test("resolveComposite resolves a plain USDA query", () => {
  const match = resolveComposite(
      {query: "chicken broilers fryers breast meat only cooked roasted"}, []);
  assert.equal(match.kind, "resolved");
  assert.equal(match.food.id, "usda:171477");
  assert.equal(match.food.source, "usdaFdc");
});

test("resolveComposite reports the raw/cooked fork as ambiguous", () => {
  const match = resolveComposite({query: "rice white long-grain regular"}, []);
  assert.equal(match.kind, "ambiguous");
  assert.ok(match.candidates.length > 1);
});

test("resolveComposite honours an explicit preparation", () => {
  const match = resolveComposite(
      {query: "rice white long-grain regular", preparation: "cooked"}, []);
  assert.equal(match.kind, "resolved");
  assert.equal(match.food.id, "usda:168878");
});

test("resolveComposite returns notFound for a food USDA lacks", () => {
  const match = resolveComposite({query: "koshari"}, []);
  assert.equal(match.kind, "notFound");
});

test("a custom food wins over the catalog, labelled as the user's own", () => {
  // USDA has no Koshari; the user's does, so it resolves — and to THEIR figure.
  const match = resolveComposite({query: "koshari"}, [KOSHARI]);
  assert.equal(match.kind, "resolved");
  assert.equal(match.food.id, "custom:k1");
  assert.equal(match.food.source, "userCustom");
  assert.equal(match.food.kcalPer100g, 150);
});

test("resolveComposite by id short-circuits the search", () => {
  const usda = resolveComposite({foodId: "usda:171477"}, []);
  assert.equal(usda.kind, "resolved");
  assert.equal(usda.food.id, "usda:171477");

  const custom = resolveComposite({foodId: "custom:k1"}, [KOSHARI]);
  assert.equal(custom.kind, "resolved");
  assert.equal(custom.food.name, "Koshari");
});

test("a deleted custom id resolves to notFound, never a lookalike", () => {
  // Substituting a USDA food for a custom one the user deleted would silently
  // rewrite what a past entry meant.
  const match = resolveComposite({foodId: "custom:gone"}, [KOSHARI]);
  assert.equal(match.kind, "notFound");
});

test("resolveAndCompute prices a resolved food", () => {
  const out = resolveAndCompute(
      {foodId: "usda:171477", quantity: 200, unit: "g"}, []);
  assert.equal(out.outcome, "computed");
  // 165 kcal/100g × 2.
  assert.equal(out.kcal, 330);
  assert.equal(out.foodId, "usda:171477");
  assert.equal(out.source, "usdaFdc");
});

test("resolveAndCompute prices a custom food from the user's figures", () => {
  const out = resolveAndCompute(
      {foodId: "custom:k1", quantity: 400, unit: "g"}, [KOSHARI]);
  assert.equal(out.outcome, "computed");
  assert.equal(out.kcal, 600); // 150 × 4
  assert.equal(out.source, "userCustom");
});

test("resolveAndCompute surfaces ambiguity instead of guessing", () => {
  const out = resolveAndCompute(
      {query: "rice white long-grain regular", quantity: 100, unit: "g"}, []);
  assert.equal(out.outcome, "ambiguous");
  assert.ok(out.candidates.length > 1);
  assert.ok(out.candidates.every((c) => c.foodId));
});

test("resolveAndCompute surfaces notFound instead of guessing", () => {
  const out = resolveAndCompute(
      {query: "koshari", quantity: 1, unit: "bowl"}, []);
  assert.equal(out.outcome, "notFound");
});

test("resolveAndCompute refuses a volume with no recorded density", () => {
  // 100ml of olive oil is not 100g; the source didn't record a ml measure, so
  // it names the measures that WOULD work rather than assuming one.
  const out = resolveAndCompute(
      {query: "oil olive salad or cooking", quantity: 100, unit: "ml"}, []);
  assert.equal(out.outcome, "unresolvedMeasure");
  assert.equal(out.unit, "ml");
  assert.ok(Array.isArray(out.availableMeasures));
});

test("normalizeItem requires a reference, a positive quantity, and a unit",
    () => {
      assert.deepEqual(
          normalizeItem({foodId: "usda:1", quantity: 200, unit: "g"}),
          {quantity: 200, unit: "g", foodId: "usda:1"});
      assert.throws(() => normalizeItem({quantity: 1, unit: "g"}), /foodId/);
      assert.throws(
          () => normalizeItem({query: "egg", quantity: 0, unit: "g"}),
          /positive quantity/);
      assert.throws(
          () => normalizeItem({query: "egg", quantity: 1}), /unit/);
    });

test("normalizeItem keeps only catalog-distinguished preparations", () => {
  assert.equal(
      normalizeItem(
          {query: "rice", quantity: 1, unit: "g", preparation: "cooked"})
          .preparation,
      "cooked");
  // 'unknown' is not a state the user disambiguates with, so it's dropped.
  assert.equal(
      normalizeItem(
          {query: "rice", quantity: 1, unit: "g", preparation: "unknown"})
          .preparation,
      undefined);
});
