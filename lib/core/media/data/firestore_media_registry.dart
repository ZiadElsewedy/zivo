import 'package:cloud_firestore/cloud_firestore.dart';

import '../../firebase/uid_source.dart';
import '../domain/media_kind.dart';
import '../domain/media_object.dart';
import '../domain/media_registry.dart';

/// The real [MediaRegistry], backed by Firestore's `users/{uid}/media`
/// subcollection. Stores only metadata — the file bytes live in the local
/// [MediaStore] (and, later, in backup targets). This is the only place
/// Firestore SDK types touch media records.
class FirestoreMediaRegistry implements MediaRegistry {
  FirestoreMediaRegistry({
    FirebaseFirestore? firestore,
    required this.uidSource,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final UidSource uidSource;

  CollectionReference<Map<String, dynamic>> _media(String uid) =>
      _firestore.collection('users').doc(uid).collection('media');

  String _requireUid() {
    final uid = uidSource.currentUid();
    if (uid == null) {
      throw StateError('FirestoreMediaRegistry: no signed-in user.');
    }
    return uid;
  }

  @override
  Future<void> put(MediaObject object) {
    return _media(object.ownerUid).doc(object.id).set({
      'kind': object.kind.name,
      'relativePath': object.relativePath,
      'mimeType': object.mimeType,
      'byteSize': object.byteSize,
      'contentHash': object.contentHash,
      'capturedAt': Timestamp.fromDate(object.capturedAt),
      'gallery': object.gallery.name,
      'drive': object.drive.name,
      'driveFileId': object.driveFileId,
      'schemaVersion': 1,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<MediaObject?> get(String id) async {
    final uid = _requireUid();
    final snap = await _media(uid).doc(id).get();
    if (!snap.exists) return null;
    return _fromDoc(uid, snap.id, snap.data()!);
  }

  @override
  Future<List<MediaObject>> pendingBackups() async {
    final uid = _requireUid();
    // Drive not yet done is the primary work list; the whole set is small
    // (personal media), so a full read + in-memory filter is fine and avoids a
    // composite index.
    final snap = await _media(uid).get();
    return snap.docs
        .map((d) => _fromDoc(uid, d.id, d.data()))
        .where((m) => m.drive != BackupState.done || m.gallery == BackupState.failed)
        .toList(growable: false);
  }

  @override
  Future<void> remove(String id) async {
    final uid = _requireUid();
    await _media(uid).doc(id).delete();
  }

  MediaObject _fromDoc(String uid, String id, Map<String, dynamic> data) {
    final capturedAt = data['capturedAt'];
    return MediaObject(
      id: id,
      ownerUid: uid,
      kind: MediaKind.fromName(data['kind'] as String? ?? 'moment'),
      relativePath: data['relativePath'] as String? ?? '',
      mimeType: data['mimeType'] as String? ?? 'image/jpeg',
      byteSize: (data['byteSize'] as num?)?.toInt() ?? 0,
      contentHash: data['contentHash'] as String? ?? '',
      capturedAt: capturedAt is Timestamp ? capturedAt.toDate() : DateTime.now(),
      gallery: _stateFrom(data['gallery']),
      drive: _stateFrom(data['drive']),
      driveFileId: data['driveFileId'] as String?,
    );
  }

  BackupState _stateFrom(Object? raw) {
    return BackupState.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => BackupState.pending,
    );
  }
}
