/// Why an [ExerciseAlias] exists.
enum AliasSource {
  /// Written by the one-time identity migration, grouping slots that were
  /// already the same exercise.
  migration,

  /// The user confirmed two exercises are the same one.
  merge,
}

AliasSource aliasSourceFromName(String? name) => AliasSource.values.firstWhere(
  (s) => s.name == name,
  orElse: () => AliasSource.merge,
);

/// One legacy exercise id that now means another canonical exercise.
///
/// The mapping layer between old records and the identity model, kept apart
/// from `CanonicalExercise` on purpose: a canonical exercise stays a clean
/// description of a movement, and everything about how older ids fold into
/// it lives here.
///
/// **Non-destructive by construction.** A session logged before an identity
/// existed keeps the slot id it was written with, forever. This alias is
/// applied when history is *read* (`ExerciseIdentityResolver`), never written
/// back — so removing an alias restores the old reading exactly, and no
/// migration ever touches a logged set.
class ExerciseAlias {
  const ExerciseAlias({
    required this.legacyId,
    required this.canonicalId,
    required this.source,
    required this.createdAt,
  });

  /// The id as it appears in older records — in practice a plan slot id,
  /// since that is what every session wrote before identities existed.
  final String legacyId;

  /// The canonical exercise [legacyId] now resolves to.
  final String canonicalId;

  final AliasSource source;
  final DateTime createdAt;
}
