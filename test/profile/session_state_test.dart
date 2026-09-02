import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/auth/domain/user_profile.dart';

void main() {
  group('resolveSessionState', () {
    const user = AuthUser(uid: 'u1', displayName: 'Ziad');
    final completeProfile =
        UserProfile(uid: 'u1', name: 'Ziad', dateOfBirth: DateTime(2000, 1, 1));

    test('passes through Unauthenticated unchanged', () {
      final result = resolveSessionState(
        authState: const Unauthenticated(),
        profile: null,
        profileLoaded: true,
      );
      expect(result, isA<Unauthenticated>());
    });

    test('passes through AwaitingEmailVerification unchanged', () {
      const awaiting = AwaitingEmailVerification('ziad@example.com');
      final result = resolveSessionState(
        authState: awaiting,
        profile: null,
        profileLoaded: true,
      );
      expect(result, same(awaiting));
    });

    test('passes through AuthUnknown unchanged', () {
      final result = resolveSessionState(
        authState: const AuthUnknown(),
        profile: null,
        profileLoaded: true,
      );
      expect(result, isA<AuthUnknown>());
    });

    test('Authenticated + profile not yet loaded → AuthUnknown', () {
      final result = resolveSessionState(
        authState: const Authenticated(user),
        profile: null,
        profileLoaded: false,
      );
      expect(result, isA<AuthUnknown>());
    });

    test('Authenticated + complete profile → Authenticated', () {
      final result = resolveSessionState(
        authState: const Authenticated(user),
        profile: completeProfile,
        profileLoaded: true,
      );
      expect(result, isA<Authenticated>());
      expect((result as Authenticated).user, user);
    });

    test('Authenticated + null profile → ProfileCompletionRequired with '
        "suggestedName from the user's displayName", () {
      final result = resolveSessionState(
        authState: const Authenticated(user),
        profile: null,
        profileLoaded: true,
      );
      expect(result, isA<ProfileCompletionRequired>());
      final required = result as ProfileCompletionRequired;
      expect(required.user, user);
      expect(required.suggestedName, 'Ziad');
    });

    test('Authenticated + incomplete profile → ProfileCompletionRequired '
        "with suggestedName from the profile's name", () {
      final incomplete =
          UserProfile(uid: 'u1', name: '', dateOfBirth: DateTime(2000, 1, 1));
      final result = resolveSessionState(
        authState: const Authenticated(user),
        profile: incomplete,
        profileLoaded: true,
      );
      expect(result, isA<ProfileCompletionRequired>());
      expect((result as ProfileCompletionRequired).suggestedName, '');
    });
  });
}
