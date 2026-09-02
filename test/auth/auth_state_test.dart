import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';

/// `resolveAuthState` is the **client half of a security policy**, not a UI
/// helper: it decides who gets held at the verification screen. Its server half
/// is `emailTrusted()` in `firestore.rules`, which refuses writes from an
/// unverified address (covered in `firestore-tests/rules.test.mjs`).
///
/// Both halves have to agree, so this pins the client's side of the contract.
void main() {
  AuthUser user({
    String? email = 'z@example.com',
    bool verified = false,
    List<String> providers = const ['password'],
  }) => AuthUser(
    uid: 'u1',
    email: email,
    isEmailVerified: verified,
    providerIds: providers,
  );

  test('no user → Unauthenticated', () {
    expect(resolveAuthState(null), isA<Unauthenticated>());
  });

  group('password-only accounts must verify', () {
    test('unverified → AwaitingEmailVerification, carrying the address', () {
      final state = resolveAuthState(user());
      expect(state, isA<AwaitingEmailVerification>());
      expect((state as AwaitingEmailVerification).email, 'z@example.com');
    });

    test('verified → Authenticated', () {
      expect(resolveAuthState(user(verified: true)), isA<Authenticated>());
    });

    test('an account with no email cannot be held at a screen asking for one',
        () {
      // Nothing to send a code to, so gating here would strand the account
      // with no way forward. The server rule is written the same way round:
      // it refuses UNVERIFIED addresses, not addressless accounts.
      expect(resolveAuthState(user(email: null)), isA<Authenticated>());
    });

    test('an empty provider list is treated as password-only', () {
      // Defensive: a user whose providerData we could not read must fail
      // CLOSED into "verify first", never open into full access.
      expect(
        resolveAuthState(user(providers: const [])),
        isA<AwaitingEmailVerification>(),
      );
    });
  });

  group('federated accounts bypass verification', () {
    test('Google arrives trusted', () {
      expect(
        resolveAuthState(user(providers: const ['google.com'])),
        isA<Authenticated>(),
      );
    });

    test('Apple arrives trusted', () {
      expect(
        resolveAuthState(user(providers: const ['apple.com'])),
        isA<Authenticated>(),
      );
    });

    test('a password account LINKED to a provider is not held', () {
      // The provider already proved the address; forcing a code as well would
      // ask the user to prove something twice.
      expect(
        resolveAuthState(user(providers: const ['password', 'google.com'])),
        isA<Authenticated>(),
      );
    });
  });
}
