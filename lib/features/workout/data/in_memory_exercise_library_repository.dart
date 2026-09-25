import 'dart:async';

import '../domain/identity/canonical_exercise.dart';
import '../domain/identity/exercise_alias.dart';
import '../domain/identity/exercise_library_repository.dart';

/// The offline/test [ExerciseLibraryRepository] — the same contract without
/// Firestore.
class InMemoryExerciseLibraryRepository implements ExerciseLibraryRepository {
  InMemoryExerciseLibraryRepository({
    Iterable<CanonicalExercise> exercises = const [],
    Iterable<ExerciseAlias> aliases = const [],
  }) : _exercises = {for (final e in exercises) e.id: e},
       _aliases = {for (final a in aliases) a.legacyId: a};

  final Map<String, CanonicalExercise> _exercises;
  final Map<String, ExerciseAlias> _aliases;
  final _controller = StreamController<ExerciseLibrary>.broadcast();

  late ExerciseLibrary _current = _snapshot();

  ExerciseLibrary _snapshot() => ExerciseLibrary(
    exercises: Map.unmodifiable(_exercises),
    aliases: List.unmodifiable(_aliases.values),
  );

  void _emit() {
    _current = _snapshot();
    _controller.add(_current);
  }

  @override
  ExerciseLibrary get current => _current;

  @override
  Stream<ExerciseLibrary> watch() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<void> saveExercise(CanonicalExercise exercise) async {
    _exercises[exercise.id] = exercise;
    _emit();
  }

  @override
  Future<void> saveAliases(List<ExerciseAlias> aliases) async {
    for (final a in aliases) {
      _aliases[a.legacyId] = a;
    }
    _emit();
  }

  @override
  Future<void> removeAlias(String legacyId) async {
    if (_aliases.remove(legacyId) != null) _emit();
  }

  void dispose() => _controller.close();
}
