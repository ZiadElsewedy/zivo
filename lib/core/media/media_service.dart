import 'dart:io';

import 'domain/drive_backup_client.dart';
import 'domain/media_backup_target.dart';
import 'domain/media_kind.dart';
import 'domain/media_object.dart';
import 'domain/media_registry.dart';
import 'domain/media_store.dart';
import 'domain/media_storage_preferences.dart';

/// The single entry point features use for media. It hides *where* bytes go:
/// callers hand it a captured file and get back a durable reference to embed in
/// their entity; the service copies the bytes into the local [MediaStore],
/// records a [MediaObject] in the [MediaRegistry], and fans the file out to
/// whatever backup targets the account has enabled.
///
/// Storage policy (local always on; Photos on capture; Drive on the manual /
/// 3-day cadence) lives here, driven by [MediaPreferencesRepository] — not in
/// the features, and not in the targets.
class MediaService {
  MediaService({
    required this.store,
    required this.registry,
    required this.preferences,
    this.targets = const {},
    this.driveClient,
    this.isUnmetered,
  });

  final MediaStore store;
  final MediaRegistry registry;
  final MediaPreferencesRepository preferences;
  final Map<BackupTargetId, MediaBackupTarget> targets;

  /// The Google Drive connection seam, used by the Settings connect/disconnect
  /// flow. Null when Drive isn't wired (offline/dev builds); the Drive backup
  /// *upload* path goes through [targets] instead.
  final DriveBackupClient? driveClient;

  /// Whether Drive backup is available to offer in the UI at all.
  bool get supportsDrive => driveClient != null;

  /// Reports whether the current connection is unmetered (wifi/ethernet), used
  /// to honor "Wi-Fi only" for *automatic* backups. Null = unknown/always allow.
  final Future<bool> Function()? isUnmetered;

  /// Imports a just-captured/picked file into durable local storage, registers
  /// it for [ownerUid], and — if the account opted into "Save to Photos" —
  /// copies it to the system gallery. Drive backup is deliberately *not* done
  /// here; it runs on the manual "Back up now" action or the 3-day cadence.
  ///
  /// Returns the store-relative reference to persist on the owning entity
  /// (`Moment.imagePath` / `UserProfile.photoPath`).
  Future<String> capture({
    required String sourcePath,
    required MediaKind kind,
    required String id,
    required String ownerUid,
    DateTime? capturedAt,
  }) async {
    final stored = await store.importFile(
      sourcePath: sourcePath,
      kind: kind,
      id: id,
    );

    final prefs = await preferences.read();
    var object = MediaObject(
      id: id,
      ownerUid: ownerUid,
      kind: kind,
      relativePath: stored.relativePath,
      mimeType: stored.mimeType,
      byteSize: stored.byteSize,
      contentHash: stored.contentHash,
      capturedAt: capturedAt ?? DateTime.now(),
    );

    if (prefs.saveToPhotos) {
      object = await _run(BackupTargetId.gallery, object);
    }

    await registry.put(object);
    return stored.relativePath;
  }

  /// Resolves a stored reference to an absolute [File] for display, or null.
  Future<File?> resolve(String? ref) => store.resolve(ref);

  /// Connects a Google account for Drive backup (interactive) and, on success,
  /// records it in preferences (connected + enabled + email). Returns whether
  /// it connected. No-op returning false when Drive isn't wired.
  Future<bool> connectDrive() async {
    final client = driveClient;
    if (client == null) return false;
    final account = await client.connect();
    if (account == null) return false;
    final prefs = await preferences.read();
    await preferences.save(prefs.copyWith(
      driveConnected: true,
      driveBackupEnabled: true,
      driveAccountEmail: account.email,
    ));
    return true;
  }

  /// Disconnects Drive: revokes the Google session and clears the connection
  /// from preferences (backup stays local-only).
  Future<void> disconnectDrive() async {
    await driveClient?.disconnect();
    final prefs = await preferences.read();
    await preferences.save(prefs.copyWith(
      driveConnected: false,
      driveBackupEnabled: false,
      clearDriveAccountEmail: true,
    ));
  }

  /// Deletes the local file and its registry entry. (Removing an already
  /// backed-up copy from a remote target is a Phase 2 concern.)
  Future<void> deleteMedia({required String id, required String? ref}) async {
    await store.delete(ref);
    await registry.remove(id);
  }

  /// Runs a backup pass over every media file whose Drive copy is still
  /// pending/failed, then stamps [MediaStoragePreferences.lastBackupAt].
  /// A no-op (beyond the stamp) until a Drive target is registered (Phase 2).
  /// Returns how many files were successfully pushed.
  Future<int> backupNow() async {
    final prefs = await preferences.read();
    var pushed = 0;
    if (prefs.driveBackupEnabled && targets.containsKey(BackupTargetId.drive)) {
      final pending = await registry.pendingBackups();
      for (final object in pending) {
        if (object.drive == BackupState.done) continue;
        final updated = await _run(BackupTargetId.drive, object);
        await registry.put(updated);
        if (updated.drive == BackupState.done) pushed++;
      }
    }
    await preferences.save(prefs.copyWith(lastBackupAt: DateTime.now()));
    return pushed;
  }

  /// Runs [backupNow] only if the account's auto-backup cadence is due
  /// (>= [MediaStoragePreferences.autoBackupEveryDays] since the last run).
  /// Intended to be called on app open; iOS cannot guarantee true timed
  /// background execution.
  Future<void> runAutoBackupIfDue({DateTime? now}) async {
    final prefs = await preferences.read();
    final everyDays = prefs.autoBackupEveryDays;
    if (!prefs.driveBackupEnabled || everyDays == null) return;
    final last = prefs.lastBackupAt;
    final current = now ?? DateTime.now();
    if (last != null && current.difference(last).inDays < everyDays) return;
    // Honor "Wi-Fi only" for the automatic path (the manual "Back up now"
    // action deliberately ignores it — the user asked for it explicitly).
    if (prefs.wifiOnly && isUnmetered != null && !await isUnmetered!()) return;
    await backupNow();
  }

  /// Invokes one target and folds its result back into the [MediaObject]'s
  /// per-target state. Never throws — a target failure is recorded, not fatal.
  Future<MediaObject> _run(BackupTargetId targetId, MediaObject object) async {
    final target = targets[targetId];
    if (target == null) return object;
    BackupResult result;
    try {
      if (!await target.isConfigured()) return object;
      result = await target.backup(object);
    } catch (_) {
      result = const BackupResult.failure();
    }
    final state = result.succeeded ? BackupState.done : BackupState.failed;
    switch (targetId) {
      case BackupTargetId.gallery:
        return object.copyWith(gallery: state);
      case BackupTargetId.drive:
        return object.copyWith(drive: state, driveFileId: result.remoteId);
    }
  }
}
