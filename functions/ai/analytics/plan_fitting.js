/**
 * The deterministic half of plan generation: fitting a proposed day to a
 * calorie target, and refusing anything that contains a food the user said
 * they cannot eat.
 *
 * **Neither of these is left to the model.** A model asked to hit 2,400 kcal
 * writes "2,400 kcal" at the bottom of a plan that adds up to 2,830 — the
 * arithmetic is not what it is good at, and the failure is invisible. And an
 * allergy is a safety constraint, not a preference: "please avoid peanuts" in
 * a prompt is a request, while the check here is a gate. The model picks the
 * foods; this module does the sums and holds the line.
 *
 * Pure and dependency-free (a `price` function is injected), so it runs under
 * plain `node --test` and can be reasoned about without a catalog or a network.
 */

/**
 * Units whose amount can be scaled to any value and still describe a real
 * portion. "175 g of rice" is a portion; "1.4 eggs" is not, so count-like
 * units are left exactly as proposed and the fitting works around them.
 */
const SCALABLE_UNITS = ["g", "gram", "grams", "ml", "millilitre", "milliliter"];

/** The widest adjustment allowed before a fit is abandoned as dishonest. */
const MIN_SCALE = 0.5;
const MAX_SCALE = 2.0;

/**
 * Inside this band the day is already close enough and portions are left
 * alone. Scaling 400 g of rice to 408 g to chase a 2% gap invents a precision
 * nobody eats to, and makes the plan read as machine output rather than food.
 */
const SCALE_DEADBAND = 0.05;

/** Gram/millilitre amounts are rounded to this, so portions stay weighable. */
const GRAM_ROUNDING = 5;

/**
 * @param {string} unit
 * @return {boolean} Whether an amount in this unit can be scaled freely.
 */
function isScalable(unit) {
  return SCALABLE_UNITS.includes(String(unit || "").trim().toLowerCase());
}

/**
 * @param {number} quantity
 * @param {string} unit
 * @return {number} The scaled amount, rounded to something a person can
 *   actually measure.
 */
function roundQuantity(quantity, unit) {
  if (isScalable(unit)) {
    return Math.max(
        GRAM_ROUNDING, Math.round(quantity / GRAM_ROUNDING) * GRAM_ROUNDING);
  }
  return Math.round(quantity * 10) / 10;
}

/**
 * Fits one day's items to [targetKcal] by scaling only the amounts that can
 * honestly be scaled.
 *
 * The fixed (count-based) items' energy is subtracted first and the remainder
 * is what the scalable items have to cover, so a single pass lands on the
 * target rather than converging toward it — no loop, no drift, and the same
 * inputs always give the same plan.
 *
 * @param {!Array<!Object>} items Priced items: `{quantity, unit, calories}` —
 *   the same field name the plan model uses everywhere else in the app.
 * @param {number} targetKcal
 * @param {function(!Object, number): !Object} price Re-prices an item at a new
 *   quantity, returning the item with fresh nutrition. Injected because
 *   pricing needs the catalog and this module must not.
 * @return {{items: !Array<!Object>, factor: number, fitted: boolean,
 *   reason: ?string}}
 */
function fitDayToTarget(items, targetKcal, price) {
  const total = items.reduce((sum, i) => sum + (Number(i.calories) || 0), 0);
  if (!Number.isFinite(targetKcal) || targetKcal <= 0 || total <= 0) {
    return {items, factor: 1, fitted: false, reason: "no-target"};
  }

  const scalable = items.filter((i) => isScalable(i.unit));
  const fixedKcal = items
      .filter((i) => !isScalable(i.unit))
      .reduce((sum, i) => sum + (Number(i.calories) || 0), 0);
  const scalableKcal = scalable.reduce(
      (sum, i) => sum + (Number(i.calories) || 0), 0);

  if (scalable.length === 0 || scalableKcal <= 0) {
    // Everything is countable — eggs and slices of bread. Nothing here can be
    // adjusted without inventing a fractional portion, so the day stands as
    // proposed and says so.
    return {items, factor: 1, fitted: false, reason: "nothing-scalable"};
  }

  const needed = targetKcal - fixedKcal;
  if (needed <= 0) {
    return {items, factor: 1, fitted: false, reason: "fixed-items-exceed"};
  }

  const raw = needed / scalableKcal;
  if (Math.abs(raw - 1) <= SCALE_DEADBAND) {
    return {items, factor: 1, fitted: true, reason: null};
  }
  if (raw < MIN_SCALE || raw > MAX_SCALE) {
    // The proposal is not the right shape for this target — halving or
    // doubling every portion would produce a plan nobody would eat. Better to
    // hand back what was proposed, honestly off-target, than a distortion.
    return {items, factor: 1, fitted: false, reason: "out-of-range"};
  }

  const scaled = items.map((item) => {
    if (!isScalable(item.unit)) return item;
    const quantity = roundQuantity(Number(item.quantity) * raw, item.unit);
    if (quantity === Number(item.quantity)) return item;
    return price(item, quantity);
  });
  return {items: scaled, factor: raw, fitted: true, reason: null};
}

/**
 * Lowercased word tokens — the same shape `functions/nutrition/resolve.js`
 * uses, so "peanuts" matches "peanut butter" the way a person would expect.
 * @param {string} text
 * @return {!Array<string>}
 */
function wordsOf(text) {
  return String(text || "")
      .toLowerCase()
      .split(/[^a-z0-9]+/)
      .filter((t) => t.length > 1);
}

/**
 * The first item whose name contains a word from [allergies], or null.
 *
 * Deliberately blunt: it matches on whole words in either direction, so
 * "peanut" catches "peanut butter" and "peanuts" catches "peanut oil". A false
 * positive costs one regeneration; a false negative costs someone a reaction.
 * This is why the check is a stem comparison rather than an exact match.
 *
 * @param {!Array<!Object>} items `{name}`-shaped.
 * @param {!Array<string>} allergies
 * @return {?{item: !Object, allergen: string}}
 */
function findAllergen(items, allergies) {
  const allergens = (allergies || [])
      .flatMap(wordsOf)
      .map(stem)
      .filter((a) => a.length > 2);
  if (allergens.length === 0) return null;
  for (const item of items) {
    const words = wordsOf(item && item.name).map(stem);
    for (const allergen of allergens) {
      if (words.some((w) => w === allergen ||
          w.startsWith(allergen) || allergen.startsWith(w))) {
        return {item, allergen};
      }
    }
  }
  return null;
}

/**
 * Crude singularisation, enough to make "eggs"/"egg" and "nuts"/"nut" the same
 * word. Not a stemmer — it only has to survive a food name.
 * @param {string} word
 * @return {string}
 */
function stem(word) {
  const w = String(word);
  if (w.length > 3 && w.endsWith("es")) return w.slice(0, -2);
  if (w.length > 3 && w.endsWith("s")) return w.slice(0, -1);
  return w;
}

module.exports = {
  fitDayToTarget,
  findAllergen,
  isScalable,
  roundQuantity,
  wordsOf,
  stem,
  SCALABLE_UNITS,
  MIN_SCALE,
  MAX_SCALE,
  SCALE_DEADBAND,
  GRAM_ROUNDING,
};
