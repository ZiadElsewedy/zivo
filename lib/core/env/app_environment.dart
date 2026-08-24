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

  /// Whether to persist to Firestore. On by default; opt out for offline/dev
  /// runs with `--dart-define=USE_FIRESTORE=false`.
  static const bool useFirestore = bool.fromEnvironment(
    'USE_FIRESTORE',
    defaultValue: true,
  );

  /// Public Google **Web** OAuth client id passed to `google_sign_in` as
  /// `serverClientId`. A public identifier, not a secret. Overridable via
  /// `--dart-define=GOOGLE_SERVER_CLIENT_ID=<id>.apps.googleusercontent.com`.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '317167114617-k2u8fg7u6a3ppa5gagmcbu2jr7u4ljnb.apps.googleusercontent.com',
  );
}
