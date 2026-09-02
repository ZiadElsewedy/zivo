/// A signed-in **identity** — deliberately not "the user".
///
/// This carries what the authentication provider knows and guarantees, and
/// nothing else: who they are ([uid]), how to reach them ([email]), whether
/// that address is proven ([isEmailVerified]), how they signed in
/// ([providerIds]), and when ([createdAt], [lastSignInAt]).
///
/// Who the person *is* to this application — their name, date of birth,
/// preferences, anything the product cares about — lives in `UserProfile`
/// (`features/profile/`), joined to this by [uid] alone. That separation is
/// the module's central design decision; `docs/AUTH.md` gives the full
/// reasoning, but the short version is that the auth record cannot be queried,
/// validated, bounded, extended, or written transactionally with your data, so
/// anything you need to do those things to must not live on it.
///
/// [uid] is the stable Firebase Auth user id and the Firestore ownership key
/// (`users/{uid}`). Nothing above the data layer should ever see a Firebase
/// SDK `User` — only this.
class AuthUser {
  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.isEmailVerified = false,
    this.providerIds = const <String>[],
    this.createdAt,
    this.lastSignInAt,
  });

  /// Canonical, stable identity for this user. Never empty for a real session.
  final String uid;

  /// Primary email, when known. Null for providers that withhold it (e.g. a
  /// user who hid their email through Sign in with Apple).
  final String? email;

  /// The provider's idea of a human-facing name — **a hint, never app state.**
  ///
  /// Google and Apple hand one over at sign-in for free, and it makes a good
  /// prefill for the profile form the user is about to see. That is its entire
  /// job. The app's actual name for a person is `UserProfile.name`, and there
  /// is exactly one consumer of this field — `resolveSessionState`, seeding
  /// `SessionNeedsProfile.suggestedName`.
  ///
  /// Treating it as state instead is the mistake worth naming, because it
  /// looks like a harmless convenience: two fields then hold "the user's
  /// name", they drift the first time someone edits their profile, and every
  /// screen quietly picks a different one. It is also unqueryable,
  /// unvalidatable, and updated outside any transaction with your own data.
  ///
  /// Apple is the reason it is written at all: it discloses the name **only on
  /// the very first authorization** and returns nulls forever after, so the
  /// one chance to capture it is at sign-in.
  final String? displayName;

  /// Whether the email has been verified (email/password users may be false).
  final bool isEmailVerified;

  /// The sign-in providers backing this account, e.g. `password`,
  /// `google.com`, `apple.com`. Useful for display and diagnostics only.
  final List<String> providerIds;

  /// When Firebase Auth created the account (server clock). Mirrored from the
  /// SDK's own trusted metadata — no client write can forge it.
  final DateTime? createdAt;

  /// When the current session last authenticated against Firebase's servers
  /// (server clock). Updates on token refreshes, so it reads as "last contact
  /// with auth", not "last human sign-in" — that richer history lives in
  /// `users/{uid}/authEvents` via [AuthActivityRepository].
  final DateTime? lastSignInAt;

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.uid == uid &&
      other.email == email &&
      other.displayName == displayName &&
      other.isEmailVerified == isEmailVerified &&
      other.createdAt == createdAt &&
      other.lastSignInAt == lastSignInAt;

  @override
  int get hashCode => Object.hash(
    uid,
    email,
    displayName,
    isEmailVerified,
    createdAt,
    lastSignInAt,
  );

  @override
  String toString() => 'AuthUser(uid: $uid, email: $email)';
}
