/// The music controller's connection state — surfaced by
/// `MusicController.connection` so the UI (mini bar, full player) can show
/// the right affordance instead of just a blank/broken player.
enum MusicConnection {
  /// Not connected — nothing attempted yet, or a previous connection was
  /// explicitly closed via `disconnect()`.
  disconnected,

  /// A `connect()` call is in flight.
  connecting,

  /// Connected and ready — `nowPlaying` may still be null if nothing is
  /// loaded in the player.
  connected,

  /// The App Remote SDK rejected the connection for an auth reason —
  /// covers `UserNotAuthorizedException`, `AuthenticationFailedException`,
  /// and `NotLoggedInException` (see `SpotifyMusicController._mapErrorCode`).
  /// In Spotify Developer Dashboard "Development mode" (this app's current
  /// mode), the single most common real cause is the signed-in account not
  /// being added under the dashboard's User Management allow-list — but
  /// that's developer-facing context, not something to name in user-facing
  /// copy, since the same code also covers a plain declined/failed
  /// authorization. Show a generic, actionable "try again" message, never a
  /// specific claim about *why* (see [needsPremium]'s doc for the mistake
  /// this replaces).
  authFailed,

  /// Reserved for a genuinely Premium-specific signal — the App Remote SDK
  /// does not currently expose one (verified against `spotify_sdk` 3.0.2's
  /// Android/iOS plugin source: every auth-rejection path there is one of
  /// the [authFailed] exceptions, none of which distinguish "no Premium"
  /// from "not authorized" for any other reason). `_mapErrorCode` never
  /// produces this today — an earlier version of this mapping wrongly used
  /// it for `UserNotAuthorizedException`, which is NOT a Premium signal, it
  /// just means the app/account isn't authorized. Kept in the enum (rather
  /// than deleted) only in case a future SDK version adds a real one.
  needsPremium,

  /// The Spotify app isn't installed on this device — App Remote requires
  /// it (there's no web-playback fallback in this integration).
  noSpotifyApp,
}
