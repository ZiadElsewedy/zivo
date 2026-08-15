/// Non-secret client configuration for the auth data layer.
///
/// The Google **Web** client ID is a public OAuth client identifier (not a
/// secret). It is passed to `google_sign_in` as `serverClientId` so the
/// returned `idToken` is minted for the Firebase backend's audience. Required
/// on Android to obtain an id token; on iOS the client ID is read from
/// `GoogleService-Info.plist` automatically.
///
/// The default below is the ZIVO Firebase project's **web** OAuth client
/// (`client_type: 3` in `android/app/google-services.json`) so plain
/// `flutter run` works. It can still be overridden without editing code via:
///
/// ```
/// flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
/// ```
class AuthConfig {
  const AuthConfig._();

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '317167114617-k2u8fg7u6a3ppa5gagmcbu2jr7u4ljnb.apps.googleusercontent.com',
  );
}
