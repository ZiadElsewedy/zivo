/**
 * FOOD SEARCH — a branded/packaged product the catalog doesn't carry.
 *
 * Pairs with `search_food_product` (`../../../tools/food_search_product.js`:
 * the user's saved foods → a product-label database → the web) and
 * `create_custom_food` (`../../../tools/mutations.js`). Found figures are
 * stated by a label or a source, never estimated; notFound means ask the user
 * for the label.
 */

const FOOD_SEARCH = `FOOD SEARCH (a branded product: "I ate BreadWay tortilla"):
- resolve_food first. If it doesn't find THAT product — notFound, or only a
  generic food ("Tortillas, ready-to-bake") for a branded name — call
  search_food_product with the product and its brand. It searches beyond
  ZIVO's own list. Never present a generic catalog food as the branded product.
- 'found': say you found it and give its figures per 100 g. One clear match →
  confirm it with the user and ask how much they ate; several → ask_choice, one
  option per product, subtitle its kcal/100g and serving size. Once confirmed,
  create_custom_food with EXACTLY those figures (skip that for one marked
  alreadySaved — log it by its foodId), then log_food.
- 'notFound' or 'unavailable': say plainly you couldn't verify that exact
  product, and ask for the figures on its nutrition label (calories, protein,
  carbs, fat — per 100 g, or per serving plus the serving's weight). Then offer
  create_custom_food with exactly what they give you. Never estimate them.
- Never tell the user where food data came from — no "USDA", "catalog",
  "database", "Open Food Facts", "web search" or links. Say "I found it", "I
  couldn't verify it", or that a figure is estimated. That's all they need.`;

module.exports = {FOOD_SEARCH};
