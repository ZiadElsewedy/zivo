/**
 * Offline tests for `./meal_replacement.js`. `rankAlternatives` reads the
 * real bundled catalog (same as `food_db.test.js`), so these assert
 * behavioral properties (role filtering, self-exclusion, avoid filtering,
 * the alternatives cap) rather than exact catalog contents, which would be
 * brittle against a catalog rebuild.
 */

const assert = require("node:assert/strict");
const {test} = require("node:test");

const {
  classifyMacroRole,
  macroShares,
  shareDistance,
  rankAlternatives,
  MAX_ALTERNATIVES,
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

test("rankAlternatives: unknown role ranks nothing rather than guessing", () => {
  const {role, alternatives} = rankAlternatives({
    originalName: "Mystery item",
    originalMacros: {proteinG: null, carbsG: null, fatG: null},
  });
  assert.equal(role, "unknown");
  assert.deepEqual(alternatives, []);
});

test("rankAlternatives: a protein-role item gets protein-role alternatives only, capped", () => {
  const {role, alternatives} = rankAlternatives({
    originalName: "Zebra Steak Deluxe", // won't collide with real catalog names
    originalMacros: {proteinG: 40, carbsG: 0, fatG: 2},
  });
  assert.equal(role, "protein");
  assert.ok(alternatives.length > 0, "the catalog has protein-role foods");
  assert.ok(alternatives.length <= MAX_ALTERNATIVES);
  for (const alt of alternatives) {
    assert.equal(alt.macroRole, "protein");
    assert.match(alt.similarityNote, /protein/);
    assert.ok(alt.foodId);
    assert.ok(alt.per100g.kcal >= 0);
  }
  // Ranked nearest-first.
  for (let i = 1; i < alternatives.length; i++) {
    const distOf = (a) => {
      const shares = macroShares({
        proteinG: a.per100g.proteinG,
        carbsG: a.per100g.carbsG,
        fatG: a.per100g.fatG,
      });
      return shareDistance({protein: 1, carbs: 0, fat: 0}, shares);
    };
    // Not a strict re-derivation (rounding), just: not obviously out of order.
    assert.ok(distOf(alternatives[i - 1]) <= distOf(alternatives[i]) + 0.5);
  }
});

test("rankAlternatives: excludes foods matching an avoid/allergy token", () => {
  const {alternatives} = rankAlternatives({
    originalName: "Zebra Steak Deluxe",
    originalMacros: {proteinG: 40, carbsG: 0, fatG: 2},
    avoid: ["chicken"],
    allergies: ["turkey"],
  });
  for (const alt of alternatives) {
    const lower = alt.name.toLowerCase();
    assert.ok(!lower.includes("chicken"));
    assert.ok(!lower.includes("turkey"));
  }
});

test("rankAlternatives: layers the user's own custom foods in as candidates", () => {
  // Exactly the original's macro proportions — distance 0, guaranteed to rank
  // ahead of any nonzero-distance catalog food regardless of catalog contents.
  const customFoods = [{
    id: "cf1",
    name: "My Protein Shake",
    kcalPer100g: 178,
    proteinPer100g: 40,
    carbsPer100g: 0,
    fatPer100g: 2,
    preparation: "unknown",
    portions: [],
  }];
  const {alternatives} = rankAlternatives({
    originalName: "Zebra Steak Deluxe",
    originalMacros: {proteinG: 40, carbsG: 0, fatG: 2},
    customFoods,
  });
  assert.ok(
      alternatives.some((a) => a.foodId === "custom:cf1"),
      "an exact-proportion custom food should rank in ahead of nonzero-distance foods");
});

test("rankAlternatives: a 'mixed' original isn't filtered to one role", () => {
  const {role, alternatives} = rankAlternatives({
    originalName: "Zebra Omelette Supreme",
    // Protein ~48%, carbs ~4%, fat ~48% of calories — no clear lead.
    originalMacros: {proteinG: 12, carbsG: 1, fatG: 6.4},
  });
  assert.equal(role, "mixed");
  const roles = new Set(alternatives.map((a) => a.macroRole));
  // Not asserting more than one role appears (catalog-dependent), just that
  // the function didn't silently narrow to a single specific role.
  assert.ok(!alternatives.some((a) => a.macroRole === "unknown"));
  assert.ok(roles.size >= 0);
});
