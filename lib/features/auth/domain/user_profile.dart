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
    this.photoPath,
    this.bio,
  });

  /// Matches the owning [AuthUser.uid] (the Firestore `users/{uid}` doc id).
  final String uid;
  final String name;
  final DateTime dateOfBirth;

  /// A *local device file path* for the profile photo, mirroring
  /// [Moment.imagePath]'s convention — it only resolves on the device that
  /// set it. Cross-device photo sync (Firebase Storage) is a later
  /// milestone; this is deliberately just a local file, copied into the
  /// app's own `avatars/` documents folder so it survives independently of
  /// wherever the picker's source file lived.
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
      other.photoPath == photoPath &&
      other.bio == bio;

  @override
  int get hashCode => Object.hash(uid, name, dateOfBirth, photoPath, bio);

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
