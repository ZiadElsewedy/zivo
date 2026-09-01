import 'food_reference.dart';

/// The result of asking the catalog about a food. A sealed set, because the
/// three outcomes need genuinely different handling and none of them may be
/// silently collapsed into "here's a number".
///
/// This is the type that makes requirement 8 ("make uncertainty explicit")
/// structural rather than aspirational: there is no way to consume a lookup
/// result without deciding what to do when the food is ambiguous or absent.
sealed class FoodMatch {
  const FoodMatch();
}

/// The query resolved to one food the catalog is confident about.
class FoodResolved extends FoodMatch {
  const FoodResolved({required this.food, required this.alternatives});

  final FoodReference food;

  /// Other plausible matches, best-first, for a "did you mean" affordance.
  /// Non-empty here means "we're confident, but you can change it" — unlike
  /// [FoodAmbiguous], which means "we are not confident enough to pick".
  final List<FoodReference> alternatives;
}

/// Several candidates matched and they disagree about the nutrition in a way
/// that matters — most often raw versus cooked, which can be a ~3× difference.
///
/// **This is a question, not a failure.** The right response is to ask the
/// user which one they mean, exactly as a coach would ("was the chicken
/// weighed raw or after cooking?"), never to pick the first and move on.
class FoodAmbiguous extends FoodMatch {
  const FoodAmbiguous({required this.query, required this.candidates});

  final String query;

  /// The plausible foods, best-first. Always at least two.
  final List<FoodReference> candidates;
}

/// Nothing in the catalog matched.
///
/// Also not a failure: it is the honest answer, and the cue to offer the
/// user a custom food rather than to invent a value. The bundled catalog is
/// USDA, so it covers US staples well and regional cooking poorly — this
/// outcome is expected, common, and must never be papered over.
class FoodNotFound extends FoodMatch {
  const FoodNotFound({required this.query});

  final String query;
}
