import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/live_session.dart';
import '../domain/logged_set.dart';
import '../domain/rep_target.dart';
import '../domain/session_exercise.dart';
import '../domain/session_status.dart';
import '../domain/set_outcome.dart';
import '../domain/set_type.dart';
import '../domain/workout_session_repository.dart';

/// The real [WorkoutSessionRepository], backed by Firestore's
/// `users/{uid}/workoutSessions` subcollection. This is the *only* place
/// Firestore SDK types are allowed — everything above consumes the domain
/// [LiveSession]/[SessionExercise]/[LoggedSet] models.
///
/// Each [LiveSession] embeds its `exercises → sets` tree as a plain array
/// field, mirroring the plan repository's embedding of a plan's
/// `days → exercises → sets`. The repository is constructed once at app root,
/// before sign-in, so it resolves the signed-in user from an injected
/// [UidSource] rather than holding a `uid` of its own.
class FirestoreWorkoutSessionRepository implements WorkoutSessionRepository {
  FirestoreWorkoutSessionRepository({FirebaseFirestore? firestore, required this.uidSource})
    : _firestore = firestore ?? FirebaseFirestore.instance {
    // Start listening immediately, independent of whether any widget is
    // currently watching — see FirestoreWorkoutPlanRepository's constructor
    // doc for the full rationale (this repo had the matching bug: finishing
    // a session while nothing was subscribed left the cache stale for the
    // next subscriber to replay).
    _start();
  }

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  List<LiveSession> _sessions = const [];
  bool _hasSnapshot = false;
  StreamController<List<LiveSession>>? _controller;
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _querySub;

  @override
  List<LiveSession> get current => _sessions;

  @override
  Stream<List<LiveSession>> watchAll() async* {
    _controller ??= StreamController<List<LiveSession>>.broadcast();
    // A broadcast stream never replays its latest value to a *late*
    // subscriber — replay the cached list on subscribe so every listener
    // sees the current value immediately, matching the in-memory contract.
    // Because the underlying Firestore listener runs for the repository's
    // whole lifetime (see the constructor), this cached value is never stale.
    if (_hasSnapshot) yield _sessions;
    yield* _controller!.stream;
  }

  @override
  LiveSession? get activeSession => _firstActive(_sessions);

  @override
  Stream<LiveSession?> watchActiveSession() => watchAll().map(_firstActive);

  LiveSession? _firstActive(List<LiveSession> sessions) {
    for (final s in sessions) {
      if (s.status == SessionStatus.active) return s;
    }
    return null;
  }

  void _start() {
    _uidSub = _uidWithInitial().listen(_onUidChanged);
  }

  /// Tears down the always-on listener — not called in production (the
  /// repository lives for the app's process lifetime), only for explicit
  /// teardown in tests.
  void dispose() {
    _uidSub?.cancel();
    _querySub?.cancel();
    _controller?.close();
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
    _querySub = _sessionsCollection(uid)
        .orderBy('startedAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          _emit(snapshot.docs.map(_sessionFromDoc).toList(growable: false));
        }, onError: (e, s) => _controller?.addError(e, s));
  }

  void _emit(List<LiveSession> sessions) {
    _sessions = sessions;
    _hasSnapshot = true;
    _controller?.add(_sessions);
  }

  @override
  Future<void> saveSession(LiveSession session) {
    final uid = _requireUid();
    return _sessionsCollection(uid).doc(session.id).set({
      'planId': session.planId,
      'dayId': session.dayId,
      'dayLabel': session.dayLabel,
      'status': session.status.name,
      'startedAt': Timestamp.fromDate(session.startedAt),
      'completedAt': session.completedAt == null
          ? null
          : Timestamp.fromDate(session.completedAt!),
      'pausedAt': session.pausedAt == null ? null : Timestamp.fromDate(session.pausedAt!),
      'pausedAccumMs': session.pausedAccumMs,
      'exercises': session.exercises.map(_exerciseToMap).toList(),
      'schemaVersion': 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteSession(String id) {
    final uid = _requireUid();
    return _sessionsCollection(uid).doc(id).delete();
  }

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreWorkoutSessionRepository: no signed-in user.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _sessionsCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('workoutSessions');

  Map<String, dynamic> _exerciseToMap(SessionExercise exercise) => {
    'id': exercise.id,
    'exerciseId': exercise.exerciseId,
    'name': exercise.name,
    'muscleGroup': exercise.muscleGroup,
    'restSeconds': exercise.restSeconds,
    'sets': exercise.sets.map(_setToMap).toList(),
  };

  Map<String, dynamic> _setToMap(LoggedSet set) => {
    'id': set.id,
    'repKind': set.target.kind.name,
    'repMin': set.target.min,
    'repMax': set.target.max,
    'targetWeightKg': set.targetWeightKg,
    'actualReps': set.actualReps,
    'actualWeightKg': set.actualWeightKg,
    'rpe': set.rpe,
    'type': set.type.name,
    'outcome': set.outcome.name,
  };

  LiveSession _sessionFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final startedAt = data['startedAt'];
    final completedAt = data['completedAt'];
    final pausedAt = data['pausedAt'];
    final rawExercises = (data['exercises'] as List<dynamic>?) ?? const [];
    return LiveSession(
      id: doc.id,
      planId: data['planId'] as String? ?? '',
      dayId: data['dayId'] as String? ?? '',
      dayLabel: data['dayLabel'] as String? ?? '',
      status: sessionStatusFromName(data['status'] as String?),
      startedAt: startedAt is Timestamp ? startedAt.toDate() : DateTime.now(),
      completedAt: completedAt is Timestamp ? completedAt.toDate() : null,
      pausedAt: pausedAt is Timestamp ? pausedAt.toDate() : null,
      pausedAccumMs: (data['pausedAccumMs'] as num?)?.toInt() ?? 0,
      exercises: rawExercises.map(_exerciseFromMap).toList(growable: false),
    );
  }

  SessionExercise _exerciseFromMap(dynamic raw) {
    final map = (raw as Map).cast<String, dynamic>();
    final rawSets = (map['sets'] as List<dynamic>?) ?? const [];
    return SessionExercise(
      id: map['id'] as String? ?? '',
      exerciseId: map['exerciseId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      muscleGroup: map['muscleGroup'] as String?,
      restSeconds: (map['restSeconds'] as num?)?.toInt() ?? 0,
      sets: rawSets.map(_setFromMap).toList(growable: false),
    );
  }

  LoggedSet _setFromMap(dynamic raw) {
    final map = (raw as Map).cast<String, dynamic>();
    return LoggedSet(
      id: map['id'] as String? ?? '',
      target: _repTargetFromMap(map),
      targetWeightKg: (map['targetWeightKg'] as num?)?.toDouble(),
      actualReps: (map['actualReps'] as num?)?.toInt(),
      actualWeightKg: (map['actualWeightKg'] as num?)?.toDouble(),
      rpe: (map['rpe'] as num?)?.toDouble(),
      type: setTypeFromName(map['type'] as String?),
      outcome: _outcomeFromMap(map),
    );
  }

  /// Reads a set's outcome, migrating a doc written before this field
  /// existed: when `outcome` is absent, fall back to the legacy `done` bool
  /// — `true` becomes `completed`, anything else (including missing)
  /// becomes `pending`. A doc that already has `outcome` always wins, since
  /// every write from here on carries it.
  SetOutcome _outcomeFromMap(Map<String, dynamic> map) {
    final rawOutcome = map['outcome'] as String?;
    if (rawOutcome != null) return setOutcomeFromName(rawOutcome);
    final legacyDone = map['done'] as bool? ?? false;
    return legacyDone ? SetOutcome.completed : SetOutcome.pending;
  }

  RepTarget _repTargetFromMap(Map<String, dynamic> map) {
    final kind = repTargetKindFromName(map['repKind'] as String?);
    final min = (map['repMin'] as num?)?.toInt();
    final max = (map['repMax'] as num?)?.toInt();
    switch (kind) {
      case RepTargetKind.fixed:
        return RepTarget.fixed(min ?? 0);
      case RepTargetKind.range:
        return RepTarget.range(min ?? 0, max ?? (min ?? 0));
      case RepTargetKind.toFailure:
        return const RepTarget.toFailure();
    }
  }
}
