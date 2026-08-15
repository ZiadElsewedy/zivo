/// A signed-in user, expressed purely in domain terms.
///
/// This is the app's canonical identity. In particular [uid] is the stable
/// Firebase Auth user id that later becomes the Firestore ownership key
/// (`users/{uid}`). Nothing above the data layer should ever see a Firebase
/// SDK `User` — only this.
class AuthUser {
  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.isEmailVerified = false,
    this.providerIds = const <String>[],
  });

  /// Canonical, stable identity for this user. Never empty for a real session.
  final String uid;

  /// Primary email, when known. Null for providers that withhold it (e.g. a
  /// user who hid their email through Sign in with Apple).
  final String? email;

  /// Human-facing name, when known.
  final String? displayName;

  /// Whether the email has been verified (email/password users may be false).
  final bool isEmailVerified;

  /// The sign-in providers backing this account, e.g. `password`,
  /// `google.com`, `apple.com`. Useful for display and diagnostics only.
  final List<String> providerIds;

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.uid == uid &&
      other.email == email &&
      other.displayName == displayName &&
      other.isEmailVerified == isEmailVerified;

  @override
  int get hashCode => Object.hash(uid, email, displayName, isEmailVerified);

  @override
  String toString() => 'AuthUser(uid: $uid, email: $email)';
}
