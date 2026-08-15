import 'auth_user.dart';

/// The app's authentication state, driven by the auth backend's stream.
///
/// Deliberately a small closed hierarchy so the auth gate can exhaustively
/// switch over it. [AuthUnknown] is the transient state while the persisted
/// session is being restored on launch — the UI shows a splash for it, never
/// the auth screen (which would flash for already-signed-in users).
sealed class AuthState {
  const AuthState();
}

/// Still resolving whether a persisted session exists. Show a splash.
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

/// A user is signed in.
class Authenticated extends AuthState {
  const Authenticated(this.user);

  final AuthUser user;
}

/// No user is signed in. Show the auth screen.
class Unauthenticated extends AuthState {
  const Unauthenticated();
}
