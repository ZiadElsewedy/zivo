import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_scoped_mirror.dart';
import '../../../core/firebase/uid_source.dart';
import '../domain/body_weight_entry.dart';
import '../domain/body_weight_repository.dart';

/// The real [BodyWeightRepository], backed by Firestore's
/// `users/{uid}/bodyWeightEntries` subcollection. This is the *only* place
/// Firestore SDK types are allowed — everything above consumes the domain
/// [BodyWeightEntry] model.
///
/// The repository is constructed once at app root, before sign-in, so it has
/// no `uid` of its own — the uid-scoping, the cached `current`, the late-
/// subscriber replay and the always-on listener all live in
/// [UidScopedMirror]; this class supplies only the query and the mapper.
/// (This repo is one of the reasons the listener is always on: saving a
/// weigh-in while no screen was subscribed used to leave the cache stale.)
class FirestoreBodyWeightRepository implements BodyWeightRepository {
  FirestoreBodyWeightRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _mirror = UidScopedMirror<List<BodyWeightEntry>>(
      uidSource: uidSource,
      signedOutValue: const [],
      source: (uid) => _entriesCollection(uid)
          .orderBy('loggedAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(_fromDoc).toList(growable: false)),
    )..start();
  }

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  late final UidScopedMirror<List<BodyWeightEntry>> _mirror;

  @override
  List<BodyWeightEntry> get current => List.unmodifiable(_mirror.current);

  @override
  Stream<List<BodyWeightEntry>> watchAll() => _mirror.watch();

  /// Tears down the always-on listener — not called in production (the
  /// repository lives for the app's process lifetime), only for explicit
  /// teardown in tests.
  void dispose() => _mirror.dispose();

  @override
  Future<void> save(BodyWeightEntry entry) {
    final uid = uidSource.requireUid(this);
    return _entriesCollection(uid).doc(entry.id).set({
      'weightKg': entry.weightKg,
      'loggedAt': Timestamp.fromDate(entry.loggedAt),
      'schemaVersion': 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> remove(String id) {
    final uid = uidSource.requireUid(this);
    return _entriesCollection(uid).doc(id).delete();
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
