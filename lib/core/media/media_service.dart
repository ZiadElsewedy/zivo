import 'dart:io';

import 'package:path/path.dart' as p;

import 'domain/media_backup_provider.dart';
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
/// opted in — copies to the system Photos ([galleryTarget]).
///
/// Cloud backup is provider-agnostic ([MediaBackupProvider]) and deliberately
/// **manual and device-local**: nothing here touches a provider SDK on its own.
/// Uploads/downloads happen only from the user-initiated [backupNow] /
/// [syncFromBackup], and passive reads ([resolveOrFetch]) fetch only when a
/// session is already live — so opening Moments or taking a photo never
/// triggers a sign-in prompt. Swapping in a different provider (iCloud, Dropbox)
/// touches only the composition root, not this service or the features.
class MediaService {
  MediaService({
    required this.store,
    required this.registry,
    required this.preferences,
    this.galleryTarget,
    this.backup,
    this.currentAccountId,
  });

  final MediaStore store;
  final MediaRegistry registry;
  final MediaPreferencesRepository preferences;

  /// Optional on-capture copy to the device gallery ("Save to Photos").
  final MediaBackupTarget? galleryTarget;

  /// The cloud backup provider, or null in offline/dev builds.
  final MediaBackupProvider? backup;

  /// The signed-in ZIVO account uid right now (from the composition root). Used
  /// to enforce backup-connection ownership so account A's connection is never
  /// used by account B.
  final String? Function()? currentAccountId;

  /// Whether cloud backup is offered in the UI at all (build has a provider).
  bool get supportsBackup => backup != null;

  /// Whether this *device* has a backup connection usable by the current
  /// account. A connection owned by a different account is treated as not
  /// connected (and cleared — see [_backupConnectionValidForCurrentAccount]).
  Future<bool> isBackupConnected() => _backupConnectionValidForCurrentAccount();

  /// The connected backup account email on this device, if any.
  Future<String?> connectedBackupAccount() async => await backup?.connectedEmail();

  /// Defense in depth against cross-account leakage: a device connection is
  /// only usable by the account that created it. If a persisted connection
  /// belongs to a different account (e.g. a sign-out/switch hook was missed),
  /// it is disconnected here and treated as absent. Returns whether a valid
  /// connection for the current account exists.
  Future<bool> _backupConnectionValidForCurrentAccount() async {
    final provider = backup;
    if (provider == null) return false;
    if (!await provider.isDeviceConnected()) return false;
    final owner = await provider.connectedOwnerId();
    final current = currentAccountId?.call();
    if (owner != null && current != null && owner != current) {
      await provider.disconnect(); // stale connection from another account
      return false;
    }
    return true;
  }

  /// Imports a just-captured/picked file into durable local storage, registers
  /// it, and — if "Save to Photos" is on — copies it to the system gallery.
  /// Never touches the cloud provider. Returns the store-relative reference.
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
      object = await _copyToGallery(object);
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
  /// the backup provider — *only when a session is already live* (so it never
  /// prompts). On a second device the user connects once (in Storage & Sync),
  /// which establishes the session; then photos download on demand and cache.
  Future<File?> resolveOrFetch(String? ref) async {
    final local = await store.resolve(ref);
    if (local != null && await local.exists()) return local;
    if (ref == null || ref.isEmpty) return null;

    final provider = backup;
    if (provider == null || !provider.hasLiveSession) return null;

    MediaObject? object;
    try {
      object = await registry.getByRelativePath(ref);
    } catch (_) {
      return null;
    }
    final remoteId = object?.remoteId;
    if (remoteId == null) return null;

    try {
      final bytes = await provider.download(remoteId);
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

  /// Interactive connect to the backup provider (user-initiated). Tags the
  /// connection with the current account so it can't later be used by another.
  /// Returns whether it connected.
  Future<bool> connectBackup() async {
    final provider = backup;
    final owner = currentAccountId?.call();
    if (provider == null || owner == null) return false;
    return await provider.connect(ownerAccountId: owner) != null;
  }

  /// Disconnects the backup provider on this device — clears both the in-memory
  /// session and the persisted connection state. Called on sign-out / account
  /// switch, and when a stale cross-account connection is detected.
  Future<void> disconnectBackup() => backup?.disconnect() ?? Future.value();

  /// Uploads every not-yet-backed-up photo to the account's namespace.
  /// User-initiated ("Back up now"): may establish/restore the session. Returns
  /// how many were pushed (0 if the provider isn't connected on this device).
  Future<int> backupNow() async {
    final provider = backup;
    if (provider == null) return 0;
    // Never revive a connection that belongs to another account.
    if (!await _backupConnectionValidForCurrentAccount()) return 0;
    if (!provider.hasLiveSession && await provider.restoreSession() == null) return 0;

    final pending = await registry.pendingBackups();
    var pushed = 0;
    for (final object in pending) {
      if (object.remoteBackup == BackupState.done) continue;
      final file = await store.resolve(object.relativePath);
      if (file == null || !await file.exists()) continue; // nothing local to upload
      final remoteId = await provider.upload(
        file: file,
        fileName: p.posix.basename(object.relativePath),
        mimeType: object.mimeType,
        accountFolder: object.ownerUid, // per-account isolation
        replaceRemoteId: object.remoteId,
      );
      if (remoteId != null) {
        await registry.put(object.copyWith(remoteBackup: BackupState.done, remoteId: remoteId));
        pushed++;
      } else {
        await registry.put(object.copyWith(remoteBackup: BackupState.failed));
      }
    }
    return pushed;
  }

  /// Downloads every backed-up photo missing locally (e.g. a second device or
  /// after reinstall). User-initiated ("Sync"). Returns how many were fetched.
  Future<int> syncFromBackup() async {
    final provider = backup;
    if (provider == null) return 0;
    // Never revive a connection that belongs to another account.
    if (!await _backupConnectionValidForCurrentAccount()) return 0;
    if (!provider.hasLiveSession && await provider.restoreSession() == null) return 0;

    final all = await registry.getAll();
    var fetched = 0;
    for (final object in all) {
      final remoteId = object.remoteId;
      if (remoteId == null) continue;
      final local = await store.resolve(object.relativePath);
      if (local != null && await local.exists()) continue;
      final bytes = await provider.download(remoteId);
      if (bytes == null || bytes.isEmpty) continue;
      await store.writeBytes(object.relativePath, bytes);
      fetched++;
    }
    return fetched;
  }

  /// Copies to the device gallery and folds the outcome into the object's state.
  Future<MediaObject> _copyToGallery(MediaObject object) async {
    final target = galleryTarget;
    if (target == null) return object;
    bool ok;
    try {
      ok = await target.isConfigured() && await target.backup(object);
    } catch (_) {
      ok = false;
    }
    return object.copyWith(gallery: ok ? BackupState.done : BackupState.failed);
  }
}
