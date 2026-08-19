import 'user_profile.dart';

/// The seam between the app and wherever user profiles are persisted.
///
/// Presentation depends only on this interface — never on Firestore — so the
/// backend is a data-layer detail (mirrors [AuthRepository]). The concrete
/// implementation is `FirestoreProfileRepository`; tests use
/// `FakeProfileRepository`.
abstract interface class ProfileRepository {
  /// Emits the current profile for [uid], or null when none exists yet, and
  /// every subsequent change. Reactive so profile edits elsewhere update the
  /// gate immediately.
  Stream<UserProfile?> watchProfile(String uid);

  /// One-shot read of the current profile for [uid], or null if none exists.
  Future<UserProfile?> fetchProfile(String uid);

  /// Creates or updates the profile for [uid]. Callers always pass the full,
  /// current [photoPath] (including unchanged) — this is a plain overwrite,
  /// not a partial patch, so omitting it clears any previously saved photo.
  Future<void> saveProfile({
    required String uid,
    required String name,
    required DateTime dateOfBirth,
    String? photoPath,
  });
}
