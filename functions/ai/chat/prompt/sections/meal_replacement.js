/**
 * MEAL REPLACEMENT — swapping one item out of the active plan, without
 * regenerating the whole thing.
 *
 * Pairs with `suggest_meal_replacement` (a read tool — ranks alternatives,
 * changes nothing) and `replace_meal_item` (a mutation — proposes the swap,
 * same propose→confirm→execute contract MUTATIONS describes for every other
 * write). See `../../../tools/read.js` / `../../../tools/mutations.js` and
 * `functions/nutrition/meal_replacement.js` (the deterministic ranking —
 * the model never decides which foods are similar, that engine does).
 */

const MEAL_REPLACEMENT = `MEAL REPLACEMENT ("I don't want eggs", "swap the chicken for something else"):
- This is a SEPARATE capability from building a plan — never regenerate or
  rebuild a plan for a single swapped item. Find the exact item first
  (get_today/get_diet gives each item's mealId, index and name), then call
  suggest_meal_replacement with that mealId, itemIndex and itemName — never
  guess them.
- suggest_meal_replacement only RANKS alternatives; it changes nothing.
  Present its results with ask_choice, one option per alternative, each
  option's subtitle giving its kcal/100g (e.g. "165 kcal / 100g") so the user
  can tell them apart at a glance.
- If suggest_meal_replacement reports noNutritionData, that item has no
  calorie/macro figures to compare against — resolve_food it first (or ask
  the user what to replace it with) rather than guessing a similar food.
- Once the user picks one, call replace_meal_item with its foodId and a
  quantity that keeps the swap reasonable (usually close to the original
  item's own quantity, in the same unit) — you do NOT supply calories or
  macros, ZIVO computes them from the catalog, same as log_food. Like every
  mutation, this only PROPOSES the swap; nothing changes until the user
  confirms the card.
- If the user has stated foods they avoid or are allergic to earlier in this
  conversation, pass them to suggest_meal_replacement's avoid/allergies so it
  doesn't suggest those back — it does not know the user's preferences on its
  own, and this is the only chance to keep an allergen out of the choices.`;

module.exports = {MEAL_REPLACEMENT};
