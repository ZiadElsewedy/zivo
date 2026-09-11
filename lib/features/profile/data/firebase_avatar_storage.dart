import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import '../domain/avatar_storage.dart';

/// The real [AvatarStorage], backed by Firebase Storage. This is the *only*
/// place `firebase_storage` types are allowed — everything above consumes the
/// [AvatarStorage] interface.
///
/// Every account's avatar is a single object at `avatars/{uid}` (no extension,
/// no timestamp): a new photo `putFile`s over the old one, so a user never
/// accumulates orphaned avatars and the storage rule can pin the path exactly.
/// The download URL changes on each upload (Firebase appends a fresh token),
/// which also busts any cached `Image.network` copy of the previous avatar.
class FirebaseAvatarStorage implements AvatarStorage {
  FirebaseAvatarStorage({FirebaseStorage? storage}) : _injected = storage;

  final FirebaseStorage? _injected;

  /// Resolved lazily, not in the constructor: `app.dart` builds this eagerly
  /// even in tests, and touching `FirebaseStorage.instance` before Firebase is
  /// initialized would throw. Only a real [upload]/[remove] reaches it.
  FirebaseStorage get _storage => _injected ?? FirebaseStorage.instance;

  Reference _ref(String uid) => _storage.ref().child('avatars').child(uid);

  @override
  Future<String> upload({
    required String uid,
    required File file,
    String mimeType = 'image/jpeg',
  }) async {
    final ref = _ref(uid);
    await ref.putFile(file, SettableMetadata(contentType: mimeType));
    return ref.getDownloadURL();
  }

  @override
  Future<void> remove(String uid) async {
    try {
      await _ref(uid).delete();
    } on FirebaseException catch (e) {
      // A missing object is the normal "nothing to remove" case, not a failure.
      if (e.code == 'object-not-found') return;
      rethrow;
    }
  }
}
