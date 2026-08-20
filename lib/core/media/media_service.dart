import 'dart:io';

import 'package:path/path.dart' as p;

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
/// records a [MediaObject] in the [MediaRegistry], and — only if the account
/// opted in — copies to the system Photos.
///
/// Google Drive is deliberately **manual and device-local**: nothing here ever
/// touches the Google SDK on its own. Uploads/downloads happen only from the
/// user-initiated [backupNow] / [syncFromDrive], and passive reads
/// ([resolveOrFetch]) fetch from Drive only when a session is already live —
/// so opening Moments or taking a photo never triggers a sign-in prompt.
class MediaService {
  MediaService({
    required this.store,
    required this.registry,
    required this.preferences,
    this.targets = const {},
    this.driveClient,
  });

  final MediaStore store;
  final MediaRegistry registry;
  final MediaPreferencesRepository preferences;

  /// Non-Drive fan-out targets (currently the device gallery for "Save to
  /// Photos"). Drive is handled directly, not as a passive target.
  final Map<BackupTargetId, MediaBackupTarget> targets;

  /// The Google Drive seam, or null in offline/dev builds.
  final DriveBackupClient? driveClient;

  /// Whether Drive backup is offered in the UI at all (build has a client).
  bool get supportsDrive => driveClient != null;

  /// Whether an authorized Drive session is live right now (no SDK call).
  bool get isDriveSessionLive => driveClient?.hasLiveSession ?? false;

  /// Whether this *device* has connected Drive before (persisted).
  Future<bool> isDriveConnected() async =>
      await driveClient?.isDeviceConnected() ?? false;

  /// The connected Google account email on this device, if any.
  Future<String?> connectedDriveEmail() async =>
      await driveClient?.connectedEmail();

  /// Imports a just-captured/picked file into durable local storage, registers
  /// it, and — if "Save to Photos" is on — copies it to the system gallery.
  /// Never touches Drive. Returns the store-relative reference to persist.
  Future<String> capture({
    required String sourcePath,
    required MediaKind kind,
    required String id,
    required String ownerUid,
    CaptureSource source = CaptureSource.unknown,
    DateTime? capturedAt,
  }) async {
    final stored = await store.importFile(sourcePath: sourcePath, kind: kind, id: id);

    // Local copy done — everything below is best-effort and must never lose the
    // photo or block the owning entity from saving.
    MediaStoragePreferences prefs;
    try {
      prefs = await preferences.read();
    } catch (_) {
      prefs = MediaStoragePreferences.defaults;
    }

    var object = MediaObject(
      id: id,
      ownerUid: ownerUid,
      kind: kind,
      relativePath: stored.relativePath,
      mimeType: stored.mimeType,
      byteSize: stored.byteSize,
      contentHash: stored.contentHash,
      capturedAt: capturedAt ?? DateTime.now(),
      source: source,
      width: stored.width,
      height: stored.height,
    );

    if (prefs.saveToPhotos) {
      object = await _runGallery(object);
    }

    try {
      await registry.put(object);
    } catch (_) {
      // Metadata is best-effort; the local file still exists.
    }
    return stored.relativePath;
  }

  /// Resolves a stored reference to an absolute [File] for display, or null.
  Future<File?> resolve(String? ref) => store.resolve(ref);

  /// Like [resolve], but if the local copy is missing it pulls the bytes from
  /// Drive — *only when a session is already live* (so it never prompts). On a
  /// second device the user connects Drive once (in Storage & Sync), which
  /// establishes the session; then photos download on demand and are cached.
  Future<File?> resolveOrFetch(String? ref) async {
    final local = await store.resolve(ref);
    if (local != null && await local.exists()) return local;
    if (ref == null || ref.isEmpty) return null;

    final client = driveClient;
    if (client == null || !client.hasLiveSession) return null;

    final id = p.posix.basenameWithoutExtension(ref);
    MediaObject? object;
    try {
      object = await registry.get(id);
    } catch (_) {
      return null;
    }
    final driveFileId = object?.driveFileId;
    if (driveFileId == null) return null;

    try {
      final bytes = await client.download(driveFileId);
      if (bytes == null || bytes.isEmpty) return null;
      return await store.writeBytes(ref, bytes);
    } catch (_) {
      return null;
    }
  }

  /// Deletes the local file and its registry entry.
  Future<void> deleteMedia({required String id, required String? ref}) async {
    await store.delete(ref);
    await registry.remove(id);
  }

  /// Interactive connect to Google Drive (user-initiated). Returns whether it
  /// connected. The connection is remembered per-device by the client.
  Future<bool> connectDrive() async {
    final account = await driveClient?.connect();
    return account != null;
  }

  /// Disconnects Drive on this device.
  Future<void> disconnectDrive() => driveClient?.disconnect() ?? Future.value();

  /// Uploads every not-yet-backed-up photo to the account's Drive subfolder.
  /// User-initiated ("Back up now"): may establish/restore the session. Returns
  /// how many were pushed (0 if Drive isn't connected on this device).
  Future<int> backupNow() async {
    final client = driveClient;
    if (client == null) return 0;
    if (!client.hasLiveSession && await client.restoreSession() == null) return 0;

    final pending = await registry.pendingBackups();
    var pushed = 0;
    for (final object in pending) {
      if (object.drive == BackupState.done) continue;
      final file = await store.resolve(object.relativePath);
      if (file == null || !await file.exists()) continue; // nothing local to upload
      final remoteId = await client.uploadImage(
        file: file,
        fileName: p.posix.basename(object.relativePath),
        mimeType: object.mimeType,
        accountFolder: object.ownerUid,
        replaceFileId: object.driveFileId,
      );
      if (remoteId != null) {
        await registry.put(object.copyWith(drive: BackupState.done, driveFileId: remoteId));
        pushed++;
      } else {
        await registry.put(object.copyWith(drive: BackupState.failed));
      }
    }
    return pushed;
  }

  /// Downloads every backed-up photo missing locally (e.g. a second device or
  /// after reinstall) into the local store. User-initiated ("Sync from Drive").
  /// Returns how many were fetched.
  Future<int> syncFromDrive() async {
    final client = driveClient;
    if (client == null) return 0;
    if (!client.hasLiveSession && await client.restoreSession() == null) return 0;

    final all = await registry.getAll();
    var fetched = 0;
    for (final object in all) {
      final driveFileId = object.driveFileId;
      if (driveFileId == null) continue;
      final local = await store.resolve(object.relativePath);
      if (local != null && await local.exists()) continue;
      final bytes = await client.download(driveFileId);
      if (bytes == null || bytes.isEmpty) continue;
      await store.writeBytes(object.relativePath, bytes);
      fetched++;
    }
    return fetched;
  }

  /// Invokes the gallery target and folds its result into the object's state.
  Future<MediaObject> _runGallery(MediaObject object) async {
    final target = targets[BackupTargetId.gallery];
    if (target == null) return object;
    BackupResult result;
    try {
      if (!await target.isConfigured()) return object;
      result = await target.backup(object);
    } catch (_) {
      result = const BackupResult.failure();
    }
    return object.copyWith(
      gallery: result.succeeded ? BackupState.done : BackupState.failed,
    );
  }
}
