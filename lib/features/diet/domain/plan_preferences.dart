/// What ZIVO needs to know about a person's eating before it can build them a
/// plan they will actually follow.
///
/// Every field here is something **only the user can supply** — none of it is
/// derivable from their body data, their training or their log. That is the
/// bar for asking: a plan generator that asks for what it could work out
/// itself is a form.
///
/// Nothing here is a nutrition input. Calories and macros come from the target
/// ([NutritionTargets]) and from the food catalog; these are the constraints
/// the plan has to live inside.
class PlanPreferences {
  const PlanPreferences({
    required this.mealsPerDay,
    this.likes = const [],
    this.avoid = const [],
    this.allergies = const [],
    this.cuisine,
    this.notes,
  });

  /// How many times a day they want to eat. The single strongest determinant
  /// of whether a plan survives contact with a working week.
  final int mealsPerDay;

  /// Foods they want to see. Not a whitelist — a steer.
  final List<String> likes;

  /// Foods they won't eat. A preference: ZIVO is asked not to use these.
  final List<String> avoid;

  /// Foods they **cannot** eat. Categorically different from [avoid]: this is
  /// a safety limit, checked deterministically on the server after generation
  /// rather than left to the model's compliance with a prompt.
  final List<String> allergies;

  /// The kitchen the plan should come from — "Egyptian", "Mediterranean".
  /// Load-bearing in practice: a generator with no cuisine steer produces
  /// chicken-and-broccoli American gym food for everyone.
  final String? cuisine;

  /// Anything else, in their words. Free text, passed through as data.
  final String? notes;

  bool get isUsable =>
      mealsPerDay >= kMinMealsPerDay && mealsPerDay <= kMaxMealsPerDay;

  PlanPreferences copyWith({
    int? mealsPerDay,
    List<String>? likes,
    List<String>? avoid,
    List<String>? allergies,
    String? cuisine,
    String? notes,
  }) => PlanPreferences(
    mealsPerDay: mealsPerDay ?? this.mealsPerDay,
    likes: likes ?? this.likes,
    avoid: avoid ?? this.avoid,
    allergies: allergies ?? this.allergies,
    cuisine: cuisine ?? this.cuisine,
    notes: notes ?? this.notes,
  );

  /// The payload the `aiGenerateDietPlan` callable reads. Empty lists are sent
  /// as empty, not omitted — "I have no allergies" and "I wasn't asked" are
  /// the same to the server, and both mean the check finds nothing.
  Map<String, Object?> toPayload() => {
    'mealsPerDay': mealsPerDay,
    'likes': likes,
    'avoid': avoid,
    'allergies': allergies,
    if (cuisine != null && cuisine!.trim().isNotEmpty) 'cuisine': cuisine,
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes,
  };
}

/// Fewer than two "meals" a day isn't a plan this app can track against, and
/// more than eight stops being a meal structure and becomes grazing.
const int kMinMealsPerDay = 2;
const int kMaxMealsPerDay = 8;

/// Splits a comma-separated list the user typed into clean entries, dropping
/// blanks and duplicates while keeping the order they wrote them in.
List<String> parseFoodList(String text) {
  final seen = <String>{};
  final out = <String>[];
  for (final part in text.split(RegExp(r'[,\n]'))) {
    final value = part.trim();
    if (value.isEmpty) continue;
    final key = value.toLowerCase();
    if (!seen.add(key)) continue;
    out.add(value);
  }
  return out;
}
