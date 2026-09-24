/**
 * Meal replacement — pricing realistic alternatives to a plan item.
 *
 * The split of work (changed 2026-09-24): the MODEL proposes which foods are a
 * realistic swap — it knows what molokhia is, which meal it's in, and what an
 * Egyptian home cook would put there instead. THIS module supplies every
 * number: it resolves each proposal to a plain whole food in the catalog and
 * sizes a portion to the original item's calories. The earlier design ranked
 * the whole catalog by macro-share similarity alone and let no one decide
 * what a food *is*, which is how canned beef-stroganoff soup came back as a
 * replacement for molokhia. Used by `../ai/tools/read.js`'s
 * `search_food_alternatives` tool.
 *
 * `classifyMacroRole`/`macroShares` stay: the tool reports the original
 * item's macro role so the model can keep the swap in the same role.
 *
 * **No Dart mirror yet.** Every other pure engine in this codebase (coaching
 * rules, diet state, energy) is mirrored client-side with shared golden
 * vectors, because both the app and the coach need to agree on the same
 * answer. This one doesn't have that requirement yet — only the AI tool path
 * exists (see docs/DIET_AI_FOOD_ASSISTANT_ARCHITECTURE.md, Phase 4). A future
 * in-app "Replace" button (outside chat) would need a Dart port of
 * `priceReplacementCandidates`, at which point this earns golden
 * vectors like everything else here.
 */

const {rank, KCAL_PER_GRAM, tokenize} = require("./food_db");
const {customToFood} = require("./resolve");

/** @const {!Array<string>} The three roles a food's calories can come from. */
const ROLES = ["protein", "carbs", "fat"];

/**
 * A role only counts as the food's dominant one if its calorie share leads
 * the next-highest by at least this much — otherwise the food is "mixed" (a
 * balanced meal like eggs, not clearly a protein/carb/fat source). Matches
 * `food_db.js`'s `CLOSE_SCORE`-style "don't pretend a near-tie is a clean
 * answer" discipline, applied to macro shares instead of search scores.
 * @const {number}
 */
const DOMINANCE_MARGIN = 0.10;

/** @const {number} Candidates priced per call, at most. */
const MAX_CANDIDATES = 6;

/**
 * The share of calories each macro contributes, on the 4/4/9 Atwater factors
 * (`KCAL_PER_GRAM`, the same constants `nutritionFor`'s plausibility math
 * uses) — or null when there is nothing to measure (all three macros
 * zero/absent).
 * @param {{proteinG: ?number, carbsG: ?number, fatG: ?number}} macros
 * @return {?{protein: number, carbs: number, fat: number}}
 */
function macroShares(macros) {
  const proteinKcal =
    Math.max(0, Number(macros.proteinG) || 0) * KCAL_PER_GRAM.protein;
  const carbsKcal =
    Math.max(0, Number(macros.carbsG) || 0) * KCAL_PER_GRAM.carbs;
  const fatKcal = Math.max(0, Number(macros.fatG) || 0) * KCAL_PER_GRAM.fat;
  const total = proteinKcal + carbsKcal + fatKcal;
  if (total <= 0) return null;
  return {
    protein: proteinKcal / total,
    carbs: carbsKcal / total,
    fat: fatKcal / total,
  };
}

/**
 * The macro role a food's calories are mostly coming from — `"protein"`,
 * `"carbs"` or `"fat"` when one clearly leads, `"mixed"` when none does by
 * enough to call it, or `"unknown"` when there's nothing to measure at all
 * (no macros given).
 * @param {{proteinG: ?number, carbsG: ?number, fatG: ?number}} macros
 * @return {string}
 */
function classifyMacroRole(macros) {
  const shares = macroShares(macros);
  if (!shares) return "unknown";
  const sorted = ROLES.map((r) => [r, shares[r]]).sort((a, b) => b[1] - a[1]);
  const [topRole, topShare] = sorted[0];
  const secondShare = sorted[1][1];
  return (topShare - secondShare) >= DOMINANCE_MARGIN ? topRole : "mixed";
}

/**
 * Euclidean distance between two macro-share vectors — the closer to 0, the
 * more alike two foods' calories are made of, independent of their serving
 * size or absolute calories.
 * @param {{protein: number, carbs: number, fat: number}} a
 * @param {{protein: number, carbs: number, fat: number}} b
 * @return {number}
 */
function shareDistance(a, b) {
  const dp = a.protein - b.protein;
  const dc = a.carbs - b.carbs;
  const df = a.fat - b.fat;
  return Math.sqrt(dp * dp + dc * dc + df * df);
}

/**
 * Whether `name` contains any of `tokens` as a whole word — the same
 * "over-splitting is the safe direction" discipline the allergen gate uses
 * elsewhere (`plan_fitting.js`): a candidate is excluded on any match, never
 * partially trusted.
 * @param {string} name
 * @param {!Array<string>} avoidTokens Lowercased single words to avoid.
 * @return {boolean}
 */
function nameMatchesAny(name, avoidTokens) {
  if (avoidTokens.length === 0) return false;
  const nameTokens = tokenize(name);
  return avoidTokens.some((t) => nameTokens.has(t));
}

// Words in a catalog name that mark a PROCESSED or prepared form of a food —
// what a person swapping one item in a home-cooked meal almost never means
// by "green beans" or "chicken breast". Not a blocklist of foods: a candidate
// that asks for one of these words ("canned tuna") keeps it.
const PROCESSED_WORDS = new Set([
  "canned", "frozen", "breaded", "deli", "sliced", "prepackaged", "souffle",
  "soup", "sauce", "gravy", "mix", "flour", "dehydrated", "powder", "dry",
  "instant", "ready", "serve", "heat", "microwaved", "fried", "battered",
  "sweetened", "syrup", "juice", "baby", "infant", "restaurant", "fast",
  "roll", "sausage", "luncheon", "stuffed", "glazed", "candied", "pickled",
  "dressing", "spread", "substitute", "imitation", "cured", "smoked",
  "strips", "breakfast", "jerky",
]);

// USDA categories that are prepared/branded/institutional food rather than a
// food itself. A candidate in one is heavily penalised, never excluded — the
// user may genuinely have asked for a restaurant dish.
const PROCESSED_CATEGORIES = new Set([
  "Fast Foods", "Restaurant Foods", "Baby Foods", "Soups, Sauces, and Gravies",
  "Sausages and Luncheon Meats", "Meals, Entrees, and Side Dishes",
  "Snacks", "Sweets",
]);

// How many best-matching catalog rows are considered for one candidate
// before the whole-food preference picks among them.
const CONSIDERED_MATCHES = 40;

/**
 * The catalog food a candidate NAME most plausibly means, preferring the plain
 * whole food over a processed form ("green beans" → boiled green beans, not
 * canned; "chicken breast" → roasted breast meat, not breaded tenders), and
 * the cooked form over raw for a meal item (plan meals are eaten cooked) —
 * unless the candidate's own words ask for the processed form or a
 * preparation. Deterministic: the same name always resolves to the same row.
 *
 * @param {string} name A candidate food name (from the model).
 * @param {!Array<Object>} customFoods The user's own foods (catalog shape).
 * @param {?string} preparation 'raw'|'cooked'|'dry'|null.
 * @return {?Object} A catalog-shaped food, or null when nothing matches.
 */
function pickWholeFood(name, customFoods, preparation) {
  const wanted = tokenize(name);
  if (wanted.size === 0) return null;
  // The user's own foods first — if they've saved it, that's what they mean.
  for (const food of customFoods) {
    const tokens = tokenize(food.name);
    if ([...wanted].every((t) => tokens.has(t))) return food;
  }
  // The catalog names foods in the plural ("Potatoes, boiled…"), people
  // don't — so the plural of the last word is searched too.
  const words = name.trim().split(/\s+/);
  const last = words[words.length - 1];
  const stem = words.slice(0, -1);
  const plural = [...stem,
    /(s|x|ch|sh|o)$/i.test(last) ? `${last}es` : `${last}s`].join(" ");
  // …and the other way round ("eggs" → "Egg, whole, cooked").
  const singular = /[^s]s$/i.test(last) ?
    [...stem, last.slice(0, -1)].join(" ") : name;
  const byId = new Map();
  for (const hit of [...rank(name), ...rank(plural), ...rank(singular)]) {
    const prior = byId.get(hit.food.id);
    if (!prior || hit.score > prior.score) byId.set(hit.food.id, hit);
  }
  const ranked = [...byId.values()]
      .sort((a, b) => b.score - a.score || a.food.id.localeCompare(b.food.id))
      .slice(0, CONSIDERED_MATCHES);
  if (ranked.length === 0) return null;
  const wantedLoose =
      new Set([...wanted, ...tokenize(plural), ...tokenize(singular)]);
  let best = null;
  for (const {food, score} of ranked) {
    let adjusted = score;
    // A qualifier in the food's own name that the candidate didn't ask for
    // makes it a different food: "Malabar spinach", "Sweet potato".
    for (const token of food._lead) {
      if (!wantedLoose.has(token)) adjusted -= 12;
    }
    for (const token of food._tokens) {
      if (PROCESSED_WORDS.has(token) && !wanted.has(token)) adjusted -= 25;
    }
    if (PROCESSED_CATEGORIES.has(food.category)) adjusted -= 40;
    // An all-caps word is a brand (UNCLE BEN'S, SMART SOUP): a branded row is
    // one product, not the food.
    if (/\b(?!USDA\b)[A-Z]{3,}\b/.test(food.name)) adjusted -= 30;
    const prep = food.preparation;
    if (preparation) {
      if (prep === preparation) adjusted += 15;
    } else if (prep === "cooked") {
      // Plan meals are eaten cooked, and raw vs cooked differ up to ~3x in
      // calories (rice, lentils) — the wrong basis would mis-size the swap.
      adjusted += 22;
    } else if (prep === "raw") {
      adjusted += 4;
    }
    if (!best || adjusted > best.adjusted ||
        (adjusted === best.adjusted && food.id < best.food.id)) {
      best = {food, adjusted};
    }
  }
  return best.food;
}

/**
 * Prices the model's candidate replacements for a plan item against the real
 * catalog — the model proposes WHICH foods would be a realistic swap (it
 * understands cuisine, the meal, and what kind of food the item is); ZIVO
 * supplies EVERY number. Each found candidate gets a suggested portion sized
 * to the original item's calories, so the swap keeps the plan's day about
 * where it was.
 *
 * Replaces the previous macro-share ranking over the whole catalog, which
 * optimised for "calories made of the same macros" with no idea what a food
 * IS — and so offered canned beef-stroganoff soup in place of molokhia.
 *
 * @param {!Object} args
 * @param {string} args.originalName The item being replaced.
 * @param {?number} args.originalCalories Its calories in the plan, if known.
 * @param {!Array<{name: string, preparation: (?string|undefined)}>}
 *   args.candidates The model's proposals.
 * @param {!Array<Object>=} args.customFoods The user's own foods
 *   (`store.listCustomFoods` rows).
 * @param {!Array<string>=} args.avoid Foods the user said they don't want.
 * @return {!Array<!Object>} One entry per candidate, in the model's order:
 *   `{name, found: true, foodId, catalogName, per100g, portion}` or
 *   `{name, found: false, reason}`.
 */
function priceReplacementCandidates({
  originalName, originalCalories, candidates, customFoods = [], avoid = [],
}) {
  const excludeTokens = avoid
      .map((t) => String(t || "").trim().toLowerCase())
      .filter((t) => t.length > 0);
  const originalTokens = tokenize(originalName);
  const custom = (customFoods || []).map(customToFood);
  const seen = new Set();
  const out = [];
  for (const candidate of candidates.slice(0, MAX_CANDIDATES)) {
    const name = String(candidate && candidate.name || "").trim();
    if (!name) continue;
    if (nameMatchesAny(name, excludeTokens)) {
      out.push({name, found: false, reason: "avoided"});
      continue;
    }
    const nameTokens = tokenize(name);
    if (nameTokens.size > 0 &&
        [...nameTokens].every((t) => originalTokens.has(t))) {
      out.push({name, found: false, reason: "sameAsOriginal"});
      continue;
    }
    const food = pickWholeFood(name, custom, candidate.preparation || null);
    if (!food) {
      out.push({name, found: false, reason: "notInCatalog"});
      continue;
    }
    if (seen.has(food.id)) continue;
    seen.add(food.id);
    const kcal100 = food.kcalPer100g;
    // A portion with about the original item's calories; bounded so a
    // near-zero-calorie vegetable isn't prescribed by the kilo, and rounded
    // to 10 g because nobody weighs 173 g of courgette.
    let grams = 150;
    if (Number.isFinite(originalCalories) && originalCalories > 0 &&
        kcal100 > 0) {
      grams = originalCalories / (kcal100 / 100);
    }
    grams = Math.min(400, Math.max(30, Math.round(grams / 10) * 10));
    const factor = grams / 100;
    out.push({
      name,
      found: true,
      foodId: food.id,
      catalogName: food.name,
      per100g: {
        kcal: Math.round(kcal100),
        proteinG: food.proteinPer100g,
        carbsG: food.carbsPer100g,
        fatG: food.fatPer100g,
      },
      portion: {
        grams,
        kcal: Math.round(kcal100 * factor),
        proteinG: Math.round(food.proteinPer100g * factor * 10) / 10,
        carbsG: Math.round(food.carbsPer100g * factor * 10) / 10,
        fatG: Math.round(food.fatPer100g * factor * 10) / 10,
      },
    });
  }
  return out;
}

module.exports = {
  classifyMacroRole,
  macroShares,
  shareDistance,
  priceReplacementCandidates,
  pickWholeFood,
  DOMINANCE_MARGIN,
  MAX_CANDIDATES,
};
