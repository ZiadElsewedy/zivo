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

  /// Connected to the Spotify app, but the signed-in account is Free —
  /// Spotify's App Remote SDK only allows *observing* playback state for
  /// Free accounts, not driving it (play/pause/seek/skip all fail).
  needsPremium,

  /// The Spotify app isn't installed on this device — App Remote requires
  /// it (there's no web-playback fallback in this integration).
  noSpotifyApp,
}
