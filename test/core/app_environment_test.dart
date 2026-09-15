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

  group('useFirebaseEmulator', () {
    test('defaults off in the test context', () {
      expect(AppEnvironment.useFirebaseEmulator, isFalse);
    });

    // A release build must never talk to a developer's laptop, so the override
    // is ignored in release — mirroring the useFirestore guard.
    test('release ignores a true override', () {
      expect(
        AppEnvironment.resolveUseFirebaseEmulator(
          isRelease: true,
          override: true,
        ),
        isFalse,
      );
      expect(
        AppEnvironment.resolveUseFirebaseEmulator(
          isRelease: true,
          override: false,
        ),
        isFalse,
      );
    });

    test('debug/profile honour the override', () {
      expect(
        AppEnvironment.resolveUseFirebaseEmulator(
          isRelease: false,
          override: true,
        ),
        isTrue,
      );
      expect(
        AppEnvironment.resolveUseFirebaseEmulator(
          isRelease: false,
          override: false,
        ),
        isFalse,
      );
    });
  });

  group('emulatorHost', () {
    test('Android emulator reaches the host at 10.0.2.2 by default', () {
      expect(
        AppEnvironment.resolveEmulatorHost(override: '', isAndroid: true),
        '10.0.2.2',
      );
    });

    test('other targets default to localhost', () {
      expect(
        AppEnvironment.resolveEmulatorHost(override: '', isAndroid: false),
        'localhost',
      );
    });

    test('an explicit override wins (e.g. a physical device LAN IP)', () {
      expect(
        AppEnvironment.resolveEmulatorHost(
          override: '192.168.1.20',
          isAndroid: true,
        ),
        '192.168.1.20',
      );
    });
  });
}
