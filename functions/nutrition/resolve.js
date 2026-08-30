/**
 * Composite food resolution for the AI gateway — the server mirror of
 * `lib/features/diet/domain/nutrition/composite_food_resolver.dart`.
 *
 * The bundled catalog (`./food_db.js`) is USDA, so it covers regional and home
 * cooking badly. Rather than let that gap be filled by a model guess, the app
 * lets the user define a food once (`customFoods`) and layers it OVER the
 * reference data. The coach must resolve food the same way, or it will quote a
 * different number than the screen for the user's own "Koshari" — the exact
 * drift this whole epic exists to prevent.
 *
 * This module is the ONE place server-side that turns a food reference (a query
 * or an id) plus an amount into calories. `resolve_food`,
 * `calculate_meal_nutrition` and `log_food`'s verify hook all go through it, so
 * they cannot disagree with each other, and — via the shared golden vectors —
 * cannot disagree with the Dart side either.
 */

const {resolveFood, foodById, nutritionFor} = require("./food_db");

/**
 * Lowercased word tokens, punctuation stripped — the exact `_matchCustom`
 * tokenizer from the Dart composite resolver (tokens of length > 1).
 * @param {string} text
 * @return {!Array<string>}
 */
function tokensOf(text) {
  return String(text)
      .toLowerCase()
      .split(/[^a-z0-9]+/)
      .filter((t) => t.length > 1);
}

/**
 * A stored custom-food row (from `store.listCustomFoods`) projected into the
 * same food shape `food_db.js` produces, so `nutritionFor` can price it with
 * no special-casing. `source`/`sourceRef` mark it as the user's own.
 * @param {!Object} cf
 * @return {!Object}
 */
function customToFood(cf) {
  return {
    id: `custom:${cf.id}`,
    name: cf.name,
    category: null,
    preparation: cf.preparation || "unknown",
    kcalPer100g: Number(cf.kcalPer100g) || 0,
    proteinPer100g: Number(cf.proteinPer100g) || 0,
    carbsPer100g: Number(cf.carbsPer100g) || 0,
    fatPer100g: Number(cf.fatPer100g) || 0,
    source: "userCustom",
    sourceRef: String(cf.id),
    portions: (Array.isArray(cf.portions) ? cf.portions : [])
        .filter((p) => p && typeof p.label === "string" &&
          typeof p.grams === "number")
        .map((p) => ({label: p.label, grams: p.grams})),
  };
}

/**
 * The user's own foods whose name contains every word of `query` — the same
 * all-words rule the bundled catalog uses (so the two behave alike), newest
 * first (a food defined a moment ago is the one being used now), optionally
 * filtered to a preparation.
 * @param {!Array<Object>} customFoods
 * @param {string} query
 * @param {?string} preparation
 * @return {!Array<Object>} Food-shaped objects.
 */
function matchCustom(customFoods, query, preparation) {
  const tokens = tokensOf(query);
  if (tokens.length === 0) return [];
  const matches = [];
  for (const cf of customFoods) {
    const name = String(cf.name || "").toLowerCase();
    if (!tokens.every((t) => name.includes(t))) continue;
    if (preparation && (cf.preparation || "unknown") !== preparation) continue;
    matches.push(cf);
  }
  // Newest first (createdAt may be a Date, ms number, or absent).
  const ms = (cf) => {
    const c = cf.createdAt;
    if (c instanceof Date) return c.getTime();
    return typeof c === "number" ? c : 0;
  };
  matches.sort((a, b) => ms(b) - ms(a));
  return matches.map(customToFood);
}

/**
 * Resolves a food reference to `{kind:'resolved'|'ambiguous'|'notFound'}`,
 * consulting the user's custom foods before the USDA catalog. A food the user
 * defined themselves wins outright — they told us what it is, and there is
 * nothing for the reference catalog to be more right about.
 *
 * An explicit `foodId` (a `custom:<id>` or `usda:<fdcId>` handle from a prior
 * `resolve_food` result) short-circuits the search: it is a decision already
 * made, not a query to re-interpret. A deleted custom id resolves to notFound,
 * never a USDA lookalike — substituting would silently rewrite what the user
 * meant.
 *
 * @param {!Object} ref `{query?, foodId?, preparation?}`.
 * @param {!Array<Object>} customFoods The user's own foods.
 * @return {!Object} A FoodMatch-shaped result.
 */
function resolveComposite(ref, customFoods) {
  const preparation = ref.preparation || null;
  if (ref.foodId) {
    const id = String(ref.foodId);
    if (id.startsWith("custom:")) {
      const wanted = id.slice("custom:".length);
      const cf = customFoods.find((c) => String(c.id) === wanted);
      return cf ?
        {kind: "resolved", food: customToFood(cf), alternatives: []} :
        {kind: "notFound", query: id};
    }
    const food = foodById(id);
    return food ?
      {kind: "resolved", food, alternatives: []} :
      {kind: "notFound", query: id};
  }

  const query = String(ref.query || "");
  const mine = matchCustom(customFoods, query, preparation);
  if (mine.length > 0) {
    return {kind: "resolved", food: mine[0], alternatives: mine.slice(1)};
  }
  return resolveFood(query, {preparation});
}

/**
 * Resolves a meal item and prices it, in one step. Returns a discriminated
 * outcome so no caller can consume the result without deciding what to do when
 * the food is uncertain, absent, or the amount can't be converted:
 *
 * - `{outcome:'computed', ...nutrition}` — a `nutritionFor` result plus the
 *   food's name/preparation.
 * - `{outcome:'ambiguous', candidates}` — close matches whose energy differs
 *   materially (the raw-vs-cooked fork). The caller must pick a foodId.
 * - `{outcome:'notFound'}` — nothing matched.
 * - `{outcome:'unresolvedMeasure', availableMeasures, reason}` — the food is
 *   known but the unit can't be converted for it (a volume with no recorded
 *   density, an unknown measure).
 *
 * @param {!Object} item `{query?, foodId?, preparation?, quantity, unit}`.
 * @param {!Array<Object>} customFoods
 * @return {!Object}
 */
function resolveAndCompute(item, customFoods) {
  const match = resolveComposite(item, customFoods);
  if (match.kind === "notFound") {
    return {outcome: "notFound", query: match.query};
  }
  if (match.kind === "ambiguous") {
    return {
      outcome: "ambiguous",
      query: match.query,
      candidates: match.candidates.map(summariseFood),
    };
  }
  const nutrition = nutritionFor(match.food, item.quantity, item.unit);
  if (nutrition.unresolved) {
    return {
      outcome: "unresolvedMeasure",
      reason: nutrition.unresolved,
      unit: nutrition.unit,
      food: summariseFood(match.food),
      availableMeasures: nutrition.availableMeasures || [],
    };
  }
  return {
    outcome: "computed",
    preparation: match.food.preparation,
    alternatives: (match.alternatives || []).map(summariseFood),
    ...nutrition,
  };
}

const VALID_PREPARATIONS = ["raw", "cooked", "dry"];

/**
 * Normalizes one raw meal item from a tool call into `{foodId?, query?,
 * preparation?, quantity, unit}`, or throws with a human message. Shared by the
 * read tools and `log_food` so a food identified by `calculate_meal_nutrition`
 * is validated the same way it is logged.
 *
 * A reference is required (a `foodId` from a prior `resolve_food`, or a free
 * `query`); a positive `quantity`; and a non-empty `unit`. `preparation` is
 * kept only when it is one of the states the catalog actually distinguishes.
 * @param {!Object} raw
 * @return {!Object}
 */
function normalizeItem(raw) {
  const item = raw && typeof raw === "object" ? raw : {};
  const foodId = item.foodId != null && String(item.foodId).trim() !== "" ?
    String(item.foodId).trim() : null;
  const query = item.query != null && String(item.query).trim() !== "" ?
    String(item.query).trim() : null;
  if (!foodId && !query) {
    throw new Error(
        "Each item needs a foodId (from resolve_food) or a query naming the " +
        "food.");
  }
  const quantity = Number(item.quantity);
  if (!Number.isFinite(quantity) || quantity <= 0) {
    throw new Error(
        `A positive quantity is required for ${query || foodId}.`);
  }
  const unit = item.unit != null ? String(item.unit).trim() : "";
  if (!unit) {
    throw new Error(`A unit (e.g. g, oz, piece) is required for ` +
        `${query || foodId}.`);
  }
  const prep = item.preparation != null ?
    String(item.preparation).trim().toLowerCase() : null;
  const out = {quantity, unit};
  if (foodId) out.foodId = foodId;
  if (query) out.query = query;
  if (prep && VALID_PREPARATIONS.includes(prep)) out.preparation = prep;
  return out;
}

/**
 * The compact projection of a food used in tool payloads and error guidance.
 * @param {!Object} food
 * @return {!Object}
 */
function summariseFood(food) {
  return {
    foodId: food.id,
    name: food.name,
    preparation: food.preparation,
    per100gKcal: Math.round(food.kcalPer100g),
  };
}

module.exports = {
  resolveComposite,
  resolveAndCompute,
  normalizeItem,
  matchCustom,
  customToFood,
  summariseFood,
  tokensOf,
};
