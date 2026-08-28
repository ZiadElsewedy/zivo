/// Feature flag + Spotify app config for the music/now-playing feature.
///
/// [kMusicEnabled] gates this feature's UI mounting (see `home_shell.dart`,
/// which only mounts the now-playing lozenge when it's true, and
/// `profile_page.dart`'s "Connect Spotify" row, same gate). The
/// `MusicController` itself is always wired into [AppScope] regardless of
/// this flag; `app.dart`'s `_defaultMusic()` picks `SpotifyMusicController`
/// over `FakeMusicController` only when BOTH this is true AND
/// [spotifyClientId] is non-empty.
const bool kMusicEnabled = true;

/// The app's Spotify Developer Dashboard Client ID — a public identifier for
/// the Authorization Code with PKCE flow (no client secret involved; safe to
/// ship in the app binary, same as this being plain source here).
const String spotifyClientId = 'a1b5285079624e06ac6553c109289f40';

/// Must exactly match a Redirect URI registered on the Spotify Developer
/// Dashboard for [spotifyClientId] — registered. The custom URL scheme
/// (`zivo`) is also registered in the iOS/Android native config (see
/// ios/Runner/Info.plist's CFBundleURLTypes and the Android manifest).
const String spotifyRedirectUri = 'zivo://spotify-callback';
