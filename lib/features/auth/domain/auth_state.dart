import 'auth_user.dart';

/// What the authentication backend currently says about this device.
///
/// Deliberately a small closed hierarchy so callers can switch exhaustively,
/// and deliberately **free of any application concept** — no profile, no
/// onboarding, no feature flags. This file is part of the portable auth
/// module: it answers "is someone signed in, and is their identity usable
/// yet?", and nothing else. The app's richer notion of "is this session ready
/// to use the product?" is composed on top, in `features/profile/domain/
/// session_state.dart`, which is where anything app-specific belongs.
///
/// That separation is load-bearing. When `ProfileCompletionRequired` lived
/// here, this file imported `UserProfile` — so the auth module depended on the
/// app's own user record, and could not be lifted into another project without
/// dragging ZIVO's date-of-birth and bio fields with it.
sealed class AuthState {
  const AuthState();
}

/// Still resolving whether a persisted session exists. Show a splash.
///
/// Distinct from [Unauthenticated] on purpose: on launch the SDK needs a
/// moment to restore a persisted session, and rendering the sign-in screen
/// during that moment would flash it at users who are, in fact, signed in.
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

/// A user is signed in and their identity is usable.
class Authenticated extends AuthState {
  const Authenticated(this.user);

  final AuthUser user;
}

/// No user is signed in. Show the auth screen.
class Unauthenticated extends AuthState {
  const Unauthenticated();
}

/// An account exists but its **email/password** identity has not been verified
/// with a one-time code yet. The account is real (so the session persists
/// across restarts), but the app holds it at the OTP screen until the code is
/// confirmed server-side.
///
/// Only pure `password` accounts reach this state — Google and Apple arrive
/// already verified, so they bypass it entirely (see [resolveAuthState]).
class AwaitingEmailVerification extends AuthState {
  const AwaitingEmailVerification(this.email);

  /// The address the verification code was sent to. Never null here (the
  /// state is only produced for accounts that have an email).
  final String email;
}

/// Maps a signed-in [user] (or null) onto the gate's [AuthState].
///
/// The **single** place the "does this account still need email-OTP
/// verification?" policy lives, so the data layer's stream and the gate's
/// synchronous seed can never disagree. The rule: an account backed **only**
/// by the `password` provider, with a known email Firebase has not marked
/// verified, must verify. Social accounts never match.
///
/// This is the client half of a policy with two halves. The server half is
/// `emailTrusted()` in `firestore.rules`, which refuses *writes* from an
/// unverified address. Neither is redundant: this one produces the right
/// screen, that one makes it a boundary rather than a suggestion. If you
/// change the rule here, change it there.
AuthState resolveAuthState(AuthUser? user) {
  if (user == null) return const Unauthenticated();
  final providers = user.providerIds.toSet();
  final passwordOnly =
      providers.isEmpty || providers.every((p) => p == 'password');
  if (passwordOnly && user.email != null && !user.isEmailVerified) {
    return AwaitingEmailVerification(user.email!);
  }
  return Authenticated(user);
}
