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
  });

  /// Matches the owning [AuthUser.uid] (the Firestore `users/{uid}` doc id).
  final String uid;
  final String name;
  final DateTime dateOfBirth;

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.uid == uid &&
      other.name == name &&
      other.dateOfBirth == dateOfBirth;

  @override
  int get hashCode => Object.hash(uid, name, dateOfBirth);

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
