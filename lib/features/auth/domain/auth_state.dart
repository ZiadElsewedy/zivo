import 'auth_user.dart';
import 'user_profile.dart';

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

/// A user account exists but its **email/password** identity has not yet been
/// verified with a one-time code. The account is created (so the session
/// persists across restarts), but the app is gated behind the OTP screen until
/// the code is confirmed server-side.
///
/// Only pure `password` accounts ever reach this state — Google and Apple
/// arrive already `emailVerified`, so they bypass it entirely (see
/// [resolveAuthState]).
class AwaitingEmailVerification extends AuthState {
  const AwaitingEmailVerification(this.email);

  /// The address the verification code was sent to. Never null here (the state
  /// is only produced for accounts that have an email).
  final String email;
}

/// A user is authenticated (email verified / social) but has no complete
/// [UserProfile] yet. Show the profile-completion screen instead of the home
/// shell until [saveProfile] gives them one.
class ProfileCompletionRequired extends AuthState {
  const ProfileCompletionRequired(this.user, {this.suggestedName});

  final AuthUser user;

  /// Prefill hint for the name field, e.g. a provider's display name or a
  /// partially-saved profile's name. Null when nothing is known yet.
  final String? suggestedName;
}

/// Maps a signed-in [user] (or null) onto the gate's [AuthState].
///
/// This is the *single* place the "does this account still need email-OTP
/// verification?" policy lives, so the data-layer stream and the gate's
/// synchronous seed can never diverge. The rule: an account backed **only** by
/// the `password` provider, with a known email that Firebase has not marked
/// verified, must verify via OTP. Social accounts (which include a
/// `google.com` / `apple.com` provider and arrive verified) never match.
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

/// Layers profile-completeness onto an already-resolved [authState].
///
/// Only [Authenticated] is affected — every other state (splash, signed out,
/// awaiting OTP) passes through unchanged, since a profile is meaningless
/// without a signed-in identity. While [profileLoaded] is false the profile
/// stream hasn't emitted yet, so this returns [AuthUnknown] (splash) rather
/// than risk a flash of the completion screen for a user who actually has a
/// complete profile.
AuthState resolveSessionState({
  required AuthState authState,
  required UserProfile? profile,
  required bool profileLoaded,
}) {
  if (authState is! Authenticated) return authState;
  if (!profileLoaded) return const AuthUnknown();
  if (isProfileComplete(profile)) return authState;
  return ProfileCompletionRequired(
    authState.user,
    suggestedName: profile?.name ?? authState.user.displayName,
  );
}
