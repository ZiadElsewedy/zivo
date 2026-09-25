import 'canonical_exercise.dart';
import 'exercise_alias.dart';
import 'exercise_identity_resolver.dart';

/// A snapshot of the account's exercise identities: the canonical exercises
/// and, separately, the legacy-id aliases that fold older records into them.
class ExerciseLibrary {
  ExerciseLibrary({this.exercises = const {}, this.aliases = const []});

  static final empty = ExerciseLibrary();

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

  Future<void> saveAliases(List<ExerciseAlias> aliases);

  /// Undoes a merge for one legacy id. Only the mapping goes: no logged
  /// session is touched, so its history reads as it did before the alias.
  Future<void> removeAlias(String legacyId);
}
