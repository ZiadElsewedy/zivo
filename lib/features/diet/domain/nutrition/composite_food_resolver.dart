import 'custom_food.dart';
import 'food_reference.dart';
import 'food_resolver.dart';
import 'resolved_food.dart';

/// Layers the user's own foods over the bundled catalog.
///
/// The bundled catalog is USDA, so it covers regional and home cooking badly.
/// Rather than let that gap be filled by a guess, the app lets the user define
/// a food once ([CustomFood]) and this puts it in front of the reference data
/// from then on — their "Koshari" beats anything USDA might loosely match, and
/// their figures are labelled as theirs wherever they surface.
class CompositeFoodResolver implements FoodResolver {
  CompositeFoodResolver({required this.catalog, required this.customFoods});

  /// The bundled reference catalog.
  final FoodResolver catalog;

  /// The user's own foods, read fresh on each lookup so a food defined a
  /// moment ago is immediately findable.
  final Future<List<CustomFood>> Function() customFoods;

  @override
  Future<FoodReference?> byId(String id) async {
    if (id.startsWith('custom:')) {
      final wanted = id.substring('custom:'.length);
      for (final food in await customFoods()) {
        if (food.id == wanted) return food.toReference();
      }
      // A custom food the user deleted. Null, never a lookalike from USDA —
      // substituting here would silently rewrite what a past entry meant.
      return null;
    }
    return catalog.byId(id);
  }

  @override
  Future<List<FoodReference>> search(String query, {int limit = 20}) async {
    final mine = _matchCustom(await customFoods(), query);
    if (mine.isEmpty) return catalog.search(query, limit: limit);
    final rest = await catalog.search(query, limit: limit);
    return [...mine, ...rest].take(limit).toList();
  }

  @override
  Future<FoodMatch> resolve(
    String query, {
    FoodPreparation? preparation,
  }) async {
    final mine = _matchCustom(await customFoods(), query)
        .where((f) => preparation == null || f.preparation == preparation)
        .toList();

    // A food the user defined themselves wins outright. They told us what it
    // is; there is nothing for the reference catalog to be more right about.
    if (mine.isNotEmpty) {
      return FoodResolved(food: mine.first, alternatives: mine.skip(1).toList());
    }
    return catalog.resolve(query, preparation: preparation);
  }

  /// Custom foods whose name contains every word of the query — the same
  /// all-words rule the bundled catalog uses, so the two behave alike.
  List<FoodReference> _matchCustom(List<CustomFood> foods, String query) {
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length > 1)
        .toSet();
    if (tokens.isEmpty) return const [];

    final matches = <CustomFood>[];
    for (final food in foods) {
      final name = food.name.toLowerCase();
      if (tokens.every(name.contains)) matches.add(food);
    }
    // Newest first: a food defined recently is the one being used now.
    matches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches.map((f) => f.toReference()).toList();
  }
}
