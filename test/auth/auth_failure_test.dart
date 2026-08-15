import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/auth_failure.dart';

void main() {
  group('mapAuthErrorCode', () {
    test('maps invalid-email', () {
      expect(mapAuthErrorCode('invalid-email').kind, AuthFailureKind.invalidEmail);
    });

    test('collapses wrong-password / user-not-found / invalid-credential', () {
      for (final code in ['wrong-password', 'user-not-found', 'invalid-credential']) {
        final f = mapAuthErrorCode(code);
        expect(f.kind, AuthFailureKind.wrongPassword,
            reason: '$code should map to wrongPassword');
        expect(f.message, 'Email or password is incorrect.');
      }
    });

    test('maps email-already-in-use and weak-password', () {
      expect(mapAuthErrorCode('email-already-in-use').kind,
          AuthFailureKind.emailAlreadyInUse);
      expect(mapAuthErrorCode('weak-password').kind, AuthFailureKind.weakPassword);
    });

    test('maps provider/config codes to providerConfig', () {
      expect(mapAuthErrorCode('operation-not-allowed').kind,
          AuthFailureKind.providerConfig);
      expect(mapAuthErrorCode('configuration-not-found').kind,
          AuthFailureKind.providerConfig);
    });

    test('maps network and rate-limit codes', () {
      expect(mapAuthErrorCode('network-request-failed').kind,
          AuthFailureKind.networkError);
      expect(mapAuthErrorCode('too-many-requests').kind,
          AuthFailureKind.tooManyRequests);
    });

    test('falls back to unknown for unrecognised codes', () {
      final f = mapAuthErrorCode('something-weird');
      expect(f.kind, AuthFailureKind.unknown);
      expect(f.message, isNotEmpty);
    });
  });
}
