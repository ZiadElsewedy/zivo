import 'canonical_exercise.dart';
import 'equipment.dart';

/// Decides whether a name someone typed, imported or dictated is an exercise
/// they already have — the only place a name is allowed to *suggest* an
/// identity. It never assigns one by itself beyond the unambiguous case:
/// names are how people describe movements, not how they identify them
/// ("Incline Chest Press" might mean the dumbbell or the machine).
///
/// Two gates, in order:
///
/// 1. **Equipment.** Two different known equipment kinds are never the same
///    exercise, however alike the names — Incline Dumbbell Press and Incline
///    Machine Chest Press progress separately. Unknown equipment on either
///    side never counts as agreement, so it can only ever be *suggested*.
/// 2. **The movement words** — the name normalized (case, punctuation,
///    plurals, known synonyms such as zigzag ≈ EZ) with equipment words
///    removed, compared as a set so word order doesn't matter
///    ("Seated Row (Wide Grip)" ≈ "Wide-Grip Seated Row").
///
/// Pure and synchronous; the flows that create exercises (manual add,
/// import review, in-session swap/add) ask it and put the answer in front of
/// the user.
class ExerciseMatch {
  const ExerciseMatch({this.confident, this.suggestions = const []});

  /// Same movement words AND the same known equipment (or neither states
  /// one): safe to link without asking, shown with a way to undo it.
  final CanonicalExercise? confident;

  /// Plausibly the same — ask "same exercise?" rather than link.
  final List<CanonicalExercise> suggestions;

  bool get isNone => confident == null && suggestions.isEmpty;
}

ExerciseMatch matchExercise({
  required String name,
  Equipment? equipment,
  required Iterable<CanonicalExercise> library,
}) {
  final probe = ExerciseSignature.of(name, equipment: equipment);
  if (probe.movement.isEmpty) return const ExerciseMatch();

  CanonicalExercise? confident;
  final suggestions = <CanonicalExercise>[];
  for (final candidate in library) {
    final other = ExerciseSignature.of(
      candidate.name,
      equipment: candidate.equipment,
    );
    switch (probe.compare(other)) {
      case SignatureMatch.same:
        confident ??= candidate;
      case SignatureMatch.plausible:
        suggestions.add(candidate);
      case SignatureMatch.different:
        break;
    }
  }
  return ExerciseMatch(confident: confident, suggestions: suggestions);
}

/// Whether renaming [from] to [to] names a **different movement** rather
/// than the same one spelled better — the question a plan edit has to ask
/// before a slot keeps or loses its history.
///
/// Deliberately lenient toward "same": a typo fix ("Bench Pres" → "Bench
/// Press") or rewording must never cut a slot off from its history. Only
/// changes that alter what the numbers mean count as different: another
/// known equipment, a variation word gained or lost (incline, seated,
/// single-arm …), or no movement word in common at all.
bool isDifferentMovement(String from, String to) {
  final a = ExerciseSignature.of(from);
  final b = ExerciseSignature.of(to);
  if (a.equipment != null && b.equipment != null && a.equipment != b.equipment) {
    return true;
  }
  final changed = a.movement.difference(b.movement).union(
    b.movement.difference(a.movement),
  );
  if (changed.any(_variationWords.contains)) return true;
  return a.movement.isNotEmpty &&
      b.movement.isNotEmpty &&
      a.movement.intersection(b.movement).isEmpty;
}

enum SignatureMatch { same, plausible, different }

/// A name reduced to what matters for identity: the movement words and the
/// equipment (stated, or implied by the name).
class ExerciseSignature {
  ExerciseSignature._(this.movement, this.equipment);

  factory ExerciseSignature.of(String name, {Equipment? equipment}) {
    final tokens = normalizeExerciseTokens(name);
    return ExerciseSignature._(
      tokens.where((t) => !isEquipmentWord(t)).toSet(),
      equipment ?? inferEquipmentFromTokens(tokens),
    );
  }

  final Set<String> movement;
  final Equipment? equipment;

  SignatureMatch compare(ExerciseSignature other) {
    final a = equipment;
    final b = other.equipment;
    if (a != null && b != null && a != b) return SignatureMatch.different;
    final bothKnown = a != null && b != null;
    final neitherKnown = a == null && b == null;

    if (_sameSet(movement, other.movement)) {
      return bothKnown || neitherKnown
          ? SignatureMatch.same
          : SignatureMatch.plausible;
    }
    // One name is the other plus a qualifier ("Hammer Curl" and "Hammer
    // Dumbbell Curl" once equipment is set aside; "Incline Press" and
    // "Incline Chest Press"). Worth asking — unless the extra words change
    // the movement itself (single-arm, seated, incline …), which makes it a
    // different exercise, not a more specific name for the same one.
    final smaller = movement.length <= other.movement.length
        ? movement
        : other.movement;
    final larger = identical(smaller, movement) ? other.movement : movement;
    if (smaller.isNotEmpty && larger.containsAll(smaller)) {
      final extra = larger.difference(smaller);
      if (extra.any(_variationWords.contains)) return SignatureMatch.different;
      return SignatureMatch.plausible;
    }
    return SignatureMatch.different;
  }

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}

/// Words that make a movement a different variation when one name has them
/// and the other doesn't: angle, laterality, stance and body position all
/// change what the numbers mean.
const Set<String> _variationWords = {
  'single',
  'one',
  'unilateral',
  'alternating',
  'incline',
  'decline',
  'flat',
  'seated',
  'standing',
  'lying',
  'kneeling',
  'overhead',
  'front',
  'reverse',
  'close',
  'wide',
  'narrow',
  'sumo',
  'romanian',
  'stiff',
  'deficit',
  'pause',
  'paused',
  // Grip, support and bar change the movement as much as angle does — a
  // hammer curl is not a dumbbell curl with a longer name (all found as
  // false "same exercise?" suggestions on a real library).
  'hammer',
  'neutral',
  'supinated',
  'pronated',
  'underhand',
  'overhand',
  'preacher',
  'concentration',
  'spider',
  'bayesian',
  'supported',
  'ez',
};

/// Multi-word synonyms, applied to the space-joined lowercase name before it
/// is split, longest first. Each maps a way people write a movement onto one
/// spelling, so "Rear Pec Deck" and "Reverse Pec Deck" meet as the same words.
const List<(String, String)> _phraseSynonyms = [
  ('reverse pec deck', 'rear delt fly'),
  ('rear pec deck', 'rear delt fly'),
  ('rear delt pec deck', 'rear delt fly'),
  ('rear delt rear delt fly', 'rear delt fly'),
  ('rear delt reverse fly', 'rear delt fly'),
  ('zig zag', 'ez'),
  ('zigzag', 'ez'),
  ('ez bar', 'ez'),
  ('e z', 'ez'),
  ('pull down', 'pulldown'),
  ('push down', 'pushdown'),
  ('pull up', 'pullup'),
  ('push up', 'pushup'),
  ('chin up', 'chinup'),
  ('body weight', 'bodyweight'),
  ('dumb bell', 'dumbbell'),
  ('bar bell', 'barbell'),
  ('single arm', 'single'),
  ('one arm', 'single'),
  ('single leg', 'single'),
  ('one leg', 'single'),
];

const Map<String, String> _wordSynonyms = {
  'raises': 'raise',
  'dumbbells': 'dumbbell',
  'db': 'dumbbell',
  'dbs': 'dumbbell',
  'bb': 'barbell',
  'rdl': 'romanian deadlift',
  'ohp': 'overhead press',
  'tricep': 'triceps',
  'bicep': 'biceps',
  'delts': 'delt',
  'flye': 'fly',
  'flyes': 'fly',
  'flies': 'fly',
};

/// Words that carry no identity — dropped before comparing.
const Set<String> _fillerWords = {
  'the',
  'a',
  'an',
  'with',
  'on',
  'and',
  'grip',
};

/// The name as a list of comparable words: lowercased, punctuation removed,
/// synonyms applied, plurals folded, filler dropped. Stable and pure — the
/// same name always yields the same tokens.
List<String> normalizeExerciseTokens(String name) {
  var text = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  text = ' $text ';
  for (final (from, to) in _phraseSynonyms) {
    text = text.replaceAll(' $from ', ' $to ');
  }
  final out = <String>[];
  for (final raw in text.trim().split(' ')) {
    if (raw.isEmpty) continue;
    final mapped = _wordSynonyms[raw] ?? _singular(raw);
    for (final word in mapped.split(' ')) {
      if (!_fillerWords.contains(word)) out.add(word);
    }
  }
  return out;
}

/// Folds a plain English plural ("curls", "extensions", "rows") without
/// touching words that merely end in s ("press", "triceps", "abs").
String _singular(String word) {
  if (word.length <= 3) return word;
  if (word.endsWith('ss') || word.endsWith('us') || word.endsWith('ps')) {
    return word;
  }
  if (word.endsWith('s')) return word.substring(0, word.length - 1);
  return word;
}
