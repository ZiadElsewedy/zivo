#!/usr/bin/env node
/**
 * Builds ZIVO's bundled nutrition catalog (`assets/nutrition/foods.json`) from
 * USDA FoodData Central bulk exports.
 *
 * **Why this script exists at all.** ZIVO's whole trust argument is that a
 * calorie figure comes from a verified source, never from a model. That only
 * holds if the catalog itself is derived, mechanically and reproducibly, from
 * a real dataset — so every row carries the `fdcId` it came from, and anyone
 * can re-run this and get byte-identical output. A hand-written catalog would
 * reproduce exactly the problem this feature exists to solve, one layer down.
 * See docs/DIET_COACH_AUDIT.md (T1/T2).
 *
 * Source data (US government, public domain — https://fdc.nal.usda.gov):
 *   - Foundation Foods  — small, deeply analysed core set.
 *   - SR Legacy         — the broad staple reference set.
 *
 * Usage:
 *   node scripts/nutrition/build_food_db.js \
 *     --foundation <FoodData_Central_foundation_food_json_*.json> \
 *     --sr-legacy  <FoodData_Central_sr_legacy_food_json_*.json> \
 *     --out assets/nutrition/foods.json
 *
 * Writes the catalog TWICE: once for the app bundle and once under
 * `functions/nutrition/` for the server. The two copies must be byte-identical
 * — the app and the coach quoting different calorie figures for the same food
 * is precisely the class of bug this rebuild exists to eliminate — and a test
 * on each side asserts the shared checksum.
 *
 * Deterministic: same inputs → same bytes. Rows are sorted by id, keys are
 * written in a fixed order, and numbers are rounded to a fixed precision, so
 * the asset's checksum is a meaningful thing to assert in a test.
 */

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

// FDC nutrient ids. Energy has three possible carriers; we prefer the directly
// reported kcal value and fall back to the Atwater-derived ones.
const NUTRIENT = {
  ENERGY_KCAL: 1008,
  ENERGY_ATWATER_GENERAL: 2047,
  ENERGY_ATWATER_SPECIFIC: 2048,
  PROTEIN: 1003,
  FAT: 1004,
  CARBS: 1005,
};

// Categories that are branded products, restaurant items or composite meals
// rather than foods a person weighs. They bloat the asset and pollute search
// with things like "Pillsbury Golden Layer Buttermilk Biscuits", while the
// nutrition of a specific brand's product is exactly what a bundled snapshot
// gets wrong first when the recipe changes.
const EXCLUDED_CATEGORIES = new Set([
  "Restaurant Foods",
  "Fast Foods",
  "Branded Food Products Database",
  "Baby Foods",
]);

/**
 * How a food was prepared, derived from the USDA description. This is a real
 * dimension of the data, not a nicety: 100 g of raw chicken and 100 g of
 * cooked chicken differ by roughly a third, and getting it wrong is where
 * consumer trackers quietly lose their accuracy.
 *
 * `unknown` is deliberately preserved rather than defaulted — a resolver that
 * can't tell raw from cooked should ask, not guess.
 */
const STATE = {RAW: "raw", COOKED: "cooked", DRY: "dry", UNKNOWN: "unknown"};

/**
 * Derives a preparation state from a USDA description.
 * @param {string} description
 * @return {string} One of STATE.
 */
function stateFor(description) {
  const d = description.toLowerCase();
  // Order matters: "cooked, raw" never occurs, but "dry roasted" does, and a
  // dried food that is then cooked reads as cooked.
  if (/\b(cooked|boiled|roasted|grilled|broiled|baked|braised|steamed|fried|stewed|poached|sauteed|sautéed)\b/.test(d)) {
    return STATE.COOKED;
  }
  if (/\braw\b/.test(d)) return STATE.RAW;
  if (/\b(dry|dried|dehydrated|uncooked)\b/.test(d)) return STATE.DRY;
  return STATE.UNKNOWN;
}

/**
 * The per-100g amount of `nutrientId` in `food`, or null when absent.
 * @param {!Object} food An FDC food record.
 * @param {number} nutrientId
 * @param {string=} requireUnit Only accept the value if the unit matches.
 * @return {?number}
 */
function nutrientAmount(food, nutrientId, requireUnit) {
  const list = Array.isArray(food.foodNutrients) ? food.foodNutrients : [];
  for (const entry of list) {
    const nutrient = entry && entry.nutrient;
    if (!nutrient || nutrient.id !== nutrientId) continue;
    if (requireUnit &&
        String(nutrient.unitName || "").toLowerCase() !== requireUnit) {
      continue;
    }
    const amount = entry.amount;
    if (typeof amount === "number" && Number.isFinite(amount) && amount >= 0) {
      return amount;
    }
  }
  return null;
}

/**
 * Energy in kcal per 100 g. Prefers the directly reported kcal figure, then
 * the Atwater-derived ones — never a kJ value silently read as kcal.
 * @param {!Object} food
 * @return {?number}
 */
function energyKcal(food) {
  for (const id of [
    NUTRIENT.ENERGY_KCAL,
    NUTRIENT.ENERGY_ATWATER_SPECIFIC,
    NUTRIENT.ENERGY_ATWATER_GENERAL,
  ]) {
    const value = nutrientAmount(food, id, "kcal");
    if (value !== null) return value;
  }
  return null;
}

/**
 * Household portions for a food ("1 cup" → 140 g), so a user who doesn't own
 * scales can still log something the calculator can work with exactly.
 * Deduplicated by label, capped, and sorted for determinism.
 * @param {!Object} food
 * @return {!Array<!Object>} `[{label, grams}]`
 */
function portionsFor(food) {
  const list = Array.isArray(food.foodPortions) ? food.foodPortions : [];
  const byLabel = new Map();
  for (const portion of list) {
    const grams = portion && portion.gramWeight;
    if (typeof grams !== "number" || !Number.isFinite(grams) || grams <= 0) {
      continue;
    }
    const unit = portion.measureUnit && portion.measureUnit.name;
    const parts = [
      portion.amount && portion.amount !== 1 ? String(portion.amount) : null,
      unit && unit !== "undetermined" ? unit : null,
      portion.modifier && !/^\d+$/.test(String(portion.modifier)) ?
        String(portion.modifier) : null,
    ].filter(Boolean);
    const label = parts.join(" ").trim().toLowerCase();
    if (!label || label.length > 40) continue;
    // A portion's grams are per its stated amount; normalize to "one of it".
    const perOne = portion.amount && portion.amount > 0 ?
      grams / portion.amount : grams;
    if (!byLabel.has(label)) {
      byLabel.set(label, Math.round(perOne * 10) / 10);
    }
  }
  return [...byLabel.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .slice(0, 6)
      .map(([label, grams]) => ({label, grams}));
}

/** @param {number} v @return {number} v to one decimal place. */
function round1(v) {
  return Math.round(v * 10) / 10;
}

/**
 * Converts one FDC food record into a catalog row, or null when it can't be
 * used. A row without all four macro figures is dropped rather than stored
 * with holes: a partial row would silently under-count a meal, which is worse
 * than honestly not having the food at all.
 * @param {!Object} food
 * @param {string} dataset 'foundation' | 'sr_legacy'
 * @return {?Object}
 */
function toRow(food, dataset) {
  // The exports contain occasional null entries; skip rather than crash the
  // whole build on one bad record.
  if (!food || typeof food !== "object") return null;
  const fdcId = food.fdcId;
  const description = typeof food.description === "string" ?
    food.description.trim() : "";
  if (!Number.isInteger(fdcId) || !description) return null;

  const category = food.foodCategory && food.foodCategory.description ?
    String(food.foodCategory.description) : null;
  if (category && EXCLUDED_CATEGORIES.has(category)) return null;

  const kcal = energyKcal(food);
  const protein = nutrientAmount(food, NUTRIENT.PROTEIN, "g");
  const carbs = nutrientAmount(food, NUTRIENT.CARBS, "g");
  const fat = nutrientAmount(food, NUTRIENT.FAT, "g");
  if (kcal === null || protein === null || carbs === null || fat === null) {
    return null;
  }
  // A food whose macros are wildly inconsistent with its stated energy is a
  // bad record, not a discovery. 4/4/9 with generous slack for fibre, alcohol
  // and rounding.
  const impliedKcal = protein * 4 + carbs * 4 + fat * 9;
  if (kcal > 0 && Math.abs(impliedKcal - kcal) > Math.max(120, kcal * 0.45)) {
    return null;
  }

  return {
    fdcId,
    name: description,
    category,
    state: stateFor(description),
    kcal: round1(kcal),
    protein: round1(protein),
    carbs: round1(carbs),
    fat: round1(fat),
    portions: portionsFor(food),
    dataset,
  };
}

/**
 * @param {!Array<string>} argv
 * @return {!Object} Parsed `--key value` flags.
 */
function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 2) {
    const key = argv[i].replace(/^--/, "");
    args[key] = argv[i + 1];
  }
  return args;
}

/**
 * Reads one FDC export and returns its food array.
 * @param {string} file
 * @param {string} key Top-level key ('FoundationFoods' | 'SRLegacyFoods').
 * @return {!Array<Object>}
 */
function readExport(file, key) {
  if (!file) return [];
  const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
  const foods = parsed[key];
  if (!Array.isArray(foods)) {
    throw new Error(`${file}: expected a "${key}" array`);
  }
  return foods;
}

function main() {
  const args = parseArgs(process.argv);
  const out = args.out || "assets/nutrition/foods.json";

  const rows = [];
  const seen = new Set();
  const sources = [];

  for (const [file, key, dataset] of [
    [args.foundation, "FoundationFoods", "foundation"],
    [args["sr-legacy"], "SRLegacyFoods", "sr_legacy"],
  ]) {
    if (!file) continue;
    const foods = readExport(file, key);
    let kept = 0;
    for (const food of foods) {
      const row = toRow(food, dataset);
      // Foundation is processed first and wins on collision: its analyses are
      // newer and more thorough than SR Legacy's.
      if (!row || seen.has(row.fdcId)) continue;
      seen.add(row.fdcId);
      rows.push(row);
      kept++;
    }
    sources.push({dataset, file: path.basename(file), total: foods.length, kept});
  }

  // Sorted by fdcId so the output is stable regardless of input order.
  rows.sort((a, b) => a.fdcId - b.fdcId);

  // Rows are written as positional tuples, not objects. Repeating ten key
  // names across 7,000+ rows costs roughly a third of the file for no
  // information — and this asset ships inside the app. `fields` keeps the
  // format self-describing, so it stays mechanical rather than magic.
  const catalog = {
    schemaVersion: 1,
    // Recorded in the asset itself so the app can always say where a number
    // came from, and a stale catalog is visible rather than invisible.
    source: "USDA FoodData Central (public domain) — https://fdc.nal.usda.gov",
    builtFrom: sources,
    foodCount: rows.length,
    // Per 100 g for every row; portions are [label, gramsPerOne] pairs.
    basis: "per100g",
    fields: [
      "fdcId", "name", "category", "state",
      "kcal", "protein", "carbs", "fat", "portions",
    ],
    foods: rows.map((r) => [
      r.fdcId, r.name, r.category, r.state,
      r.kcal, r.protein, r.carbs, r.fat,
      r.portions.map((p) => [p.label, p.grams]),
    ]),
  };

  const json = JSON.stringify(catalog, null, 0);
  const sha = crypto.createHash("sha256").update(json).digest("hex");

  // Both copies, plus the checksum both suites assert against.
  const targets = [out, args["also-out"] || "functions/nutrition/foods.json"];
  for (const target of targets) {
    fs.mkdirSync(path.dirname(target), {recursive: true});
    fs.writeFileSync(target, `${json}\n`);
  }
  fs.writeFileSync(
      "assets/nutrition/foods.sha256",
      `${sha}\n`,
  );

  process.stdout.write(
      `${targets.join("\n")}\n` +
      `  foods:     ${rows.length}\n` +
      `  bytes:     ${json.length}\n` +
      `  sha256:    ${sha}\n` +
      sources.map((s) =>
        `  ${s.dataset}: kept ${s.kept} of ${s.total} (${s.file})\n`).join(""),
  );
}

if (require.main === module) main();

module.exports = {toRow, stateFor, energyKcal, portionsFor, STATE};
