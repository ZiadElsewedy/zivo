/// What an exercise is performed with — the part of an identity that two
/// similar names most often disagree on (an incline *dumbbell* press and an
/// incline *machine* press train the same muscles and progress separately).
///
/// Coarse on purpose. Attachments (an EZ/zigzag bar on a cable, a rope) are
/// part of the name, not a separate equipment kind.
enum Equipment {
  barbell,
  dumbbell,
  machine,
  cable,
  smith,
  kettlebell,
  band,
  bodyweight,
}

/// Parses a stored equipment name; null for anything unknown (including
/// null), so a value written by a newer client never crashes an older one.
Equipment? equipmentFromName(String? name) {
  for (final e in Equipment.values) {
    if (e.name == name) return e;
  }
  return null;
}

/// Name words that name the equipment outright. Multi-word phrases are
/// matched on the normalized, space-joined token string.
const Map<String, Equipment> _equipmentWords = {
  'barbell': Equipment.barbell,
  'bb': Equipment.barbell,
  'dumbbell': Equipment.dumbbell,
  'db': Equipment.dumbbell,
  'machine': Equipment.machine,
  'cable': Equipment.cable,
  'smith': Equipment.smith,
  'kettlebell': Equipment.kettlebell,
  'kb': Equipment.kettlebell,
  'band': Equipment.band,
  'bodyweight': Equipment.bodyweight,
};

/// Movements that only exist on one kind of equipment, so the name implies
/// it even without saying "machine".
const Map<String, Equipment> _equipmentPhrases = {
  // A bench press that names no equipment is a barbell press by gym
  // convention; "Dumbbell Bench Press" states its own and wins (words are
  // checked before phrases).
  'bench press': Equipment.barbell,
  'pec deck': Equipment.machine,
  'rear delt fly': Equipment.machine,
  'leg press': Equipment.machine,
  'hack squat': Equipment.machine,
  'leg extension': Equipment.machine,
  'leg curl': Equipment.machine,
  'lat pulldown': Equipment.cable,
  'pushdown': Equipment.cable,
  'face pull': Equipment.cable,
};

/// The equipment a name states or implies, or null when it doesn't. Takes
/// tokens already normalized by `normalizeExerciseTokens`.
Equipment? inferEquipmentFromTokens(List<String> tokens) {
  for (final t in tokens) {
    final e = _equipmentWords[t];
    if (e != null) return e;
  }
  final joined = ' ${tokens.join(' ')} ';
  for (final entry in _equipmentPhrases.entries) {
    if (joined.contains(' ${entry.key} ')) return entry.value;
  }
  return null;
}

/// Whether [token] only names equipment — dropped when comparing what the
/// movement itself is, because equipment is compared separately.
bool isEquipmentWord(String token) => _equipmentWords.containsKey(token);
