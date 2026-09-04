import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_scoped_mirror.dart';
import '../../../core/firebase/uid_source.dart';
import '../domain/moment.dart';
import '../domain/moment_repository.dart';

/// The real [MomentRepository], backed by Firestore's `users/{uid}/moments`
/// subcollection. This is the *only* place Firestore SDK types are allowed —
/// everything above consumes the domain [Moment] model.
///
/// The repository is constructed once at app root, before sign-in, so it has
/// no `uid` of its own — the uid-scoping, the cached `current`, the late-
/// subscriber replay and the always-on listener all live in
/// [UidScopedMirror]; this class supplies only the query and the mapper.
///
/// Like Notes' `updatedAt`, `takenAt` here is a domain field owned by the
/// entity (the moment's own capture time), not pure server metadata — it is
/// written and read back verbatim rather than stamped with
/// `serverTimestamp()`.
///
/// [Moment.imagePath] is a *media-store reference* — a relative path owned by
/// the `core/media` [MediaStore], not portable image bytes or a Firebase
/// Storage URL. The capture flow imports the picked file into durable local
/// storage via `MediaService`; this repository just persists the returned
/// reference string. Resolving it back to a file (and any cloud backup) is the
/// media module's job, not this one's.
class FirestoreMomentRepository implements MomentRepository {
  FirestoreMomentRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _mirror = UidScopedMirror<List<Moment>>(
      uidSource: uidSource,
      signedOutValue: const [],
      source: (uid) => _momentsCollection(uid)
          .orderBy('takenAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map(_fromDoc).toList(growable: false)),
    )..start();
  }

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  late final UidScopedMirror<List<Moment>> _mirror;

  @override
  List<Moment> get current => List.unmodifiable(_mirror.current);

  @override
  Stream<List<Moment>> watchAll() => _mirror.watch();

  /// Tears down the always-on listener — not called in production (the
  /// repository lives for the app's process lifetime), only for explicit
  /// teardown in tests.
  void dispose() => _mirror.dispose();

  @override
  Future<void> add(Moment moment) {
    final uid = uidSource.requireUid(this);
    return _momentsCollection(uid).doc(moment.id).set({
      'caption': moment.caption,
      'takenAt': Timestamp.fromDate(moment.takenAt),
      'imagePath': moment.imagePath,
      'location': moment.location,
      'schemaVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> update(Moment moment) {
    final uid = uidSource.requireUid(this);
    return _momentsCollection(uid).doc(moment.id).update({
      'caption': moment.caption,
      'takenAt': Timestamp.fromDate(moment.takenAt),
      'imagePath': moment.imagePath,
      'location': moment.location,
      'schemaVersion': 1,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> remove(String id) {
    final uid = uidSource.requireUid(this);
    return _momentsCollection(uid).doc(id).delete();
  }

  CollectionReference<Map<String, dynamic>> _momentsCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('moments');

  Moment _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final takenAt = data['takenAt'];
    final imagePath = data['imagePath'];
    final location = data['location'];
    return Moment(
      id: doc.id,
      caption: data['caption'] as String? ?? '',
      takenAt: takenAt is Timestamp ? takenAt.toDate() : DateTime.now(),
      imagePath: imagePath is String ? imagePath : null,
      location: location is String ? location : null,
    );
  }
}
