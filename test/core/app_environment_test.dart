import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/env/app_environment.dart';

void main() {
  // Under `flutter test`, kReleaseMode and kProfileMode are both false, so the
  // active configuration resolves to Development. These assertions lock in the
  // Development branch of the resolution logic (the other branches are
  // compile-time constants selected by the build mode).
  group('AppEnvironment (Development / test context)', () {
    test('resolves to the Development configuration', () {
      expect(AppEnvironment.config, AppConfig.development);
      expect(AppEnvironment.isDevelopment, isTrue);
      expect(AppEnvironment.isProfile, isFalse);
      expect(AppEnvironment.isRelease, isFalse);
      expect(AppEnvironment.name, 'Development');
    });

    test('Development uses App Check debug providers', () {
      expect(AppEnvironment.appCheckMode, AppCheckMode.debug);
    });

    test('defaults: Firestore on, public client id present', () {
      expect(AppEnvironment.useFirestore, isTrue);
      expect(
        AppEnvironment.googleServerClientId,
        endsWith('.apps.googleusercontent.com'),
      );
    });
  });
}
