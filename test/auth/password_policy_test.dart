import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/password_policy.dart';

void main() {
  group('PasswordPolicy', () {
    test('rejects a too-short password', () {
      expect(PasswordPolicy.isSatisfiedBy('Pw0'), isFalse);
    });

    test('rejects a password missing an uppercase letter', () {
      expect(PasswordPolicy.isSatisfiedBy('passw0rd'), isFalse);
    });

    test('rejects a password missing a lowercase letter', () {
      expect(PasswordPolicy.isSatisfiedBy('PASSW0RD'), isFalse);
    });

    test('rejects a password missing a digit', () {
      expect(PasswordPolicy.isSatisfiedBy('Password'), isFalse);
    });

    test('accepts a compliant password', () {
      expect(PasswordPolicy.isSatisfiedBy('Passw0rd'), isTrue);
    });

    test('unmetRules lists only the rules not yet satisfied', () {
      final unmet = PasswordPolicy.unmetRules('short');
      expect(unmet, isNotEmpty);
      expect(unmet.every((rule) => !rule.isSatisfiedBy('short')), isTrue);

      expect(PasswordPolicy.unmetRules('Passw0rd'), isEmpty);
    });
  });
}
