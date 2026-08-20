import 'media_object.dart';

/// The identity of a backup destination. Used as the map key when the
/// [MediaService] fans a captured file out to the enabled targets, and to tag
/// per-target state on [MediaObject].
enum BackupTargetId {
  /// The device's system Photos/Gallery (opt-in "Save to Photos").
  gallery,

  /// Google Drive (`drive.file` scope — app-created files only).
  drive,
}

/// A pluggable destination a media file can be copied to. New destinations
/// (iCloud, Dropbox, …) implement this interface and are registered with the
/// [MediaService] — no feature or service rewrite required.
///
/// Targets are intentionally dumb: they push one file and report a result.
/// *Whether* and *when* a file is pushed (per-account preferences, the 3-day
/// auto-backup cadence, wifi-only) is decided by the service and preferences,
/// not here.
abstract interface class MediaBackupTarget {
  BackupTargetId get id;

  /// Whether this target is usable right now (permissions granted, account
  /// connected). The service skips unconfigured targets rather than throwing.
  Future<bool> isConfigured();

  /// Pushes the file backing [object] (resolved via the store) to the target.
  /// Returns the outcome; throwing is also treated as a failure by the service.
  Future<BackupResult> backup(MediaObject object);
}

/// The outcome of a single [MediaBackupTarget.backup] call.
class BackupResult {
  const BackupResult.success({this.remoteId}) : succeeded = true;
  const BackupResult.failure() : succeeded = false, remoteId = null;

  final bool succeeded;

  /// A target-assigned id for the pushed file (e.g. a Drive file id), when the
  /// target has one. Persisted onto [MediaObject.driveFileId] for Drive.
  final String? remoteId;
}
