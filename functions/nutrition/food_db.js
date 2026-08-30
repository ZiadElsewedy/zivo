/**
 * The server's half of ZIVO's nutrition catalog — the exact mirror of
 * `lib/features/diet/data/bundled_food_database.dart` and
 * `lib/features/diet/domain/nutrition/nutrition_calculator.dart`.
 *
 * **Why a mirror at all.** The app and the coach must quote the same number
 * for the same food. Two implementations is a risk, so it is contained two
 * ways: both read the identical asset (written by
 * `scripts/nutrition/build_food_db.js`, checksum asserted on both sides), and
 * both are run against the same golden vectors in
 * `test/fixtures/nutrition_vectors.json`. If they ever drift, a test fails
 * rather than a user getting two different answers.
 *
 * Loading is lazy and memoized: a turn that never asks about a food never
 * parses the ~1 MB catalog.
 */

const fs = require("node:fs");
const path = require("node:path");

const CATALOG_PATH = path.join(__dirname, "foods.json");

/** Energy per gram, for the macro arithmetic. Mirrors the Dart constants. */
const KCAL_PER_GRAM = {protein: 4, carbs: 4, fat: 9};

/**
 * Mass units convertible with no assumption about the food. Volume is
 * deliberately absent — see `unresolvedQuantity`.
 */
const GRAMS_PER_MASS_UNIT = {
  "g": 1, "gram": 1, "grams": 1,
  "kg": 1000,
  "oz": 28.349523125, "ounce": 28.349523125, "ounces": 28.349523125,
  "lb": 453.59237, "pound": 453.59237, "pounds": 453.59237,
};

const PIECE_UNITS = ["pcs", "pc", "piece", "pieces", "each", "item"];
const PIECE_CANDIDATES = [
  "piece", "each", "medium", "large", "small", "fillet", "slice", "serving",
];

// Ranking/ambiguity constants — must match the Dart side exactly.
const CLOSE_SCORE = 12;
const MAX_CANDIDATES = 5;
const MATERIAL_ENERGY_GAP = 0.25;

let cached = null;

/**
 * @param {number} v
 * @return {number} `v` rounded to one decimal place.
 */
function round1(v) {
  return Math.round(v * 10) / 10;
}

/**
 * Lowercased word tokens, punctuation stripped. Deliberately simple and
 * deterministic — no stemming, nothing that could make "chicken" quietly
 * match "chickpea". Mirrors the Dart `_tokenize`.
 * @param {string} text
 * @return {!Set<string>}
 */
function tokenize(text) {
  const tokens = new Set();
  for (const raw of String(text).toLowerCase().split(/[^a-z0-9]+/)) {
    if (raw.length > 1) tokens.add(raw);
  }
  return tokens;
}

/**
 * The part of a USDA description before the first comma — the food itself,
 * with everything after it being qualification.
 * @param {string} name
 * @return {string}
 */
function leadSegment(name) {
  const comma = name.indexOf(",");
  return comma === -1 ? name : name.slice(0, comma);
}

/**
 * Parses the catalog once and builds its search index.
 * @param {string=} file Override, for tests.
 * @return {!Object}
 */
function loadCatalog(file) {
  if (cached && !file) return cached;
  const decoded = JSON.parse(fs.readFileSync(file || CATALOG_PATH, "utf8"));
  const foods = [];
  const byId = new Map();
  for (const row of decoded.foods || []) {
    if (!Array.isArray(row) || row.length < 9) continue;
    const [fdcId, name, category, state, kcal, protein, carbs, fat, portions] =
      row;
    if (typeof fdcId !== "number" || typeof name !== "string" || !name) continue;
    const food = {
      id: `usda:${fdcId}`,
      name,
      category: typeof category === "string" ? category : null,
      preparation: typeof state === "string" ? state : "unknown",
      kcalPer100g: Number(kcal) || 0,
      proteinPer100g: Number(protein) || 0,
      carbsPer100g: Number(carbs) || 0,
      fatPer100g: Number(fat) || 0,
      source: "usdaFdc",
      sourceRef: String(fdcId),
      portions: (Array.isArray(portions) ? portions : [])
          .filter((p) => Array.isArray(p) && typeof p[0] === "string" &&
            typeof p[1] === "number")
          .map((p) => ({label: p[0], grams: p[1]})),
      _tokens: tokenize(name),
      _lead: tokenize(leadSegment(name)),
    };
    foods.push(food);
    byId.set(food.id, food);
  }
  const catalog = {meta: decoded, foods, byId};
  if (!file) cached = catalog;
  return catalog;
}

/**
 * Best-first matches for `query`. Deterministic: ties break on id.
 * @param {string} query
 * @param {!Object=} opts `{preparation, catalog}` overrides.
 * @return {!Array<{food: !Object, score: number}>}
 */
function rank(query, opts) {
  const {preparation, catalog} = opts || {};
  const cat = catalog || loadCatalog();
  const queryTokens = tokenize(query);
  if (queryTokens.size === 0) return [];

  const results = [];
  for (const food of cat.foods) {
    if (preparation && food.preparation !== preparation) continue;

    let matched = 0;
    for (const token of queryTokens) {
      if (food._tokens.has(token)) matched++;
    }
    // Every word the user typed has to appear — partial matches are how a
    // search for "chicken breast" ends up returning chicken soup.
    if (matched < queryTokens.size) continue;

    let score = 60;
    let inLead = 0;
    for (const token of queryTokens) {
      if (food._lead.has(token)) inLead++;
    }
    score += 30 * (inLead / queryTokens.size);
    score -= (food._tokens.size - queryTokens.size) * 1.6;
    results.push({food, score});
  }

  results.sort((a, b) =>
    b.score - a.score || a.food.id.localeCompare(b.food.id));
  return results;
}

/**
 * Whether close matches differ enough in energy that choosing one for the user
 * would be a guess with real consequences — the raw-versus-cooked test.
 * @param {!Array<{food: !Object}>} contenders
 * @return {boolean}
 */
function disagreeMaterially(contenders) {
  let min = contenders[0].food.kcalPer100g;
  let max = min;
  for (const {food} of contenders) {
    if (food.kcalPer100g < min) min = food.kcalPer100g;
    if (food.kcalPer100g > max) max = food.kcalPer100g;
  }
  if (max <= 0) return false;
  return (max - min) / max > MATERIAL_ENERGY_GAP;
}

/**
 * Resolves `query` to exactly one of
 * `{kind:'resolved'|'ambiguous'|'notFound'}`. The three outcomes are distinct
 * on purpose — see the Dart `FoodMatch`.
 * @param {string} query
 * @param {!Object=} opts `{preparation, catalog}` overrides.
 * @return {!Object}
 */
function resolveFood(query, opts) {
  const ranked = rank(query, opts);
  if (ranked.length === 0) return {kind: "notFound", query};

  const best = ranked[0];
  const contenders = ranked
      .filter((s) => s.score >= best.score - CLOSE_SCORE)
      .slice(0, MAX_CANDIDATES);

  if (contenders.length > 1 && disagreeMaterially(contenders)) {
    return {kind: "ambiguous", query, candidates: contenders.map((s) => s.food)};
  }
  return {
    kind: "resolved",
    food: best.food,
    alternatives: ranked.slice(1, MAX_CANDIDATES).map((s) => s.food),
  };
}

/**
 * `quantity` of `unit` in grams of `food`, or `{unresolved: reason}`.
 * @param {!Object} food
 * @param {number} quantity
 * @param {string} unit
 * @return {number|!Object}
 */
function gramsFor(food, quantity, unit) {
  const measures = food.portions.map((p) => p.label);
  if (!Number.isFinite(quantity) || quantity <= 0) {
    return {unresolved: "invalidQuantity", unit, availableMeasures: measures};
  }
  const normalized = String(unit).trim().toLowerCase();

  const massFactor = GRAMS_PER_MASS_UNIT[normalized];
  if (massFactor !== undefined) return quantity * massFactor;

  const named = food.portions.find((p) => p.label.toLowerCase() === normalized);
  if (named) return quantity * named.grams;

  if (PIECE_UNITS.includes(normalized)) {
    for (const candidate of PIECE_CANDIDATES) {
      const portion = food.portions.find(
          (p) => p.label.toLowerCase() === candidate);
      if (portion) return quantity * portion.grams;
    }
  }

  // No density is ever assumed: "100ml of olive oil is 100g" is wrong by ~8%,
  // and for flour by a third. Refusing and saying what WOULD work is the
  // honest answer.
  return {unresolved: "unknownMeasure", unit, availableMeasures: measures};
}

/**
 * The nutrition of `quantity` `unit` of `food`, or `{unresolved: reason}`.
 *
 * The ONLY place the server turns a food and an amount into calories. Nothing
 * else may do this arithmetic — least of all the model.
 * @param {!Object} food
 * @param {number} quantity
 * @param {string} unit
 * @return {!Object}
 */
function nutritionFor(food, quantity, unit) {
  const grams = gramsFor(food, quantity, unit);
  if (typeof grams !== "number") return grams;

  const factor = grams / 100;
  return {
    foodId: food.id,
    name: food.name,
    quantity,
    unit,
    grams: round1(grams),
    kcal: Math.round(food.kcalPer100g * factor),
    proteinG: round1(food.proteinPer100g * factor),
    carbsG: round1(food.carbsPer100g * factor),
    fatG: round1(food.fatPer100g * factor),
    source: food.source,
    sourceRef: food.sourceRef,
  };
}

/**
 * @param {string} id
 * @param {!Object=} catalog
 * @return {?Object}
 */
function foodById(id, catalog) {
  return (catalog || loadCatalog()).byId.get(id) || null;
}

module.exports = {
  loadCatalog,
  resolveFood,
  foodById,
  nutritionFor,
  gramsFor,
  rank,
  tokenize,
  CATALOG_PATH,
  KCAL_PER_GRAM,
};
