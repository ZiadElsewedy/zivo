import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/profile/domain/user_profile.dart';

void main() {
  group('isProfileComplete', () {
    test('null profile is incomplete', () {
      expect(isProfileComplete(null), isFalse);
    });

    test('empty name is incomplete', () {
      final profile = UserProfile(uid: 'u1', name: '', dateOfBirth: DateTime(2000, 1, 1));
      expect(isProfileComplete(profile), isFalse);
    });

    test('whitespace-only name is incomplete', () {
      final profile = UserProfile(uid: 'u1', name: '   ', dateOfBirth: DateTime(2000, 1, 1));
      expect(isProfileComplete(profile), isFalse);
    });

    test('a name and date of birth make a complete profile', () {
      final profile = UserProfile(uid: 'u1', name: 'Ziad', dateOfBirth: DateTime(2000, 1, 1));
      expect(isProfileComplete(profile), isTrue);
    });
  });
}
