import 'package:cloud_firestore/cloud_firestore.dart';

import '../../firebase/uid_source.dart';
import '../domain/media_kind.dart';
import '../domain/media_object.dart';
import '../domain/media_registry.dart';
import 'in_memory_media_registry.dart' show needsBackup;

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

  /// Writes the record under **the signed-in account**, never under whatever
  /// owner the caller happened to pass. Routing writes by `object.ownerUid`
  /// while every read routes by the current uid meant a capture taken during a
  /// momentary auth gap wrote to an unroutable path, was rejected by the rules,
  /// and left a photo with no registry record at all — metadata-less bytes
  /// here, and an unresolvable image on every other device.
  @override
  Future<void> put(MediaObject object) {
    final uid = _requireUid();
    if (object.ownerUid != uid) {
      throw StateError(
        'FirestoreMediaRegistry: refusing to write media ${object.id} owned by '
        '"${object.ownerUid}" as "$uid".',
      );
    }
    return _media(uid).doc(object.id).set({
      'kind': object.kind.name,
      'relativePath': object.relativePath,
      'mimeType': object.mimeType,
      'byteSize': object.byteSize,
      'contentHash': object.contentHash,
      'capturedAt': Timestamp.fromDate(object.capturedAt),
      'source': object.source.name,
      'width': object.width,
      'height': object.height,
      'gallery': object.gallery.name,
      // Firestore keys kept as 'drive'/'driveFileId' for back-compat with
      // already-stored docs; the domain fields are provider-neutral.
      'drive': object.remoteBackup.name,
      'driveFileId': object.remoteId,
      // Which Drive account `driveFileId` lives in. Added in schema 2; absent
      // on older docs, where it reads as "unknown" rather than as this one.
      'driveAccountKey': object.remoteAccountKey,
      'schemaVersion': 2,
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
  Future<MediaObject?> getByRelativePath(String relativePath) async {
    final uid = _requireUid();
    final snap = await _media(uid)
        .where('relativePath', isEqualTo: relativePath)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return _fromDoc(uid, doc.id, doc.data());
  }

  @override
  Future<List<MediaObject>> getAll() async {
    final uid = _requireUid();
    final snap = await _media(uid).get();
    return snap.docs
        .map((d) => _fromDoc(uid, d.id, d.data()))
        .toList(growable: false);
  }

  @override
  Future<List<MediaObject>> pendingBackups({String? forAccountKey}) async {
    final uid = _requireUid();
    // Drive not yet done (or done against another account) is the primary work
    // list; the whole set is small (personal media), so a full read + in-memory
    // filter is fine and avoids a composite index — and the account-relative
    // clause could not be expressed as a Firestore query anyway.
    final snap = await _media(uid).get();
    return snap.docs
        .map((d) => _fromDoc(uid, d.id, d.data()))
        .where((m) => needsBackup(m, forAccountKey))
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
      source: CaptureSource.fromName(data['source'] as String?),
      width: (data['width'] as num?)?.toInt(),
      height: (data['height'] as num?)?.toInt(),
      gallery: _stateFrom(data['gallery']),
      remoteBackup: _stateFrom(data['drive']),
      remoteId: data['driveFileId'] as String?,
      remoteAccountKey: data['driveAccountKey'] as String?,
    );
  }

  BackupState _stateFrom(Object? raw) {
    return BackupState.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => BackupState.pending,
    );
  }
}
