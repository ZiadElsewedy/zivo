#!/usr/bin/env node
/**
 * Generates `test/fixtures/nutrition_vectors.json` — the shared golden vectors
 * that both `flutter test` and `node --test` run.
 *
 * This file is the answer to the two-implementations problem (see
 * `docs/DIET_COACH_AUDIT.md`, T13). The app resolves and computes nutrition in
 * Dart; the coach does it in JavaScript. Comment discipline is not a guarantee
 * they agree — a fixture both sides must reproduce exactly is.
 *
 * The expectations are produced by the JS implementation and then asserted by
 * BOTH sides, so regenerating this file after changing one implementation will
 * fail the other's test until they match again. That is the intended friction.
 *
 * Usage: node scripts/nutrition/build_vectors.js
 */

const fs = require("node:fs");
const crypto = require("node:crypto");
const {loadCatalog, resolveFood, foodById, nutritionFor} =
  require("../../functions/nutrition/food_db");

// Deliberately spans the cases that matter rather than a random sample:
// exact mass scaling, unit conversion, the raw/cooked fork, a food with
// household portions, a refusal, and a miss.
const LOOKUPS = [
  {query: "chicken broilers fryers breast meat only cooked roasted"},
  {query: "rice white long-grain regular", label: "raw/cooked fork"},
  {query: "rice white long-grain regular", preparation: "cooked"},
  {query: "egg whole raw fresh"},
  {query: "oil olive salad or cooking"},
  {query: "broccoli raw"},
  {query: "koshari", label: "not in a USDA catalog"},
  {query: "", label: "empty query"},
];

const COMPUTATIONS = [
  {foodId: "usda:171477", quantity: 200, unit: "g"},
  {foodId: "usda:171477", quantity: 4, unit: "oz"},
  {foodId: "usda:171477", quantity: 0.5, unit: "kg"},
  {foodId: "usda:168878", quantity: 150, unit: "g"},
  {foodId: "usda:168877", quantity: 150, unit: "g"},
  {foodId: "usda:171413", quantity: 10, unit: "g"},
  {foodId: "usda:171413", quantity: 100, unit: "ml", label: "no density"},
  {foodId: "usda:171287", quantity: 2, unit: "pcs"},
  {foodId: "usda:171477", quantity: 0, unit: "g", label: "zero"},
  {foodId: "usda:171477", quantity: -5, unit: "g", label: "negative"},
];

function main() {
  const catalog = loadCatalog();
  const catalogJson = fs.readFileSync(require("../../functions/nutrition/food_db").CATALOG_PATH, "utf8");
  const checksum = crypto.createHash("sha256")
      .update(catalogJson.trimEnd()).digest("hex");

  const lookups = LOOKUPS.map((spec) => {
    const match = resolveFood(spec.query, {preparation: spec.preparation});
    const expected = {kind: match.kind};
    if (match.kind === "resolved") {
      expected.foodId = match.food.id;
      expected.kcalPer100g = match.food.kcalPer100g;
      expected.preparation = match.food.preparation;
    } else if (match.kind === "ambiguous") {
      expected.candidateIds = match.candidates.map((f) => f.id);
      expected.preparations =
        [...new Set(match.candidates.map((f) => f.preparation))].sort();
    }
    return {...spec, expected};
  });

  const computations = COMPUTATIONS.map((spec) => {
    const food = foodById(spec.foodId);
    if (!food) throw new Error(`vector references a missing food: ${spec.foodId}`);
    const result = nutritionFor(food, spec.quantity, spec.unit);
    const expected = result.unresolved ?
      {unresolved: result.unresolved} :
      {
        grams: result.grams,
        kcal: result.kcal,
        proteinG: result.proteinG,
        carbsG: result.carbsG,
        fatG: result.fatG,
        sourceRef: result.sourceRef,
      };
    return {...spec, expected};
  });

  const vectors = {
    schemaVersion: 1,
    note:
      "Golden vectors for the nutrition resolver + calculator. Run by BOTH " +
      "flutter test and node --test; regenerate with " +
      "scripts/nutrition/build_vectors.js. If one implementation changes, " +
      "the other's test fails until they agree again.",
    catalogSha256: checksum,
    catalogFoodCount: catalog.foods.length,
    lookups,
    computations,
  };

  fs.writeFileSync(
      "test/fixtures/nutrition_vectors.json",
      `${JSON.stringify(vectors, null, 2)}\n`,
  );
  process.stdout.write(
      `test/fixtures/nutrition_vectors.json\n` +
      `  lookups:      ${lookups.length}\n` +
      `  computations: ${computations.length}\n` +
      `  catalog:      ${checksum}\n`,
  );
}

if (require.main === module) main();
