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

    test('defaults: Firestore on, public client id present', () {
      expect(AppEnvironment.useFirestore, isTrue);
      expect(
        AppEnvironment.googleServerClientId,
        endsWith('.apps.googleusercontent.com'),
      );
    });
  });

  group('useFirestore release guard', () {
    // A release build always uses Firestore, so an accidental or stale
    // USE_FIRESTORE=false override can never ship the in-memory demo mode
    // (the bug that once reached TestFlight via a cached dart-define).
    test('release ignores a false override', () {
      expect(
        AppEnvironment.resolveUseFirestore(isRelease: true, override: false),
        isTrue,
      );
      expect(
        AppEnvironment.resolveUseFirestore(isRelease: true, override: true),
        isTrue,
      );
    });

    test('debug/profile honour the override', () {
      expect(
        AppEnvironment.resolveUseFirestore(isRelease: false, override: false),
        isFalse,
      );
      expect(
        AppEnvironment.resolveUseFirestore(isRelease: false, override: true),
        isTrue,
      );
    });
  });
}
