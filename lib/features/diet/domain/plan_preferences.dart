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
    this.eatingHabits,
    this.scheduleNotes,
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

  /// How the user usually eats, in their own words — "eggs and bread for
  /// breakfast, chicken and rice for lunch, something light at night". The
  /// richest steer the generator gets, because it describes the plan the user
  /// will actually keep rather than the one a form would produce. Free text
  /// (spoken or typed); passed through as data.
  final String? eatingHabits;

  /// Anything about their routine that should shape *when* meals fall — "I
  /// train at 6am and eat straight after". Free text; passed through as data.
  final String? scheduleNotes;

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
    String? eatingHabits,
    String? scheduleNotes,
    String? notes,
  }) => PlanPreferences(
    mealsPerDay: mealsPerDay ?? this.mealsPerDay,
    likes: likes ?? this.likes,
    avoid: avoid ?? this.avoid,
    allergies: allergies ?? this.allergies,
    cuisine: cuisine ?? this.cuisine,
    eatingHabits: eatingHabits ?? this.eatingHabits,
    scheduleNotes: scheduleNotes ?? this.scheduleNotes,
    notes: notes ?? this.notes,
  );

  /// The payload the `aiGenerateDietPlan` callable reads. Empty lists are sent
  /// as empty, not omitted — "I have no allergies" and "I wasn't asked" are
  /// the same to the server, and both mean the check finds nothing.
  ///
  /// [eatingHabits], [scheduleNotes] and [notes] are folded into the single
  /// `notes` field the generator already reads, each under its own English
  /// label so the model can tell "how they eat" from "when they eat". Folding
  /// them keeps the deployed backend contract unchanged — no new schema field
  /// to deploy before the wizard can size a plan — while still giving the
  /// generator every word the user gave.
  Map<String, Object?> toPayload() {
    final map = <String, Object?>{
      'mealsPerDay': mealsPerDay,
      'likes': likes,
      'avoid': avoid,
      'allergies': allergies,
      if (cuisine != null && cuisine!.trim().isNotEmpty) 'cuisine': cuisine,
    };
    final composedNotes = _composeNotes();
    if (composedNotes != null) map['notes'] = composedNotes;
    return map;
  }

  /// The user's free-text answers, labelled and joined, or null when they gave
  /// none. English labels only — the payload is data for an English-reasoning
  /// model, and the user's own words (in whatever language) sit inside.
  String? _composeNotes() {
    final parts = <String>[];
    final habits = eatingHabits?.trim();
    final schedule = scheduleNotes?.trim();
    final extra = notes?.trim();
    if (habits != null && habits.isNotEmpty) {
      parts.add('How they usually eat: $habits');
    }
    if (schedule != null && schedule.isNotEmpty) {
      parts.add('Their routine and timing: $schedule');
    }
    if (extra != null && extra.isNotEmpty) parts.add(extra);
    return parts.isEmpty ? null : parts.join('\n');
  }
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

/// Turns a natural-language sentence ("I don't like fish, broccoli, or cottage
/// cheese", "peanuts and shellfish") into clean food tokens.
///
/// Used for the wizard's spoken/typed dislikes and allergies, which arrive as
/// prose rather than a tidy comma list. It splits on commas, semicolons,
/// newlines and the conjunctions "and"/"or", then strips the leading filler
/// people actually say ("I don't like…", "no…", "allergic to…").
///
/// **Over-splitting is the safe direction here**, deliberately: the server's
/// allergen gate stem-matches each token against every food in the generated
/// plan, so more tokens catch more, and a stray token never lets an allergen
/// *through*. The cost is a rare split of a two-word food ("mac and cheese"),
/// which at worst makes the model avoid slightly more than asked.
List<String> splitNaturalFoodList(String text) {
  final seen = <String>{};
  final out = <String>[];
  final pieces = text.split(
    RegExp(r'[,\n;]|\band\b|\bor\b', caseSensitive: false),
  );
  for (final piece in pieces) {
    var value = piece.trim();
    // Drop the way people phrase a dislike/allergy before the food itself.
    value = value.replaceFirst(
      RegExp(
        r"^(i\s+)?(don'?t|do\s+not|can'?t|cannot)\s+(like|eat|want|have|stand)\s+",
        caseSensitive: false,
      ),
      '',
    );
    value = value.replaceFirst(
      RegExp(
        r'^(no|not|avoid|allergic\s+to|allergy\s+to|allergies?|my\s+allergies?\s+are)\s*:?\s+',
        caseSensitive: false,
      ),
      '',
    );
    value = value.replaceFirst(RegExp(r'[.\s]+$'), '').trim();
    if (value.isEmpty) continue;
    final key = value.toLowerCase();
    if (!seen.add(key)) continue;
    out.add(value);
  }
  return out;
}
