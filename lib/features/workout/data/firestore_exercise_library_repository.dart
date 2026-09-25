import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/identity/canonical_exercise.dart';
import '../domain/identity/equipment.dart';
import '../domain/identity/exercise_alias.dart';
import '../domain/identity/exercise_library_repository.dart';

/// The real [ExerciseLibraryRepository]: canonical exercises at
/// `users/{uid}/exercises/{exerciseId}` and legacy-id aliases at
/// `users/{uid}/exerciseAliases/{legacyId}` — two collections so the identity
/// and the mapping into it never share a document (see `ExerciseAlias`).
///
/// Constructed once at app root and re-scoped through [UidSource], like the
/// settings repository. [current] is kept warm by always-on listeners because
/// history readers resolve ids synchronously while they build.
class FirestoreExerciseLibraryRepository implements ExerciseLibraryRepository {
  FirestoreExerciseLibraryRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _listenForUid(uidSource.currentUid());
    _uidSub = uidSource.uidChanges.listen(_listenForUid);
  }

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  Map<String, CanonicalExercise> _exercises = const {};
  List<ExerciseAlias> _aliases = const [];
  bool _exercisesLoaded = false;
  bool _aliasesLoaded = false;
  ExerciseLibrary _current = ExerciseLibrary.empty;
  final _controller = StreamController<ExerciseLibrary>.broadcast();
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _exercisesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _aliasesSub;

  CollectionReference<Map<String, dynamic>> _exercisesOf(String uid) =>
      _firestore.collection('users').doc(uid).collection('exercises');

  CollectionReference<Map<String, dynamic>> _aliasesOf(String uid) =>
      _firestore.collection('users').doc(uid).collection('exerciseAliases');

  void _listenForUid(String? uid) {
    _exercisesSub?.cancel();
    _aliasesSub?.cancel();
    _exercises = const {};
    _aliases = const [];
    _exercisesLoaded = false;
    _aliasesLoaded = false;
    _emit();
    if (uid == null) return;
    _exercisesSub = _exercisesOf(uid).snapshots().listen((snap) {
      _exercises = {
        for (final d in snap.docs) d.id: _exerciseFromDoc(d.id, d.data()),
      };
      _exercisesLoaded = true;
      _emit();
    }, onError: _controller.addError);
    _aliasesSub = _aliasesOf(uid).snapshots().listen((snap) {
      _aliases = [for (final d in snap.docs) ?_aliasFromDoc(d.id, d.data())];
      _aliasesLoaded = true;
      _emit();
    }, onError: _controller.addError);
  }

  void _emit() {
    _current = ExerciseLibrary(
      exercises: _exercises,
      aliases: _aliases,
      loaded: _exercisesLoaded && _aliasesLoaded,
    );
    if (!_controller.isClosed) _controller.add(_current);
  }

  @override
  ExerciseLibrary get current => _current;

  @override
  Stream<ExerciseLibrary> watch() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<void> saveExercise(CanonicalExercise exercise) {
    final uid = uidSource.requireUid(this);
    return _exercisesOf(uid).doc(exercise.id).set(_exerciseToDoc(exercise));
  }

  @override
  Future<void> saveExercises(List<CanonicalExercise> exercises) async {
    if (exercises.isEmpty) return;
    final uid = uidSource.requireUid(this);
    // A batch holds 500 writes; a migration of a long history can exceed it.
    for (var i = 0; i < exercises.length; i += 400) {
      final batch = _firestore.batch();
      for (final e in exercises.skip(i).take(400)) {
        batch.set(_exercisesOf(uid).doc(e.id), _exerciseToDoc(e));
      }
      await batch.commit();
    }
  }

  Map<String, Object?> _exerciseToDoc(CanonicalExercise exercise) => {
    'name': exercise.name,
    'equipment': exercise.equipment?.name,
    'muscleGroup': exercise.muscleGroup,
    'createdAt': Timestamp.fromDate(exercise.createdAt),
    if (exercise.distinctFrom.isNotEmpty)
      'distinctFrom': exercise.distinctFrom.toList()..sort(),
    'schemaVersion': 1,
  };

  @override
  Future<void> saveAliases(List<ExerciseAlias> aliases) async {
    if (aliases.isEmpty) return;
    final uid = uidSource.requireUid(this);
    for (var i = 0; i < aliases.length; i += 400) {
      final batch = _firestore.batch();
      for (final a in aliases.skip(i).take(400)) {
        batch.set(_aliasesOf(uid).doc(a.legacyId), {
          'canonicalId': a.canonicalId,
          'source': a.source.name,
          'createdAt': Timestamp.fromDate(a.createdAt),
          'schemaVersion': 1,
        });
      }
      await batch.commit();
    }
  }

  @override
  Future<void> removeAlias(String legacyId) {
    final uid = uidSource.requireUid(this);
    return _aliasesOf(uid).doc(legacyId).delete();
  }

  CanonicalExercise _exerciseFromDoc(String id, Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    return CanonicalExercise(
      id: id,
      name: data['name'] as String? ?? '',
      equipment: equipmentFromName(data['equipment'] as String?),
      muscleGroup: data['muscleGroup'] as String?,
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      distinctFrom: {
        for (final id in (data['distinctFrom'] as List?) ?? const [])
          if (id is String) id,
      },
    );
  }

  /// Null for a doc without a usable target — an alias that points nowhere
  /// is skipped rather than resolving ids to an empty string.
  ExerciseAlias? _aliasFromDoc(String legacyId, Map<String, dynamic> data) {
    final canonicalId = data['canonicalId'];
    if (canonicalId is! String || canonicalId.isEmpty) return null;
    final createdAt = data['createdAt'];
    return ExerciseAlias(
      legacyId: legacyId,
      canonicalId: canonicalId,
      source: aliasSourceFromName(data['source'] as String?),
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Tears down the always-on listeners — only called in tests.
  void dispose() {
    _uidSub?.cancel();
    _exercisesSub?.cancel();
    _aliasesSub?.cancel();
    _controller.close();
  }
}
