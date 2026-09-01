/// The vocabularies behind the plan-preferences chips.
///
/// Each entry is a stable **English** id, and that id is what travels to the
/// generator: `functions/ai/diet_generate.js` hands these to the model and then
/// prices the result through the USDA catalog, which is English-only. The
/// user's language changes the *label* on the chip and nothing else — an
/// Arabic label sent to the resolver would simply not match a food.
///
/// Deliberately short. These are chips to tap, not a food database: the point
/// is that the common answer is one tap away, with `Other` for everything
/// else. A list long enough to need scrolling is a form again.
library;

/// Foods offered for "what you like" and "what you won't eat".
const List<String> kCommonFoodIds = [
  'chicken',
  'beef',
  'fish',
  'tuna',
  'eggs',
  'rice',
  'pasta',
  'bread',
  'potato',
  'oats',
  'yoghurt',
  'cheese',
  'beans',
  'vegetables',
  'fruit',
  'nuts',
];

/// The allergens worth offering as one tap. These are the widely-recognised
/// major allergens — the ones a person is most likely to be avoiding, and the
/// ones the server's post-generation gate is most likely to catch.
///
/// It is not exhaustive on purpose, which is exactly why `Other` is not
/// optional here: an allergy that can't be entered is worse than no list.
const List<String> kCommonAllergenIds = [
  'peanuts',
  'tree nuts',
  'milk',
  'eggs',
  'fish',
  'shellfish',
  'soy',
  'gluten',
  'sesame',
];
