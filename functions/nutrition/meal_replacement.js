/**
 * Meal replacement — ranking alternatives to a plan item by what it's
 * NUTRITIONALLY FOR, not just its name or its calorie count.
 *
 * Pure and deterministic, like `../ai/plan_fitting.js` and the coaching engine
 * (`../diet/rules.js`) — the model doesn't decide which foods are similar, this
 * does. Used by `../ai/tools/meal_replacement.js`'s `suggest_meal_replacement`
 * tool.
 *
 * **No Dart mirror yet.** Every other pure engine in this codebase (coaching
 * rules, diet state, energy) is mirrored client-side with shared golden
 * vectors, because both the app and the coach need to agree on the same
 * answer. This one doesn't have that requirement yet — only the AI tool path
 * exists (see docs/DIET_AI_FOOD_ASSISTANT_ARCHITECTURE.md, Phase 4). A future
 * in-app "Replace" button (outside chat) would need a Dart port of
 * `classifyMacroRole`/`rankAlternatives`, at which point this earns golden
 * vectors like everything else here.
 */

const {loadCatalog, KCAL_PER_GRAM, tokenize} = require("./food_db");
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

/** @const {number} Alternatives returned, at most — mirrors `MAX_CANDIDATES`. */
const MAX_ALTERNATIVES = 5;

/**
 * The share of calories each macro contributes, on the 4/4/9 Atwater factors
 * (`KCAL_PER_GRAM`, the same constants `nutritionFor`'s plausibility math
 * uses) — or null when there is nothing to measure (all three macros
 * zero/absent).
 * @param {{proteinG: ?number, carbsG: ?number, fatG: ?number}} macros
 * @return {?{protein: number, carbs: number, fat: number}}
 */
function macroShares(macros) {
  const proteinKcal = Math.max(0, Number(macros.proteinG) || 0) * KCAL_PER_GRAM.protein;
  const carbsKcal = Math.max(0, Number(macros.carbsG) || 0) * KCAL_PER_GRAM.carbs;
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
 * A short, deterministic sentence for why a candidate was suggested — no
 * model involved, so it never says more than the numbers actually show.
 * @param {string} originalRole The item being replaced's classified role.
 * @return {string}
 */
function similarityNoteFor(originalRole) {
  if (originalRole === "protein" || originalRole === "carbs" ||
      originalRole === "fat") {
    return `Similar ${originalRole} profile`;
  }
  return "Comparable macro balance";
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

/**
 * Ranks catalog (+ the user's own custom) foods as replacements for a plan
 * item, by how alike their calories' macro composition is — never by name,
 * never by the model's judgement.
 *
 * @param {!Object} args
 * @param {string} args.originalName The item being replaced, for the
 *   "don't just suggest the same food back" exclusion.
 * @param {{proteinG: ?number, carbsG: ?number, fatG: ?number}} args.originalMacros
 * @param {!Array<Object>=} args.customFoods The user's own foods
 *   (`store.listCustomFoods` rows), layered in as candidates too.
 * @param {!Array<string>=} args.avoid Foods to exclude — the model's own
 *   knowledge of what the user has said in this conversation, NOT read from
 *   any stored preference (nothing persists `PlanPreferences` server-side).
 * @param {!Array<string>=} args.allergies Same as `avoid`, kept as a separate
 *   list purely so a caller can log/report them distinctly; both exclude the
 *   same way here.
 * @return {{role: string, alternatives: !Array<!Object>}} `role` is the
 *   original item's classified macro role (see `classifyMacroRole`);
 *   `alternatives` is empty when `role` is `"unknown"` (nothing to rank
 *   against) or nothing survives the avoid/allergy filter.
 */
function rankAlternatives({
  originalName, originalMacros, customFoods = [], avoid = [], allergies = [],
}) {
  const role = classifyMacroRole(originalMacros);
  if (role === "unknown") return {role, alternatives: []};

  const originalShares = macroShares(originalMacros);
  const excludeTokens = [...avoid, ...allergies]
      .map((t) => String(t || "").trim().toLowerCase())
      .filter((t) => t.length > 0);
  const originalTokens = tokenize(originalName);

  const candidates = [
    ...loadCatalog().foods,
    ...(customFoods || []).map(customToFood),
  ];

  const scored = [];
  for (const food of candidates) {
    const shares = macroShares({
      proteinG: food.proteinPer100g,
      carbsG: food.carbsPer100g,
      fatG: food.fatPer100g,
    });
    if (!shares) continue;
    const candidateRole = classifyMacroRole({
      proteinG: food.proteinPer100g,
      carbsG: food.carbsPer100g,
      fatG: food.fatPer100g,
    });
    if (role !== "mixed" && candidateRole !== role) continue;
    // Don't suggest back the exact food being replaced.
    const foodTokens = tokenize(food.name);
    if (foodTokens.size === originalTokens.size &&
        [...foodTokens].every((t) => originalTokens.has(t))) {
      continue;
    }
    if (nameMatchesAny(food.name, excludeTokens)) continue;

    scored.push({
      food,
      distance: shareDistance(originalShares, shares),
      candidateRole,
    });
  }

  scored.sort((a, b) => a.distance - b.distance || (a.food.id < b.food.id ? -1 : 1));

  const alternatives = scored.slice(0, MAX_ALTERNATIVES).map(({food, candidateRole}) => ({
    foodId: food.id,
    name: food.name,
    per100g: {
      kcal: Math.round(food.kcalPer100g),
      proteinG: food.proteinPer100g,
      carbsG: food.carbsPer100g,
      fatG: food.fatPer100g,
    },
    macroRole: candidateRole,
    similarityNote: similarityNoteFor(role),
  }));

  return {role, alternatives};
}

module.exports = {
  classifyMacroRole,
  macroShares,
  shareDistance,
  rankAlternatives,
  DOMINANCE_MARGIN,
  MAX_ALTERNATIVES,
};
