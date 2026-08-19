/// A single account's media-storage choices. Persisted per-uid so preferences
/// follow the account (and each signed-in user decides independently), not the
/// device.
///
/// Local storage is always on and not represented here — capturing media always
/// writes the durable local copy. These fields govern the *additional*
/// destinations and the backup cadence layered on top.
class MediaStoragePreferences {
  const MediaStoragePreferences({
    this.saveToPhotos = false,
    this.driveBackupEnabled = false,
    this.driveConnected = false,
    this.driveAccountEmail,
    this.autoBackupEveryDays = 3,
    this.wifiOnly = true,
    this.lastBackupAt,
  });

  /// Opt-in: also copy each captured photo into the device's system Photos.
  final bool saveToPhotos;

  /// Whether Google Drive backup is switched on for this account.
  final bool driveBackupEnabled;

  /// Whether a Google account has actually been connected (OAuth granted).
  /// Independent of how the user signed in — Apple/email users still connect
  /// Drive as a separate step.
  final bool driveConnected;

  /// The connected Google account's email, for display in Settings.
  final String? driveAccountEmail;

  /// Auto-backup cadence in days. The scheduler backs pending media up when at
  /// least this many days have passed since [lastBackupAt] and the app opens.
  /// Null disables the automatic cadence (manual "Back up now" still works).
  final int? autoBackupEveryDays;

  /// Restrict automatic backups to unmetered (wifi) connections.
  final bool wifiOnly;

  /// When the last successful backup run completed. Drives the 3-day cadence.
  final DateTime? lastBackupAt;

  /// Default preferences for a brand-new account: local-only, nothing else on.
  static const MediaStoragePreferences defaults = MediaStoragePreferences();

  MediaStoragePreferences copyWith({
    bool? saveToPhotos,
    bool? driveBackupEnabled,
    bool? driveConnected,
    String? driveAccountEmail,
    bool clearDriveAccountEmail = false,
    int? autoBackupEveryDays,
    bool? wifiOnly,
    DateTime? lastBackupAt,
  }) {
    return MediaStoragePreferences(
      saveToPhotos: saveToPhotos ?? this.saveToPhotos,
      driveBackupEnabled: driveBackupEnabled ?? this.driveBackupEnabled,
      driveConnected: driveConnected ?? this.driveConnected,
      driveAccountEmail: clearDriveAccountEmail
          ? null
          : (driveAccountEmail ?? this.driveAccountEmail),
      autoBackupEveryDays: autoBackupEveryDays ?? this.autoBackupEveryDays,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaStoragePreferences &&
      other.saveToPhotos == saveToPhotos &&
      other.driveBackupEnabled == driveBackupEnabled &&
      other.driveConnected == driveConnected &&
      other.driveAccountEmail == driveAccountEmail &&
      other.autoBackupEveryDays == autoBackupEveryDays &&
      other.wifiOnly == wifiOnly &&
      other.lastBackupAt == lastBackupAt;

  @override
  int get hashCode => Object.hash(
        saveToPhotos,
        driveBackupEnabled,
        driveConnected,
        driveAccountEmail,
        autoBackupEveryDays,
        wifiOnly,
        lastBackupAt,
      );
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
