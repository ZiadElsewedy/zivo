/// A single account's media-storage choices. Persisted per-uid so preferences
/// follow the account.
///
/// Local storage is always on and not represented here — capturing media always
/// writes the durable local copy. Google Drive *connection* is intentionally
/// NOT here: it's a per-device fact (see `DriveConnectionStore`), so a device
/// that never connected is never nagged to sign in. This holds only the small,
/// device-agnostic media preferences.
class MediaStoragePreferences {
  const MediaStoragePreferences({
    this.saveToPhotos = false,
    this.autoUploadToDrive = true,
  });

  /// Opt-in: also copy each captured photo into the device's system Photos.
  final bool saveToPhotos;

  /// Default-on: the moment a capture lands locally it also uploads to Google
  /// Drive (when this device has a connected session) — a photo becomes
  /// recoverable on every other device within seconds of being taken, no
  /// "Back up now" visit required. Off here means manual-only backups. Never
  /// prompts: if no session can be silently restored, the upload simply
  /// doesn't happen now and the next "Back up now" covers it.
  final bool autoUploadToDrive;

  /// Default preferences for a brand-new account: local-first, auto-upload on.
  static const MediaStoragePreferences defaults = MediaStoragePreferences();

  MediaStoragePreferences copyWith({
    bool? saveToPhotos,
    bool? autoUploadToDrive,
  }) =>
      MediaStoragePreferences(
        saveToPhotos: saveToPhotos ?? this.saveToPhotos,
        autoUploadToDrive: autoUploadToDrive ?? this.autoUploadToDrive,
      );

  @override
  bool operator ==(Object other) =>
      other is MediaStoragePreferences &&
      other.saveToPhotos == saveToPhotos &&
      other.autoUploadToDrive == autoUploadToDrive;

  @override
  int get hashCode => Object.hash(saveToPhotos, autoUploadToDrive);
}

/// The seam between the app and per-account media preferences storage.
abstract interface class MediaPreferencesRepository {
  /// The current signed-in account's preferences as a live stream, re-scoped
  /// when the uid changes (defaults emitted when signed out or unset).
  Stream<MediaStoragePreferences> watch();

  /// Reads the current account's preferences once.
  Future<MediaStoragePreferences> read();

  /// Persists [preferences] for the current account.
  Future<void> save(MediaStoragePreferences preferences);
}
