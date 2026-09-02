/// The kinds of authentication failure the UI may need to distinguish.
///
/// This is a domain concept: the data layer maps backend error codes onto it
/// (see [mapAuthErrorCode]) so nothing above the data layer ever inspects a
/// `FirebaseAuthException`.
enum AuthFailureKind {
  invalidEmail,
  wrongPassword,
  userNotFound,
  emailAlreadyInUse,
  weakPassword,
  userDisabled,
  accountExistsWithDifferentCredential,
  networkError,
  tooManyRequests,

  /// The request reached the backend but the backend itself failed (e.g. the
  /// email-delivery provider errored). Distinct from [networkError] so we
  /// never blame the user's connection for a server-side failure.
  emailDeliveryFailed,

  /// The provider isn't enabled in the backend, or is misconfigured. Surfaced
  /// distinctly because during setup this is the most likely failure.
  providerConfig,

  /// The server refused an irreversible operation because the session's
  /// credential proof is too old.
  ///
  /// Distinct from [wrongPassword] on purpose: nothing the user typed was
  /// wrong, so the copy must say "confirm again", not "that was incorrect".
  /// Reaching this from the app means the client-side reauth prompt was
  /// skipped or its `auth_time` went stale between the prompt and the call —
  /// which is exactly the case the server-side check exists to catch.
  reauthRequired,

  unknown,
}

/// A user-presentable authentication failure. Carries a stable [kind] for
/// programmatic handling and a already-humanised [message] for display.
class AuthFailure {
  const AuthFailure(this.kind, this.message);

  final AuthFailureKind kind;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is AuthFailure && other.kind == kind && other.message == message;

  @override
  int get hashCode => Object.hash(kind, message);

  @override
  String toString() => 'AuthFailure(${kind.name}: $message)';
}

/// Maps a backend auth error [code] (e.g. Firebase's `wrong-password`) to a
/// domain [AuthFailure]. Pure and Firebase-free so it is unit-testable and so
/// no SDK types cross the domain boundary.
///
/// Note: modern Firebase collapses `wrong-password`/`user-not-found` into
/// `invalid-credential` (email-enumeration protection); all three land on a
/// single "email or password is incorrect" message.
AuthFailure mapAuthErrorCode(String code) {
  switch (code) {
    case 'invalid-email':
      return const AuthFailure(
        AuthFailureKind.invalidEmail,
        "That email address doesn't look right.",
      );
    case 'wrong-password':
    case 'user-not-found':
    case 'invalid-credential':
      return const AuthFailure(
        AuthFailureKind.wrongPassword,
        'Email or password is incorrect.',
      );
    case 'email-already-in-use':
      return const AuthFailure(
        AuthFailureKind.emailAlreadyInUse,
        'An account already exists for that email. Try signing in.',
      );
    case 'weak-password':
      return const AuthFailure(
        AuthFailureKind.weakPassword,
        'Choose a stronger password (at least 6 characters).',
      );
    case 'user-disabled':
      return const AuthFailure(
        AuthFailureKind.userDisabled,
        'This account has been disabled.',
      );
    case 'account-exists-with-different-credential':
      return const AuthFailure(
        AuthFailureKind.accountExistsWithDifferentCredential,
        'You already have an account with a different sign-in method for that email.',
      );
    case 'network-request-failed':
      return const AuthFailure(
        AuthFailureKind.networkError,
        'Network error. Check your connection and try again.',
      );
    case 'too-many-requests':
      return const AuthFailure(
        AuthFailureKind.tooManyRequests,
        'Too many attempts. Please wait a moment and try again.',
      );
    case 'operation-not-allowed':
    case 'configuration-not-found':
      return const AuthFailure(
        AuthFailureKind.providerConfig,
        'This sign-in method is not available right now.',
      );
    default:
      return const AuthFailure(
        AuthFailureKind.unknown,
        'Something went wrong. Please try again.',
      );
  }
}
