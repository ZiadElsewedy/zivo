/// Non-secret client configuration for the auth data layer.
///
/// The Google **Web** client ID is a public OAuth client identifier (not a
/// secret), but it isn't known until the Google provider is enabled in the
/// Firebase console. Supply it without editing code via:
///
/// ```
/// flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
/// ```
///
/// It is passed to `google_sign_in` as `serverClientId` so the returned
/// `idToken` is minted for the Firebase backend's audience. Required on Android
/// to obtain an id token; on iOS the client ID is read from
/// `GoogleService-Info.plist` automatically. When empty, initialization omits
/// it (iOS-only flows still work).
class AuthConfig {
  const AuthConfig._();

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );
}
