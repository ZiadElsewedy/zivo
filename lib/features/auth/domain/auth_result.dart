import 'auth_failure.dart';
import 'auth_user.dart';

/// The outcome of a sign-in / sign-up attempt.
///
/// [AuthCancelled] is modelled distinctly from [AuthFailed] on purpose: when a
/// user backs out of the Apple or Google sheet that is *not* an error and the
/// UI must show nothing — only [AuthFailed] surfaces a message.
sealed class AuthResult {
  const AuthResult();
}

/// Sign-in succeeded; [user] is now the authenticated identity.
class AuthSuccess extends AuthResult {
  const AuthSuccess(this.user);

  final AuthUser user;
}

/// The user dismissed the provider flow (Apple/Google). Not an error.
class AuthCancelled extends AuthResult {
  const AuthCancelled();
}

/// Sign-in failed with a presentable [failure].
class AuthFailed extends AuthResult {
  const AuthFailed(this.failure);

  final AuthFailure failure;
}
