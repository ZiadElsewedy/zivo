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
  /// only usable by the exact account that created it. Fail-closed — the
  /// connection is valid *only* when its recorded owner equals the current
  /// account. A different owner, an unknown owner (`null`, e.g. a connection
  /// made before owner tracking existed), or no current account all cause the
  /// persisted/in-memory connection to be cleared and rejected. (A pre-existing
  /// unowned connection therefore requires the user to reconnect once — by
  /// design.) Returns whether a valid connection for the current account exists.
  Future<bool> _backupConnectionValidForCurrentAccount() async {
    final provider = backup;
    if (provider == null) return false;
    if (!await provider.isDeviceConnected()) return false;
    final owner = await provider.connectedOwnerId();
    final current = currentAccountId?.call();
    if (owner == null || current == null || owner != current) {
      await provider.disconnect(); // unknown or foreign owner — clear it
      return false;
    }
    return true;
  }

  /// Imports a just-captured/picked file into durable local storage, registers
  /// it, and — if "Save to Photos" is on — copies it to the system gallery.
  /// Never touches the cloud provider. Returns the store-relative reference.
  ///
  /// Re-importing over an existing id (an EDITED photo — same entity, new
  /// bytes) deliberately carries the previous record's [MediaObject.remoteId]
  /// forward: the bytes changed, so the entry flips back to
  /// [BackupState.pending] (the next "Back up now" must push the new bytes),
  /// but keeping the remote id makes that push an in-place Drive UPDATE
  /// instead of a duplicate file next to an orphaned old copy.
  Future<String> capture({
    required String sourcePath,
    required MediaKind kind,
    required String id,
    required String ownerUid,
    CaptureSource source = CaptureSource.unknown,
    DateTime? capturedAt,
  }) async {
    // Carry forward what a previous capture of THIS id already established
    // (its remote file identity, its gallery outcome) so editing a photo
    // never orphans or duplicates its backed-up copy. Best-effort: a registry
    // read failure just means a fresh record.
    MediaObject? previous;
    try {
      previous = await registry.get(id);
    } catch (_) {
      previous = null;
    }

    final stored = await store.importFile(sourcePath: sourcePath, kind: kind, id: id);

    // A re-import that landed on a DIFFERENT path (the picked file's
    // extension differs from the stored one, e.g. .jpg → .png) would orphan
    // the old bytes under the registry's now-replaced path — remove them so
    // edits never accumulate hidden copies on disk. Same path = the import
    // overwrote in place; nothing to clean.
    if (previous?.relativePath != null && previous!.relativePath != stored.relativePath) {
      try {
        await store.delete(previous.relativePath);
      } catch (_) {
        // Best-effort.
      }
    }

    // Local copy done — everything below is best-effort and must never lose the
    // photo or block the owning feature from saving.
    MediaStoragePreferences prefs;
    try {
      prefs = await preferences.read();
    } catch (_) {
      prefs = MediaStoragePreferences.defaults;
    }

    final replacedRemoteId = previous?.remoteId;

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
      gallery: previous?.gallery ?? BackupState.pending,
      // Bytes changed (or first capture) — the cloud copy, if any, is stale
      // until the next backup pushes these bytes over it.
      remoteBackup: BackupState.pending,
      remoteId: replacedRemoteId,
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
  /// the backup provider — *only when a session is already live, or can be
  /// silently restored* (see [_ensureSilentSession]). On a second device the
  /// user connects once (in Storage & Sync); after that, photos download on
  /// demand and cache — opening Moments on a fresh device resolves its
  /// synced metadata against Drive automatically, with no sign-in prompt.
  Future<File?> resolveOrFetch(String? ref) async {
    final local = await store.resolve(ref);
    if (local != null && await local.exists()) return local;
    if (ref == null || ref.isEmpty) return null;

    final provider = backup;
    if (provider == null) return null;
    if (!await _ensureSilentSession()) return null;

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

  /// True when a backup session is live when this returns. A live session
  /// short-circuits true; otherwise — and ONLY when this device has a
  /// persisted connection owned by the CURRENT account — attempts a silent
  /// restore (`attemptLightweightAuthentication`, no sign-in sheet), so a
  /// freshly-reinstalled/second device that already connected once resumes
  /// its session invisibly instead of leaving every photo stuck on a
  /// placeholder until the user finds Storage & Sync.
  ///
  /// Throttled to one attempt per app run per cooldown window: passive reads
  /// must never hammer the auth SDK, and repeated failures (offline, revoked)
  /// degrade to exactly the old "placeholder until manual connect" behavior.
  Future<bool> _ensureSilentSession() async {
    final provider = backup;
    if (provider == null) return false;
    if (provider.hasLiveSession) return true;

    final now = DateTime.now();
    if (_lastSilentRestoreAttempt != null &&
        now.difference(_lastSilentRestoreAttempt!) < _silentRestoreCooldown) {
      return false;
    }
    _lastSilentRestoreAttempt = now;

    // Same ownership gate as every other provider use: never revive a
    // connection that belongs to another account.
    if (!await _backupConnectionValidForCurrentAccount()) return false;
    try {
      return await provider.restoreSession() != null;
    } catch (_) {
      return false;
    }
  }

  DateTime? _lastSilentRestoreAttempt;

  /// How long a failed silent-restore blocks further background attempts.
  /// Short enough that transient offline starts recover within the same
  /// browsing session; long enough that a gallery scroll fires at most one.
  static const _silentRestoreCooldown = Duration(minutes: 2);

  /// Deletes a piece of media everywhere it lives: the local file, its
  /// registry entry, and — best-effort, when one exists — its cloud backup
  /// copy. Deleting the OWNING entity without this would leave orphaned
  /// bytes accumulating locally and in Drive forever.
  ///
  /// [remoteId] may be passed by callers that already hold the registry
  /// record; otherwise it's looked up before the entry is removed. The local
  /// delete always happens; cloud deletion is best-effort (a failure leaves
  /// the remote copy for a later cleanup rather than blocking anything).
  Future<void> deleteMedia({required String id, required String? ref, String? remoteId}) async {
    var idToDelete = remoteId;
    if (idToDelete == null && backup?.hasLiveSession == true) {
      try {
        idToDelete = (await registry.get(id))?.remoteId;
      } catch (_) {
        idToDelete = null;
      }
    }
    await store.delete(ref);
    try {
      await registry.remove(id);
    } catch (_) {
      // Registry is metadata; the user asked for deletion and the file is
      // gone — never surface a failure here.
    }
    final provider = backup;
    if (idToDelete != null && provider != null && provider.hasLiveSession) {
      try {
        await provider.deleteRemote(idToDelete);
      } catch (_) {
        // Best-effort: an un-deletable remote copy is harmless (it sits in
        // the account's own folder; re-uploading under the same id replaces
        // it).
      }
    }
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
  ///
  /// [onProgress] (optional) is called as the run advances — `(done, total)`,
  /// where `total` is how many photos need uploading and `done` counts those
  /// finished so far — so the UI can show live "backing up 3 of 10" feedback.
  /// It fires once with `(0, total)` before the first upload, then after each.
  Future<int> backupNow({void Function(int done, int total)? onProgress}) async {
    final provider = backup;
    if (provider == null) return 0;
    // Never revive a connection that belongs to another account.
    if (!await _backupConnectionValidForCurrentAccount()) return 0;
    if (!provider.hasLiveSession && await provider.restoreSession() == null) return 0;

    final pending = (await registry.pendingBackups())
        .where((o) => o.remoteBackup != BackupState.done)
        .toList();
    final total = pending.length;
    var done = 0;
    onProgress?.call(done, total);
    var pushed = 0;
    for (final object in pending) {
      final file = await store.resolve(object.relativePath);
      if (file == null || !await file.exists()) {
        onProgress?.call(++done, total); // nothing local to upload — still advance
        continue;
      }
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
      onProgress?.call(++done, total);
    }
    return pushed;
  }

  /// Downloads every backed-up photo missing locally (e.g. a second device or
  /// after reinstall). User-initiated ("Sync"). Returns how many were fetched.
  ///
  /// [onProgress] (optional) reports `(done, total)` as the run advances, where
  /// `total` is how many backed-up photos are missing locally — so the UI can
  /// show live "downloading 3 of 10" feedback. It fires once with `(0, total)`
  /// before the first download, then after each candidate.
  Future<int> syncFromBackup({void Function(int done, int total)? onProgress}) async {
    final provider = backup;
    if (provider == null) return 0;
    // Never revive a connection that belongs to another account.
    if (!await _backupConnectionValidForCurrentAccount()) return 0;
    if (!provider.hasLiveSession && await provider.restoreSession() == null) return 0;

    // Resolve the missing-locally candidates first so progress has a real total.
    final all = await registry.getAll();
    final missing = <MediaObject>[];
    for (final object in all) {
      if (object.remoteId == null) continue;
      final local = await store.resolve(object.relativePath);
      if (local != null && await local.exists()) continue;
      missing.add(object);
    }

    final total = missing.length;
    var done = 0;
    onProgress?.call(done, total);
    var fetched = 0;
    for (final object in missing) {
      final bytes = await provider.download(object.remoteId!);
      if (bytes != null && bytes.isNotEmpty) {
        await store.writeBytes(object.relativePath, bytes);
        fetched++;
      }
      onProgress?.call(++done, total);
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
