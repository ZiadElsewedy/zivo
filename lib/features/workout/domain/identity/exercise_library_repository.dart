import 'canonical_exercise.dart';
import 'exercise_alias.dart';
import 'exercise_identity_resolver.dart';

/// A snapshot of the account's exercise identities: the canonical exercises
/// and, separately, the legacy-id aliases that fold older records into them.
class ExerciseLibrary {
  ExerciseLibrary({
    this.exercises = const {},
    this.aliases = const [],
    this.loaded = true,
  });

  /// Nothing known yet — signed out, or before the first read.
  static final empty = ExerciseLibrary(loaded: false);

  /// Whether this reflects what is actually stored. False before the first
  /// read has landed, when an empty library means "not known yet" rather
  /// than "none" — anything that WRITES identities must wait for it, or it
  /// would re-create exercises that already exist.
  final bool loaded;

  /// Keyed by [CanonicalExercise.id].
  final Map<String, CanonicalExercise> exercises;
  final List<ExerciseAlias> aliases;

  late final ExerciseIdentityResolver resolver = aliases.isEmpty
      ? ExerciseIdentityResolver.identity
      : ExerciseIdentityResolver(aliases);
}

/// The seam for exercise identities (`users/{uid}/exercises` and
/// `users/{uid}/exerciseAliases`). Firestore and in-memory implementations
/// live in `data/`.
///
/// Emits [ExerciseLibrary.empty] when signed out or before the first read,
/// so a synchronous reader always resolves — and an empty library resolves
/// every id to itself, which is the pre-identity behaviour exactly.
abstract interface class ExerciseLibraryRepository {
  ExerciseLibrary get current;

  Stream<ExerciseLibrary> watch();

  Future<void> saveExercise(CanonicalExercise exercise);

  /// Saves several at once (the identity migration's write).
  Future<void> saveExercises(List<CanonicalExercise> exercises);

  Future<void> saveAliases(List<ExerciseAlias> aliases);

  /// Undoes a merge for one legacy id. Only the mapping goes: no logged
  /// session is touched, so its history reads as it did before the alias.
  Future<void> removeAlias(String legacyId);
}
