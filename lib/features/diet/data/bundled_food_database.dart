import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../domain/nutrition/food_reference.dart';
import '../domain/nutrition/food_resolver.dart';
import '../domain/nutrition/resolved_food.dart';

/// The nutrition catalog that ships inside the app: a USDA FoodData Central
/// subset, built by `scripts/nutrition/build_food_db.js` into
/// `assets/nutrition/foods.json`.
///
/// **Why bundled rather than an API.** The figures have to be available
/// offline, identical for every user, identical between the app and the
/// server, and stable enough that a test can assert them. A network lookup is
/// none of those things. The trade is coverage: USDA describes US foods well
/// and regional cooking poorly, so [FoodNotFound] is a common, expected
/// outcome — and answering it honestly ("I don't have that food") is the
/// entire point. See `docs/DIET_COACH_AUDIT.md` (T2).
///
/// The asset is ~1 MB, parsed once on first use and kept for the process
/// lifetime. Loading is lazy: an app session that never opens a food search
/// never pays for it.
class BundledFoodDatabase implements FoodResolver {
  BundledFoodDatabase({Future<String> Function()? loadAsset})
    : _loadAsset = loadAsset ?? _defaultLoader;

  static const String assetPath = 'assets/nutrition/foods.json';

  static Future<String> _defaultLoader() => rootBundle.loadString(assetPath);

  final Future<String> Function() _loadAsset;

  Future<_Catalog>? _catalog;

  /// Parses the asset at most once, even under concurrent callers — the
  /// future itself is memoized, not just its result.
  Future<_Catalog> _load() => _catalog ??= _parse();

  Future<_Catalog> _parse() async {
    final raw = await _loadAsset();
    final decoded = json.decode(raw) as Map<String, dynamic>;
    // Positional rows, described by the asset's own `fields` list — see the
    // build script's note on why the asset isn't a list of objects.
    final rows = (decoded['foods'] as List<dynamic>? ?? const []);
    final foods = <FoodReference>[];
    for (final row in rows) {
      final food = _foodFromRow(row);
      if (food != null) foods.add(food);
    }
    return _Catalog(foods);
  }

  FoodReference? _foodFromRow(dynamic row) {
    if (row is! List || row.length < 9) return null;
    final fdcId = row[0];
    final name = row[1];
    if (fdcId is! num || name is! String || name.isEmpty) return null;
    double num0(dynamic v) => v is num ? v.toDouble() : 0;
    return FoodReference(
      id: 'usda:${fdcId.toInt()}',
      name: name,
      category: row[2] is String ? row[2] as String : null,
      preparation: foodPreparationFromName(row[3] as String?),
      kcalPer100g: num0(row[4]),
      proteinPer100g: num0(row[5]),
      carbsPer100g: num0(row[6]),
      fatPer100g: num0(row[7]),
      source: NutritionSource.usdaFdc,
      sourceRef: fdcId.toInt().toString(),
      portions: [
        for (final portion in (row[8] as List<dynamic>? ?? const []))
          if (portion is List &&
              portion.length >= 2 &&
              portion[0] is String &&
              portion[1] is num)
            FoodPortion(
              label: portion[0] as String,
              grams: (portion[1] as num).toDouble(),
            ),
      ],
    );
  }

  @override
  Future<FoodReference?> byId(String id) async {
    final catalog = await _load();
    return catalog.byId[id];
  }

  @override
  Future<List<FoodReference>> search(String query, {int limit = 20}) async {
    final catalog = await _load();
    return catalog
        .rank(query, preparation: null)
        .take(limit)
        .map((scored) => scored.food)
        .toList();
  }

  @override
  Future<FoodMatch> resolve(
    String query, {
    FoodPreparation? preparation,
  }) async {
    final catalog = await _load();
    final ranked = catalog.rank(query, preparation: preparation);
    if (ranked.isEmpty) return FoodNotFound(query: query);

    final best = ranked.first;
    // Everything scoring near the best is a genuine contender. A wider net
    // here means more questions asked and fewer wrong answers given.
    final contenders = ranked
        .where((s) => s.score >= best.score - _kCloseScore)
        .take(_kMaxCandidates)
        .toList();

    if (contenders.length > 1 && _disagreeMaterially(contenders)) {
      return FoodAmbiguous(
        query: query,
        candidates: contenders.map((s) => s.food).toList(),
      );
    }

    return FoodResolved(
      food: best.food,
      alternatives: ranked
          .skip(1)
          .take(_kMaxCandidates - 1)
          .map((s) => s.food)
          .toList(),
    );
  }

  /// Whether the close matches differ enough in energy that picking one for
  /// the user would be a guess with real consequences.
  ///
  /// This is the raw-versus-cooked test in disguise: raw rice is 365 kcal/100g
  /// and cooked rice is 130, so "100g rice" with no state is a ~3× fork and
  /// has to become a question. Where the contenders all agree on the numbers
  /// (three near-identical chicken records), which one is chosen doesn't
  /// matter and asking would be noise.
  bool _disagreeMaterially(List<_Scored> contenders) {
    var min = contenders.first.food.kcalPer100g;
    var max = min;
    for (final scored in contenders) {
      final kcal = scored.food.kcalPer100g;
      if (kcal < min) min = kcal;
      if (kcal > max) max = kcal;
    }
    if (max <= 0) return false;
    return (max - min) / max > _kMaterialEnergyGap;
  }
}

/// Score window treated as "as good as the best match".
const double _kCloseScore = 12;

/// How many candidates a question may offer before it stops being a question.
const int _kMaxCandidates = 5;

/// Relative energy spread across close matches that makes the choice matter.
const double _kMaterialEnergyGap = 0.25;

/// A food and how well it matched.
class _Scored {
  const _Scored(this.food, this.score);
  final FoodReference food;
  final double score;
}

/// The parsed catalog plus its search index.
class _Catalog {
  _Catalog(this.foods)
    : byId = {for (final food in foods) food.id: food},
      _tokens = [for (final food in foods) _tokenize(food.name)],
      _leadTokens = [
        for (final food in foods) _tokenize(_leadSegment(food.name)),
      ];

  final List<FoodReference> foods;
  final Map<String, FoodReference> byId;

  /// Tokens of the whole description, and of just the part before the first
  /// comma. USDA descriptions are comma-inverted — "Rice, white, long-grain,
  /// regular, raw" — so the leading segment is the food itself and everything
  /// after it is qualification.
  final List<Set<String>> _tokens;
  final List<Set<String>> _leadTokens;

  /// Best-first matches for [query], optionally restricted to a preparation.
  ///
  /// Deterministic: ties break on the food's id, so the same query always
  /// returns the same order.
  List<_Scored> rank(String query, {FoodPreparation? preparation}) {
    final queryTokens = _tokenize(query);
    if (queryTokens.isEmpty) return const [];

    final results = <_Scored>[];
    for (var i = 0; i < foods.length; i++) {
      final food = foods[i];
      if (preparation != null && food.preparation != preparation) continue;

      final nameTokens = _tokens[i];
      var matched = 0;
      for (final token in queryTokens) {
        if (nameTokens.contains(token)) matched++;
      }
      // Every word the user typed has to appear. Partial matches are how a
      // search for "chicken breast" ends up returning chicken soup.
      if (matched < queryTokens.length) continue;

      var score = 60.0;
      // The food itself, not a qualification of it.
      final lead = _leadTokens[i];
      var inLead = 0;
      for (final token in queryTokens) {
        if (lead.contains(token)) inLead++;
      }
      score += 30 * (inLead / queryTokens.length);
      // Prefer the plainest record that still matches: USDA's descriptions
      // get longer as they get more specific, so extra words are extra
      // assumptions about what the user meant.
      final extras = nameTokens.length - queryTokens.length;
      score -= extras * 1.6;

      results.add(_Scored(food, score));
    }

    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.food.id.compareTo(b.food.id);
    });
    return results;
  }
}

/// The part of a USDA description before the first comma — the food itself.
String _leadSegment(String name) {
  final comma = name.indexOf(',');
  return comma == -1 ? name : name.substring(0, comma);
}

/// Lowercased word tokens, punctuation stripped. Deliberately simple and
/// deterministic — no stemming, no fuzzy matching, nothing that could make
/// "chicken" quietly match "chickpea".
Set<String> _tokenize(String text) {
  final tokens = <String>{};
  for (final raw in text.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
    if (raw.length > 1) tokens.add(raw);
  }
  return tokens;
}
