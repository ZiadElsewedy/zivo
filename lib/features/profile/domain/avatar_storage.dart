import 'dart:io';

/// The seam between the app and wherever the **profile avatar bytes** live.
///
/// This is deliberately *not* the `core/media` pipeline. That pipeline is
/// local-first with optional Google Drive backup, which is right for bulk
/// moments (they stay in the user's own Drive, off ZIVO's bill) but wrong for
/// the avatar: the avatar is identity — a single tiny image that must appear
/// on every device the moment the profile syncs, without the user first
/// connecting Drive on that device. So it goes to Firebase Storage under
/// `avatars/{uid}`, and only its download URL rides in the `users/{uid}`
/// document. See [docs/DECISIONS/ADR-014](../../../../docs/DECISIONS/ADR-014-avatar-firebase-storage.md).
///
/// Presentation depends only on this interface — never on `firebase_storage` —
/// so tests run without Firebase (they use `FakeAvatarStorage`). The concrete
/// implementation is `FirebaseAvatarStorage`.
abstract interface class AvatarStorage {
  /// Uploads [file] as the avatar for [uid] (overwriting any previous one in
  /// place, so a user's avatar is exactly one object) and returns a stable
  /// HTTPS download URL to persist on the profile.
  ///
  /// [mimeType] is stamped as the object's content type so the URL serves the
  /// right bytes to `Image.network`.
  Future<String> upload({
    required String uid,
    required File file,
    String mimeType = 'image/jpeg',
  });

  /// Best-effort removal of the stored avatar for [uid]. A missing object is
  /// not an error (the user may never have had one, or it was already cleared).
  Future<void> remove(String uid);
}
