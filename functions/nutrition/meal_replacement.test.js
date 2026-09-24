/**
 * Offline tests for `./meal_replacement.js`. `priceReplacementCandidates` and
 * `pickWholeFood` read the real bundled catalog (same as `food_db.test.js`);
 * the assertions are behavioral (whole food over processed, cooked over raw,
 * portion sized to the original's calories) rather than exact row ids.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  classifyMacroRole,
  macroShares,
  shareDistance,
  priceReplacementCandidates,
  pickWholeFood,
  MAX_CANDIDATES,
} = require("./meal_replacement");

test("classifyMacroRole: a clear protein source", () => {
  // ~4 kcal/g protein, ~4 kcal/g carbs, ~9 kcal/g fat.
  assert.equal(
      classifyMacroRole({proteinG: 40, carbsG: 0, fatG: 2}), "protein");
});

test("classifyMacroRole: a clear carb source", () => {
  assert.equal(
      classifyMacroRole({proteinG: 2, carbsG: 45, fatG: 1}), "carbs");
});

test("classifyMacroRole: a clear fat source", () => {
  assert.equal(
      classifyMacroRole({proteinG: 1, carbsG: 1, fatG: 20}), "fat");
});

test("classifyMacroRole: a near-even split is 'mixed', not a false lead", () => {
  // Roughly a third of calories each — no macro clears the 10-point margin.
  assert.equal(
      classifyMacroRole({proteinG: 10, carbsG: 10, fatG: 4.4}), "mixed");
});

test("classifyMacroRole: no macros at all is 'unknown', never a guess", () => {
  assert.equal(classifyMacroRole({proteinG: null, carbsG: null, fatG: null}), "unknown");
  assert.equal(classifyMacroRole({proteinG: 0, carbsG: 0, fatG: 0}), "unknown");
});

test("macroShares sums to 1 and is null with nothing to measure", () => {
  const shares = macroShares({proteinG: 20, carbsG: 20, fatG: 10});
  assert.ok(Math.abs(shares.protein + shares.carbs + shares.fat - 1) < 1e-9);
  assert.equal(macroShares({proteinG: 0, carbsG: 0, fatG: 0}), null);
});

test("shareDistance is 0 for identical shares and grows with divergence", () => {
  const a = {protein: 0.5, carbs: 0.3, fat: 0.2};
  assert.equal(shareDistance(a, a), 0);
  const closer = {protein: 0.52, carbs: 0.28, fat: 0.2};
  const farther = {protein: 0.1, carbs: 0.1, fat: 0.8};
  assert.ok(shareDistance(a, closer) < shareDistance(a, farther));
});

test("pickWholeFood prefers the plain cooked food over processed forms", () => {
  const beans = pickWholeFood("green beans", [], null);
  assert.match(beans.name, /cooked/i);
  assert.doesNotMatch(beans.name, /canned|frozen/i);
  const chicken = pickWholeFood("chicken breast", [], null);
  assert.doesNotMatch(chicken.name, /breaded|deli|sliced/i);
  const spinach = pickWholeFood("spinach", [], null);
  assert.doesNotMatch(spinach.name, /malabar|souffle/i);
});

test("pickWholeFood keeps a processed form the candidate asked for", () => {
  assert.match(pickWholeFood("canned tuna", [], null).name, /canned/i);
});

test("pickWholeFood honours an explicit preparation", () => {
  assert.equal(pickWholeFood("carrots", [], "raw").preparation, "raw");
});

test("pickWholeFood returns null for a name the catalog doesn't have", () => {
  assert.equal(pickWholeFood("zzqx unknown dish", [], null), null);
});

test("pickWholeFood finds the user's own food first", () => {
  const mine = {id: "custom:1", name: "Mama's okra stew", kcalPer100g: 90};
  assert.equal(pickWholeFood("okra stew", [mine], null), mine);
});

test("molokhia → realistic vegetables, priced and portioned to its calories",
    () => {
      const out = priceReplacementCandidates({
        originalName: "Molokhia",
        originalCalories: 70,
        candidates: [
          {name: "green beans"}, {name: "zucchini"}, {name: "okra"},
          {name: "grilled vegetable platter"},
        ],
      });
      const found = out.filter((c) => c.found);
      assert.equal(found.length, 3);
      for (const c of found) {
        assert.ok(c.foodId);
        // The portion is sized to ~the original's 70 kcal (within rounding
        // to 10 g) unless clamped by the 30–400 g bounds.
        assert.ok(c.portion.grams >= 30 && c.portion.grams <= 400);
        assert.ok(Math.abs(c.portion.kcal - 70) <= 15 ||
          c.portion.grams === 400);
        assert.doesNotMatch(c.catalogName, /soup|canned|stroganoff/i);
      }
      assert.deepEqual(out.find((c) => !c.found),
          {name: "grilled vegetable platter", found: false,
            reason: "notInCatalog"});
    });

test("the original food and avoided foods are never offered back", () => {
  const out = priceReplacementCandidates({
    originalName: "Okra",
    originalCalories: 60,
    candidates: [{name: "okra"}, {name: "spinach"}, {name: "zucchini"}],
    avoid: ["spinach"],
  });
  assert.deepEqual(out.map((c) => [c.name, c.found, c.reason || null]), [
    ["okra", false, "sameAsOriginal"],
    ["spinach", false, "avoided"],
    ["zucchini", true, null],
  ]);
});

test("candidates are capped and duplicates collapse", () => {
  const many = Array.from({length: MAX_CANDIDATES + 3}, () => ({name: "okra"}));
  const out = priceReplacementCandidates({
    originalName: "Molokhia", originalCalories: 70, candidates: many,
  });
  assert.equal(out.length, 1);
});
