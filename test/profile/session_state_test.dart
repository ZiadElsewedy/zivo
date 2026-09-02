import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/profile/domain/session_state.dart';
import 'package:zivo/features/profile/domain/user_profile.dart';

/// The app's root routing policy, tested as the pure function it is — no
/// widgets, no Firebase, no async. Every screen the user can land on before
/// the shell opens is decided here, so this is where those decisions are
/// pinned.
void main() {
  const user = AuthUser(uid: 'u1', displayName: 'Ziad');
  final completeProfile = UserProfile(
    uid: 'u1',
    name: 'Ziad',
    dateOfBirth: DateTime(2000, 1, 1),
  );

  SessionState resolve(
    AuthState authState, {
    UserProfile? profile,
    bool profileLoaded = true,
  }) => resolveSessionState(
    authState: authState,
    profile: profile,
    profileLoaded: profileLoaded,
  );

  group('states that do not depend on the profile', () {
    test('AuthUnknown → SessionResolving (splash, never the sign-in screen)',
        () {
      expect(resolve(const AuthUnknown()), isA<SessionResolving>());
    });

    test('Unauthenticated → SessionSignedOut', () {
      expect(resolve(const Unauthenticated()), isA<SessionSignedOut>());
    });

    test('AwaitingEmailVerification → SessionNeedsEmailVerification, '
        'carrying the address', () {
      final result = resolve(
        const AwaitingEmailVerification('ziad@example.com'),
      );
      expect(result, isA<SessionNeedsEmailVerification>());
      expect(
        (result as SessionNeedsEmailVerification).email,
        'ziad@example.com',
      );
    });

    test('the profile is irrelevant to all three — even a complete one does '
        'not short-circuit verification', () {
      expect(
        resolve(
          const AwaitingEmailVerification('z@example.com'),
          profile: completeProfile,
        ),
        isA<SessionNeedsEmailVerification>(),
      );
    });
  });

  group('authenticated', () {
    test('profile not loaded yet → SessionResolving, NOT SessionNeedsProfile',
        () {
      // "We haven't looked yet" and "we looked and there is none" produce very
      // different screens. Confusing them flashes the onboarding form at users
      // who completed it long ago.
      expect(
        resolve(const Authenticated(user), profileLoaded: false),
        isA<SessionResolving>(),
      );
    });

    test('complete profile → SessionActive carrying both halves', () {
      final result = resolve(
        const Authenticated(user),
        profile: completeProfile,
      );
      expect(result, isA<SessionActive>());
      final active = result as SessionActive;
      expect(active.user, user);
      // Non-null by construction, so the shell never re-checks it.
      expect(active.profile, completeProfile);
    });

    test('no profile → SessionNeedsProfile, seeded from the provider name', () {
      // The provider's displayName is a HINT that seeds the profile the user
      // is about to create — never app state in its own right.
      final result = resolve(const Authenticated(user), profile: null);
      expect(result, isA<SessionNeedsProfile>());
      final needs = result as SessionNeedsProfile;
      expect(needs.user, user);
      expect(needs.suggestedName, 'Ziad');
    });

    test('incomplete profile → SessionNeedsProfile, seeded from the profile '
        'rather than the provider', () {
      // A half-saved profile is a better prefill than the provider's guess,
      // because the user typed it.
      final incomplete = UserProfile(
        uid: 'u1',
        name: '',
        dateOfBirth: DateTime(2000, 1, 1),
      );
      final result = resolve(
        const Authenticated(user),
        profile: incomplete,
      );
      expect(result, isA<SessionNeedsProfile>());
      expect((result as SessionNeedsProfile).suggestedName, '');
    });

    test('a user with no provider name and no profile still resolves', () {
      const anonymous = AuthUser(uid: 'u2');
      final result = resolve(const Authenticated(anonymous), profile: null);
      expect(result, isA<SessionNeedsProfile>());
      expect((result as SessionNeedsProfile).suggestedName, isNull);
    });
  });
}
