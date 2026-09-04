import 'package:flutter/foundation.dart';

/// The build configurations ZIVO ships. These mirror Flutter's build modes
/// 1:1 — there is deliberately no separate "flavor" axis, because there is a
/// single Firebase backend. Flavors would be the right tool only if/when a
/// separate dev/staging backend is introduced.
enum AppConfig { development, profile, release }

/// Single source of truth for environment-specific configuration.
///
/// Everything that used to be read ad-hoc — `USE_FIRESTORE` in `app.dart`, the
/// Google client id in `AuthConfig` — is resolved here, once. The active
/// [config] is derived from
/// Flutter's compile-time build-mode constants (`kReleaseMode`/`kProfileMode`),
/// so each build tree-shakes to exactly one branch.
///
/// Non-secret values may be overridden per configuration via
/// `--dart-define-from-file=config/<env>.json` (see the `config/` directory).
/// **No secrets live here or in those files** — only public client ids and
/// feature flags. Real credentials stay in the platform Firebase config files
/// (`google-services.json` / `GoogleService-Info.plist`), which are not secret.
class AppEnvironment {
  const AppEnvironment._();

  /// The active build configuration, from Flutter's build mode.
  static final AppConfig config = kReleaseMode
      ? AppConfig.release
      : kProfileMode
      ? AppConfig.profile
      : AppConfig.development;

  static bool get isDevelopment => config == AppConfig.development;
  static bool get isProfile => config == AppConfig.profile;
  static bool get isRelease => config == AppConfig.release;

  /// Human-readable label (logs, docs).
  static String get name => switch (config) {
    AppConfig.development => 'Development',
    AppConfig.profile => 'Profile',
    AppConfig.release => 'Release',
  };

  /// The raw `USE_FIRESTORE` override. On by default; a debug/profile run can
  /// opt into the in-memory demo mode with `--dart-define=USE_FIRESTORE=false`.
  static const bool _useFirestoreOverride = bool.fromEnvironment(
    'USE_FIRESTORE',
    defaultValue: true,
  );

  /// Whether to persist to Firestore (vs the in-memory demo repositories).
  ///
  /// **Release builds always use Firestore — the `USE_FIRESTORE=false` override
  /// is ignored in release.** The in-memory repos seed demo data (the hardcoded
  /// `ziadWorkoutPlan`, fake AI/music), which must never reach a shipped build:
  /// a stale/accidental override once baked demo mode into a TestFlight archive
  /// (Xcode's Archive reuses the dart-defines from the last `flutter build` —
  /// see `docs/build_configurations.md`). This guard makes that impossible;
  /// demo mode remains available in debug/profile for offline work and tests.
  static bool get useFirestore =>
      resolveUseFirestore(isRelease: isRelease, override: _useFirestoreOverride);

  /// The pure guard behind [useFirestore], exposed so it is testable without a
  /// release build (unit tests always run as Development, so the release branch
  /// is otherwise unreachable). Release forces Firestore on; every other config
  /// honours the [override].
  @visibleForTesting
  static bool resolveUseFirestore({
    required bool isRelease,
    required bool override,
  }) => isRelease ? true : override;

  /// Public Google **Web** OAuth client id passed to `google_sign_in` as
  /// `serverClientId`. A public identifier, not a secret. Overridable via
  /// `--dart-define=GOOGLE_SERVER_CLIENT_ID=<id>.apps.googleusercontent.com`.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '317167114617-k2u8fg7u6a3ppa5gagmcbu2jr7u4ljnb.apps.googleusercontent.com',
  );
}
