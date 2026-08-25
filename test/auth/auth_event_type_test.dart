import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/auth_event_type.dart';

void main() {
  group('AuthEventType', () {
    test('id is the enum name (wire contract)', () {
      expect(AuthEventType.accountCreated.id, 'accountCreated');
      expect(AuthEventType.signIn.id, 'signIn');
      expect(AuthEventType.signOut.id, 'signOut');
      expect(AuthEventType.emailOtpSent.id, 'emailOtpSent');
      expect(AuthEventType.emailVerified.id, 'emailVerified');
      expect(AuthEventType.passwordChanged.id, 'passwordChanged');
    });

    test('tryParse round-trips every value', () {
      for (final type in AuthEventType.values) {
        expect(AuthEventType.tryParse(type.id), type);
      }
    });

    test('tryParse resolves unknown/legacy values to null', () {
      expect(AuthEventType.tryParse('biometricUnlock'), isNull);
      expect(AuthEventType.tryParse(42), isNull);
      expect(AuthEventType.tryParse(null), isNull);
    });
  });
}
