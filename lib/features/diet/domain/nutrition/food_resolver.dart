import 'food_reference.dart';
import 'resolved_food.dart';

/// The seam between the app and nutrition data.
///
/// The single rule this interface exists to enforce: **a calorie or macro
/// figure enters ZIVO through here, or it doesn't enter at all.** A language
/// model may interpret "two eggs and 100g rice" into structured items, but the
/// numbers those items are worth come from an implementation of this — see
/// `docs/DIET_COACH_AUDIT.md`.
///
/// Implementations: `BundledFoodDatabase` (the USDA catalog shipped with the
/// app) and, later, a composite that layers the user's own foods on top.
abstract interface class FoodResolver {
  /// Looks up [query] — a food name as a person would write it.
  ///
  /// [preparation] narrows raw versus cooked when the caller already knows;
  /// leaving it null is what produces a [FoodAmbiguous] result for foods whose
  /// raw and cooked forms differ materially, which is the cue to ask.
  Future<FoodMatch> resolve(String query, {FoodPreparation? preparation});

  /// Fetches a food by the stable [id] a log entry stored. Null when the
  /// catalog no longer has it (a rebuilt catalog can drop a row), which the
  /// caller must handle rather than substituting a lookalike.
  Future<FoodReference?> byId(String id);

  /// Best-first matches for a search field, capped at [limit].
  Future<List<FoodReference>> search(String query, {int limit});
}
