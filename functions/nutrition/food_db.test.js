/**
 * Offline tests for the server's nutrition catalog + calculator, including the
 * golden vectors shared with the Flutter suite.
 *
 * The vectors are the load-bearing part: `test/fixtures/nutrition_vectors.json`
 * is run by BOTH this and `test/diet/nutrition_vectors_test.dart`, so the app
 * and the coach cannot drift into quoting different calories for the same food
 * without a test failing (see docs/DIET_COACH_AUDIT.md, T13).
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const {
  loadCatalog,
  resolveFood,
  foodById,
  nutritionFor,
  CATALOG_PATH,
} = require("./food_db");

const REPO_ROOT = path.join(__dirname, "..", "..");
const VECTORS = JSON.parse(fs.readFileSync(
    path.join(REPO_ROOT, "test/fixtures/nutrition_vectors.json"), "utf8"));

test("the server's catalog is byte-identical to the app's", () => {
  // Two copies exist so the server doesn't reach into the Flutter asset tree.
  // They are written together by scripts/nutrition/build_food_db.js, and if
  // they ever diverge the coach and the screen start quoting different
  // numbers for the same food — silently.
  const server = fs.readFileSync(CATALOG_PATH, "utf8");
  const app = fs.readFileSync(
      path.join(REPO_ROOT, "assets/nutrition/foods.json"), "utf8");
  assert.equal(server, app);

  const sha = crypto.createHash("sha256").update(server.trimEnd()).digest("hex");
  assert.equal(sha, VECTORS.catalogSha256,
      "catalog changed without regenerating the golden vectors");
});

test("every catalog row carries a traceable USDA reference", () => {
  const catalog = loadCatalog();
  assert.equal(catalog.foods.length, VECTORS.catalogFoodCount);
  for (const food of catalog.foods) {
    assert.equal(food.source, "usdaFdc");
    assert.match(food.sourceRef, /^\d+$/);
    assert.equal(food.id, `usda:${food.sourceRef}`);
  }
});

test("golden vectors: lookups resolve identically to the fixture", () => {
  for (const spec of VECTORS.lookups) {
    const match = resolveFood(spec.query, {preparation: spec.preparation});
    const label = `${spec.query || "(empty)"}${
      spec.preparation ? ` [${spec.preparation}]` : ""}`;
    assert.equal(match.kind, spec.expected.kind, label);

    if (spec.expected.kind === "resolved") {
      assert.equal(match.food.id, spec.expected.foodId, label);
      assert.equal(match.food.kcalPer100g, spec.expected.kcalPer100g, label);
      assert.equal(match.food.preparation, spec.expected.preparation, label);
    } else if (spec.expected.kind === "ambiguous") {
      assert.deepEqual(
          match.candidates.map((f) => f.id), spec.expected.candidateIds, label);
    }
  }
});

test("golden vectors: computations match the fixture exactly", () => {
  for (const spec of VECTORS.computations) {
    const food = foodById(spec.foodId);
    assert.ok(food, `missing food ${spec.foodId}`);
    const result = nutritionFor(food, spec.quantity, spec.unit);
    const label = `${spec.foodId} ${spec.quantity}${spec.unit}`;

    if (spec.expected.unresolved) {
      assert.equal(result.unresolved, spec.expected.unresolved, label);
      continue;
    }
    assert.equal(result.unresolved, undefined, label);
    assert.equal(result.grams, spec.expected.grams, label);
    assert.equal(result.kcal, spec.expected.kcal, label);
    assert.equal(result.proteinG, spec.expected.proteinG, label);
    assert.equal(result.carbsG, spec.expected.carbsG, label);
    assert.equal(result.fatG, spec.expected.fatG, label);
    assert.equal(result.sourceRef, spec.expected.sourceRef, label);
  }
});

test("a volume with no recorded measure is refused, not assumed", () => {
  // "100ml of olive oil is 100g" is wrong by ~8%; for flour, by a third.
  const oil = foodById("usda:171413");
  const result = nutritionFor(oil, 100, "ml");
  assert.equal(result.unresolved, "unknownMeasure");
  assert.equal(result.kcal, undefined);
});

test("an unknown food is notFound — never the nearest thing", () => {
  const match = resolveFood("koshari");
  assert.equal(match.kind, "notFound");
  assert.equal(match.food, undefined);
});

test("raw and cooked forms of one food force a question", () => {
  const match = resolveFood("rice white long-grain regular");
  assert.equal(match.kind, "ambiguous");
  const preparations = new Set(match.candidates.map((f) => f.preparation));
  assert.ok(preparations.has("raw"));
  assert.ok(preparations.has("cooked"));
});
