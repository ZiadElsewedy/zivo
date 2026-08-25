import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/body_weight_entry.dart';
import '../domain/body_weight_repository.dart';

/// The real [BodyWeightRepository], backed by Firestore's
/// `users/{uid}/bodyWeightEntries` subcollection. This is the *only* place
/// Firestore SDK types are allowed — everything above consumes the domain
/// [BodyWeightEntry] model.
///
/// The repository is constructed once at app root, before sign-in, so it has
/// no `uid` of its own — it resolves the signed-in user from an injected
/// [UidSource] instead, which re-scopes `watchAll()` whenever the uid changes
/// (including to/from signed-out).
class FirestoreBodyWeightRepository implements BodyWeightRepository {
  FirestoreBodyWeightRepository({FirebaseFirestore? firestore, required this.uidSource})
    : _firestore = firestore ?? FirebaseFirestore.instance {
    // Start listening immediately, independent of whether any widget is
    // currently watching — see FirestoreWorkoutSessionRepository's
    // constructor doc for the full rationale (this repo had the matching
    // bug: saving a weigh-in while no screen was subscribed left the cache
    // stale, so the next subscriber first replayed the OLD list before the
    // fresh snapshot landed — a saved weigh-in appeared to vanish).
    _start();
  }

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  List<BodyWeightEntry> _current = const [];
  bool _hasSnapshot = false;
  StreamController<List<BodyWeightEntry>>? _controller;
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _querySub;

  @override
  List<BodyWeightEntry> get current => List.unmodifiable(_current);

  @override
  Stream<List<BodyWeightEntry>> watchAll() async* {
    _controller ??= StreamController<List<BodyWeightEntry>>.broadcast();
    // A broadcast stream never replays its latest value to a *late*
    // subscriber — replay the cached snapshot on subscribe so every listener
    // sees the current value immediately, matching the in-memory contract.
    // Because the underlying Firestore listener runs for the repository's
    // whole lifetime (see the constructor), this cached value is never stale.
    if (_hasSnapshot) yield current;
    yield* _controller!.stream;
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
    _querySub = _entriesCollection(uid)
        .orderBy('loggedAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          _emit(snapshot.docs.map(_fromDoc).toList(growable: false));
        }, onError: (e, s) => _controller?.addError(e, s));
  }

  void _emit(List<BodyWeightEntry> entries) {
    _current = entries;
    _hasSnapshot = true;
    _controller?.add(current);
  }

  @override
  Future<void> save(BodyWeightEntry entry) {
    final uid = _requireUid();
    return _entriesCollection(uid).doc(entry.id).set({
      'weightKg': entry.weightKg,
      'loggedAt': Timestamp.fromDate(entry.loggedAt),
      'schemaVersion': 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> remove(String id) {
    final uid = _requireUid();
    return _entriesCollection(uid).doc(id).delete();
  }

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreBodyWeightRepository: no signed-in user.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _entriesCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('bodyWeightEntries');

  BodyWeightEntry _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final loggedAt = data['loggedAt'];
    return BodyWeightEntry(
      id: doc.id,
      weightKg: (data['weightKg'] as num?)?.toDouble() ?? 0,
      loggedAt: loggedAt is Timestamp ? loggedAt.toDate() : DateTime.now(),
    );
  }
}
