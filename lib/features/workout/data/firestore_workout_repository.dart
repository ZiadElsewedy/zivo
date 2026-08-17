import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/exercise.dart';
import '../domain/workout.dart';
import '../domain/workout_repository.dart';

/// The real [WorkoutRepository], backed by Firestore's `users/{uid}/workouts`
/// subcollection. This is the *only* place Firestore SDK types are allowed —
/// everything above consumes the domain [Workout]/[Exercise] models.
///
/// The repository is constructed once at app root, before sign-in, so it has
/// no `uid` of its own — it resolves the signed-in user from an injected
/// [UidSource] instead, which re-scopes `watchAll()` whenever the uid changes
/// (including to/from signed-out).
///
/// Each [Workout] embeds a bounded list of [Exercise]s, always loaded with
/// the parent, so they are stored as a plain array field on the workout doc
/// rather than a subcollection.
class FirestoreWorkoutRepository implements WorkoutRepository {
  FirestoreWorkoutRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  List<Workout> _current = const [];
  bool _hasSnapshot = false;
  StreamController<List<Workout>>? _controller;
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _querySub;

  @override
  List<Workout> get current => List.unmodifiable(_current);

  @override
  Stream<List<Workout>> watchAll() async* {
    _controller ??= StreamController<List<Workout>>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
    // A broadcast stream never replays its latest value to a *late* subscriber.
    // The Today dashboard subscribes first (it stays alive in the shell's
    // IndexedStack) and consumes the initial snapshot, so a Hub detail page
    // opened afterwards would otherwise sit on ConnectionState.waiting forever
    // whenever the collection is empty. Replay the cached snapshot on subscribe
    // so every listener sees the current value immediately — matching the
    // in-memory repo contract the pages and tests rely on.
    if (_hasSnapshot) yield current;
    yield* _controller!.stream;
  }

  void _start() {
    _uidSub = _uidWithInitial().listen(_onUidChanged);
  }

  void _stop() {
    _uidSub?.cancel();
    _uidSub = null;
    _querySub?.cancel();
    _querySub = null;
  }

  Stream<String?> _uidWithInitial() async* {
    yield uidSource.currentUid();
    yield* uidSource.uidChanges;
  }

  void _onUidChanged(String? uid) {
    _querySub?.cancel();
    if (uid == null) {
      _emit(const []);
      return;
    }
    _querySub = _workoutsCollection(uid)
        .orderBy('performedAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          _emit(snapshot.docs.map(_fromDoc).toList(growable: false));
        }, onError: (e, s) => _controller?.addError(e, s));
  }

  void _emit(List<Workout> workouts) {
    _current = workouts;
    _hasSnapshot = true;
    _controller?.add(current);
  }

  @override
  Future<void> add(Workout workout) {
    final uid = _requireUid();
    return _workoutsCollection(uid).doc(workout.id).set({
      'title': workout.title,
      'performedAt': Timestamp.fromDate(workout.performedAt),
      'durationMinutes': workout.durationMinutes,
      'exercises': workout.exercises
          .map(
            (e) => {
              'name': e.name,
              'sets': e.sets,
              'reps': e.reps,
              'weightKg': e.weightKg,
            },
          )
          .toList(),
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> update(Workout workout) {
    final uid = _requireUid();
    return _workoutsCollection(uid).doc(workout.id).update({
      'title': workout.title,
      'performedAt': Timestamp.fromDate(workout.performedAt),
      'durationMinutes': workout.durationMinutes,
      'exercises': workout.exercises
          .map(
            (e) => {
              'name': e.name,
              'sets': e.sets,
              'reps': e.reps,
              'weightKg': e.weightKg,
            },
          )
          .toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> remove(String id) {
    final uid = _requireUid();
    return _workoutsCollection(uid).doc(id).delete();
  }

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreWorkoutRepository: no signed-in user.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _workoutsCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('workouts');

  Workout _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final performedAt = data['performedAt'];
    final rawList = (data['exercises'] as List<dynamic>?) ?? const [];
    final exercises = rawList
        .map((raw) {
          final m = (raw as Map).cast<String, dynamic>();
          return Exercise(
            name: m['name'] as String? ?? '',
            sets: (m['sets'] as num?)?.toInt() ?? 0,
            reps: (m['reps'] as num?)?.toInt() ?? 0,
            weightKg: (m['weightKg'] as num?)?.toDouble(),
          );
        })
        .toList(growable: false);
    return Workout(
      id: doc.id,
      title: data['title'] as String? ?? '',
      performedAt: performedAt is Timestamp
          ? performedAt.toDate()
          : DateTime.now(),
      durationMinutes: (data['durationMinutes'] as num?)?.toInt(),
      exercises: exercises,
    );
  }
}
