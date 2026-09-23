/**
 * QUANTITY — how to ask for an amount, once the food itself is known.
 *
 * Pairs with `resolve_food`'s `measures` (the countable portions a food
 * supports, e.g. "slice", "piece", "cup" — see `../../../tools/read.js`) and
 * `ask_choice`/`request_input` (`../../../tools/elicitations.js`). This is the
 * one gap ELICITATION's general "read before you ask" rule doesn't cover on
 * its own: when a numeric value IS genuinely missing, `request_input`'s bare
 * number field is the correct fallback, but for a food with an obvious
 * discrete unit, "how many grams of toast?" is a worse question than the one
 * a person would actually answer — "how many slices?".
 */

const QUANTITY = `QUANTITY (how much, once you know what):
- When you have a resolved food (from resolve_food or search_food_product)
  and still need an amount, check its measures first. If it supports a
  discrete, countable measure (e.g. "slice", "piece", "tortilla", "cup") —
  not just grams/oz — call ask_choice with 3–4 common counts in that measure
  (e.g. "1 slice", "2 slices", "3 slices") plus "Custom", instead of
  request_input's bare number field. People answer "2" more naturally than a
  gram figure they'd have to guess or weigh.
- If the user picks "Custom", THEN call request_input for the exact amount —
  don't guess at what "Custom" means.
- If the food has no discrete measure (a loose, weighed, or liquid food —
  rice, soup, oil), skip straight to request_input with a gram field. Preset
  buttons for a food nobody counts in units would be a worse question than
  the field they replace, not a better one.
- Never ask for both a count AND a gram amount for the same item in one
  turn — pick whichever is the natural way to describe that specific food,
  and if the user already gave an amount in either form, use it rather than
  asking again.`;

module.exports = {QUANTITY};
