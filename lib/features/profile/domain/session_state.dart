import '../../auth/domain/auth_state.dart';
import '../../auth/domain/auth_user.dart';
import 'user_profile.dart';

/// What the **app** should show, given both halves of the answer: what
/// authentication says (`AuthState`) and what this application additionally
/// requires of a user before they can use it (a completed [UserProfile]).
///
/// ## Why this is separate from [AuthState]
///
/// "Signed in" and "ready to use the product" are different questions, and
/// they belong to different owners:
///
/// - **Authentication** owns identity and credentials. Its vocabulary is
///   fixed by the auth provider and is the same in every app: unknown,
///   signed out, signed in, needs to verify an address.
/// - **The application** owns everything else about the person — here, that
///   they must have a name and date of birth before the shell opens. Another
///   app would require a workspace, an accepted ToS, a completed KYC step, or
///   nothing at all.
///
/// Folding the second into the first is the mistake this file exists to
/// avoid. It looks harmless — one extra state on the auth enum — but it
/// inverts the dependency: the auth module ends up importing the app's user
/// record, and stops being liftable into the next project. Composing instead
/// of extending keeps `features/auth/` free of every ZIVO concept while this
/// file, which is ZIVO's, holds the app-specific rule in one readable place.
///
/// The mapping is total and pure, so the whole policy is unit-testable with
/// no widgets, no Firebase, and no async.
sealed class SessionState {
  const SessionState();
}

/// Still resolving — either the persisted auth session or the profile behind
/// it. Show a splash; never a sign-in screen and never a half-built shell.
class SessionResolving extends SessionState {
  const SessionResolving();
}

/// Nobody is signed in. Show the authentication screen.
class SessionSignedOut extends SessionState {
  const SessionSignedOut();
}

/// Signed in, but the email address still has to be proven. Show the OTP
/// screen for [email].
class SessionNeedsEmailVerification extends SessionState {
  const SessionNeedsEmailVerification(this.email);

  final String email;
}

/// Authenticated, but this app doesn't know who they are yet. Show profile
/// completion.
class SessionNeedsProfile extends SessionState {
  const SessionNeedsProfile(this.user, {this.suggestedName});

  final AuthUser user;

  /// Prefill hint for the name field: a partially-saved profile's name, or
  /// failing that the provider-supplied display name. Null when nothing is
  /// known. See [AuthUser.displayName] on why the provider value is only ever
  /// a seed.
  final String? suggestedName;
}

/// Fully resolved: a verified identity **and** a complete profile. Open the
/// app. Both are non-null here by construction, so the shell never has to
/// re-check either.
class SessionActive extends SessionState {
  const SessionActive({required this.user, required this.profile});

  final AuthUser user;
  final UserProfile profile;
}

/// Composes [authState] and the user's [profile] into the one state the app's
/// root gate renders.
///
/// [profileLoaded] is false while the profile stream has not emitted yet.
/// That case must resolve to [SessionResolving] rather than
/// [SessionNeedsProfile]: "we haven't looked yet" and "we looked and there is
/// none" produce very different screens, and confusing them flashes the
/// onboarding form at users who completed it long ago.
SessionState resolveSessionState({
  required AuthState authState,
  required UserProfile? profile,
  required bool profileLoaded,
}) {
  switch (authState) {
    case AuthUnknown():
      return const SessionResolving();
    case Unauthenticated():
      return const SessionSignedOut();
    case AwaitingEmailVerification(:final email):
      return SessionNeedsEmailVerification(email);
    case Authenticated(:final user):
      if (!profileLoaded) return const SessionResolving();
      if (isProfileComplete(profile)) {
        return SessionActive(user: user, profile: profile!);
      }
      return SessionNeedsProfile(
        user,
        suggestedName: profile?.name ?? user.displayName,
      );
  }
}
