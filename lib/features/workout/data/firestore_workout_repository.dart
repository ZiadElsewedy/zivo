import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_scoped_mirror.dart';
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
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _mirror = UidScopedMirror<List<Workout>>(
      uidSource: uidSource,
      signedOutValue: const [],
      source: (uid) => _workoutsCollection(uid)
          .orderBy('performedAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(_fromDoc).toList(growable: false)),
    )..start();
  }

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  late final UidScopedMirror<List<Workout>> _mirror;

  @override
  List<Workout> get current => List.unmodifiable(_mirror.current);

  @override
  Stream<List<Workout>> watchAll() => _mirror.watch();

  /// Tears down the always-on listener — not called in production (the
  /// repository lives for the app's process lifetime), only for explicit
  /// teardown in tests.
  void dispose() => _mirror.dispose();

  @override
  Future<void> add(Workout workout) {
    final uid = uidSource.requireUid(this);
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
    final uid = uidSource.requireUid(this);
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
    final uid = uidSource.requireUid(this);
    return _workoutsCollection(uid).doc(id).delete();
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
