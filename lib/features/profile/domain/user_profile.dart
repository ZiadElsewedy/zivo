/// A completed user profile, keyed by the auth [uid].
///
/// Deliberately non-nullable fields: an "incomplete" or "missing" profile is
/// modelled as a null `UserProfile?` at call sites (see [isProfileComplete]),
/// not as a profile with empty fields.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.name,
    required this.dateOfBirth,
    this.photoUrl,
    this.photoPath,
    this.bio,
  });

  /// Matches the owning [AuthUser.uid] (the Firestore `users/{uid}` doc id).
  final String uid;
  final String name;
  final DateTime dateOfBirth;

  /// The HTTPS download URL of the avatar stored in Firebase Storage
  /// (`avatars/{uid}`). This is the current avatar mechanism: unlike
  /// [photoPath], the bytes live in a place every device can read the moment
  /// the profile document syncs — no Google Drive connection required. See
  /// [docs/DECISIONS/ADR-014](../../../../docs/DECISIONS/ADR-014-avatar-firebase-storage.md).
  /// Preferred over [photoPath] wherever both are present.
  final String? photoUrl;

  /// **Legacy** avatar reference: a *media-store reference* (a relative path
  /// owned by the `core/media` [MediaStore]) from before avatars moved to
  /// Firebase Storage. Still rendered on the device that holds the local/Drive
  /// copy so existing users don't lose their photo, but new uploads set
  /// [photoUrl] and clear this. A legacy absolute path still resolves.
  final String? photoPath;

  /// A short "About me" line the person writes about themselves. Null/empty
  /// means they haven't set one yet — the profile shows a prompt instead.
  final String? bio;

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.uid == uid &&
      other.name == name &&
      other.dateOfBirth == dateOfBirth &&
      other.photoUrl == photoUrl &&
      other.photoPath == photoPath &&
      other.bio == bio;

  @override
  int get hashCode =>
      Object.hash(uid, name, dateOfBirth, photoUrl, photoPath, bio);

  @override
  String toString() => 'UserProfile(uid: $uid, name: $name)';
}

/// Whether [profile] is complete enough to skip the profile-completion step.
///
/// A null profile (no document yet) is always incomplete. A non-null profile
/// is complete as long as its name isn't blank — [dateOfBirth] is guaranteed
/// non-null by [UserProfile]'s constructor.
bool isProfileComplete(UserProfile? profile) =>
    profile != null && profile.name.trim().isNotEmpty;
