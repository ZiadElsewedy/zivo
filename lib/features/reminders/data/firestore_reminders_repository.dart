import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/reminder.dart';
import '../domain/reminders_repository.dart';

/// The real [RemindersRepository], backed by one document per account at
/// `users/{uid}/settings/reminders` — the per-account settings collection whose
/// rule is deliberately not pinned to a field vocabulary, so this needs no rules
/// change (see `firestore.rules`, "Per-account settings").
///
/// Structurally identical to `FirestoreWorkoutSettingsRepository`: constructed
/// once at app root without a uid and re-scoped through [UidSource], with an
/// always-on listener that keeps [current] warm and emits an empty list when
/// signed out.
class FirestoreRemindersRepository implements RemindersRepository {
  FirestoreRemindersRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _listenForUid(uidSource.currentUid());
    _uidSub = uidSource.uidChanges.listen(_listenForUid);
  }

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  List<Reminder> _current = const [];
  final _controller = StreamController<List<Reminder>>.broadcast();
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('settings')
      .doc('reminders');

  void _listenForUid(String? uid) {
    _docSub?.cancel();
    if (uid == null) {
      _emit(const []);
      return;
    }
    _docSub = _doc(uid).snapshots().listen(
      (snap) => _emit(_fromSnap(snap)),
      onError: (Object error) => _controller.addError(error),
    );
  }

  void _emit(List<Reminder> reminders) {
    _current = reminders;
    if (!_controller.isClosed) _controller.add(reminders);
  }

  @override
  List<Reminder> get current => _current;

  @override
  Stream<List<Reminder>> watch() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<void> save(List<Reminder> reminders) {
    final uid = uidSource.requireUid(this);
    return _doc(uid).set({
      'items': [for (final r in reminders) r.toMap()],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  List<Reminder> _fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) =>
      remindersFromStored(snap.data()?['items']);

  /// Tears down the always-on listener — not called in production (the
  /// repository lives for the app's process lifetime), only in tests.
  void dispose() {
    _uidSub?.cancel();
    _docSub?.cancel();
    _controller.close();
  }
}
