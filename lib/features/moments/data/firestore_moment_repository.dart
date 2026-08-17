import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/firebase/uid_source.dart';
import '../domain/moment.dart';
import '../domain/moment_repository.dart';

/// The real [MomentRepository], backed by Firestore's `users/{uid}/moments`
/// subcollection. This is the *only* place Firestore SDK types are allowed —
/// everything above consumes the domain [Moment] model.
///
/// The repository is constructed once at app root, before sign-in, so it has
/// no `uid` of its own — it resolves the signed-in user from an injected
/// [UidSource] instead, which re-scopes `watchAll()` whenever the uid changes
/// (including to/from signed-out).
///
/// Like Notes' `updatedAt`, `takenAt` here is a domain field owned by the
/// entity (the moment's own capture time), not pure server metadata — it is
/// written and read back verbatim rather than stamped with
/// `serverTimestamp()`.
///
/// [Moment.imagePath] is a *local device file path* from image_picker, not
/// portable image bytes or a URL. It is persisted as-is (a string), but it
/// will only resolve on the device that captured it — real cross-device
/// photo persistence (uploading to Firebase Storage and storing a
/// `storageRef`) is a later milestone. No file bytes are read or uploaded
/// here.
class FirestoreMomentRepository implements MomentRepository {
  FirestoreMomentRepository({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  List<Moment> _current = const [];
  StreamController<List<Moment>>? _controller;
  StreamSubscription<String?>? _uidSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _querySub;

  @override
  List<Moment> get current => List.unmodifiable(_current);

  @override
  Stream<List<Moment>> watchAll() {
    return (_controller ??= StreamController<List<Moment>>.broadcast(
      onListen: _start,
      onCancel: _stop,
    )).stream;
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
    _querySub = _momentsCollection(uid)
        .orderBy('takenAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          _emit(snapshot.docs.map(_fromDoc).toList(growable: false));
        }, onError: (e, s) => _controller?.addError(e, s));
  }

  void _emit(List<Moment> moments) {
    _current = moments;
    _controller?.add(current);
  }

  @override
  Future<void> add(Moment moment) {
    final uid = _requireUid();
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
    final uid = _requireUid();
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
    final uid = _requireUid();
    return _momentsCollection(uid).doc(id).delete();
  }

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreMomentRepository: no signed-in user.');
    }
    return uid;
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
