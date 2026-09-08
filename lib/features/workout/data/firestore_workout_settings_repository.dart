import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/workout_settings.dart';
import '../domain/workout_settings_repository.dart';

/// The real [WorkoutSettingsRepository], backed by one document per account at
/// `users/{uid}/settings/workout` — the settings collection whose rule is
/// deliberately not pinned to a field vocabulary, so this needs no rules
/// change (see `firestore.rules`, "Per-account settings").
///
/// Constructed once at app root without a uid and re-scoped through
/// [UidSource], like every other repository here. [current] is kept warm by an
/// always-on listener because the staleness sweep is synchronous at the point
/// it needs a threshold.
class FirestoreWorkoutSettingsRepository implements WorkoutSettingsRepository {
  FirestoreWorkoutSettingsRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _listenForUid(uidSource.currentUid());
    _uidSub = uidSource.uidChanges.listen(_listenForUid);
  }

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  WorkoutSettings _current = WorkoutSettings.defaults;
  final _controller = StreamController<WorkoutSettings>.broadcast();
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection('users').doc(uid).collection('settings').doc('workout');

  void _listenForUid(String? uid) {
    _docSub?.cancel();
    if (uid == null) {
      _emit(WorkoutSettings.defaults);
      return;
    }
    _docSub = _doc(uid).snapshots().listen(
      (snap) => _emit(_fromSnap(snap)),
      onError: (Object error) => _controller.addError(error),
    );
  }

  void _emit(WorkoutSettings settings) {
    _current = settings;
    if (!_controller.isClosed) _controller.add(settings);
  }

  @override
  WorkoutSettings get current => _current;

  @override
  Stream<WorkoutSettings> watch() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<void> save(WorkoutSettings settings) {
    final uid = uidSource.requireUid(this);
    return _doc(uid).set({
      'maxSessionMinutes': settings.maxSessionMinutes,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  WorkoutSettings _fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    if (data == null) return WorkoutSettings.defaults;
    return WorkoutSettings(
      maxSessionMinutes: maxSessionMinutesFrom(data['maxSessionMinutes']),
    );
  }

  /// Tears down the always-on listener — not called in production (the
  /// repository lives for the app's process lifetime), only in tests.
  void dispose() {
    _uidSub?.cancel();
    _docSub?.cancel();
    _controller.close();
  }
}
