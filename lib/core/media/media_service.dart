import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'domain/media_backup_provider.dart';
import 'domain/media_backup_target.dart';
import 'domain/media_kind.dart';
import 'domain/media_object.dart';
import 'domain/media_registry.dart';
import 'domain/media_resolution.dart';
import 'domain/media_store.dart';
import 'domain/media_storage_preferences.dart';

/// The single entry point features use for media. It hides *where* bytes go:
/// callers hand it a captured file and get back a durable reference to embed in
/// their entity; the service copies the bytes into the local [MediaStore],
/// records a [MediaObject] in the [MediaRegistry], and — only if the account
/// opted in — copies to the system Photos ([galleryTarget]).
///
/// Cloud backup is provider-agnostic ([MediaBackupProvider]) and
/// **device-local + prompt-free**: a capture uploads to Drive immediately when
/// this account has auto-upload on (default) and this device can restore its
/// session silently — otherwise it waits for the user-initiated [backupNow].
/// Passive reads ([resolveWithStatus]) fetch only when a session is already
/// live or silently restorable, so opening Moments or taking a photo never
/// triggers a sign-in prompt. Swapping in a different provider (iCloud,
/// Dropbox) touches only the composition root, not this service or the
/// features.
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

    // Sync immediately, not at the next "Back up now": when this account
    // opted into auto-upload and this device can speak to Drive without a
    // prompt, push the fresh bytes right away — fire-and-forget, never
    // blocking the save or surfacing errors here (manual backup remains the
    // fallback that catches anything this misses).
    if (prefs.autoUploadToDrive) _scheduleAutoUpload(object);
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
  ///
  /// All callers should prefer [resolveWithStatus] — this is its
  /// bytes-or-null projection, kept for callers that only care about bytes.
  Future<File?> resolveOrFetch(String? ref) async =>
      (await resolveWithStatus(ref)).file;

  /// The full-resolution read: where the bytes are, and what a missing-bytes
  /// state honestly means. See [MediaAvailability] for the three outcomes.
  ///
  /// Performance contract for grid-scale callers: successful resolutions are
  /// memoized (one disk stat per ref per process), identical in-flight
  /// fetches are shared (a gallery of 50 cloud-only tiles collapses to at
  /// most [_maxParallelFetches] simultaneous downloads), and failed fetches
  /// back off instead of re-hammering Drive on every tile rebuild.
  Future<MediaResolution> resolveWithStatus(String? ref) async {
    if (ref == null || ref.isEmpty) {
      return const MediaResolution(MediaAvailability.nowhere);
    }

    final cached = _resolvedFiles[ref];
    if (cached != null && await cached.exists()) {
      return MediaResolution(MediaAvailability.onDevice, file: cached);
    }

    final local = await store.resolve(ref);
    if (local != null && await local.exists()) {
      _rememberResolved(ref, local);
      return MediaResolution(MediaAvailability.onDevice, file: local);
    }

    final provider = backup;
    if (provider == null) {
      return const MediaResolution(MediaAvailability.nowhere);
    }

    // Whether the bytes are *fetchable* is registry knowledge, and the
    // registry is Firestore-backed metadata — it answers even with no live
    // session. A record without a remote id was never backed up anywhere:
    // no download could succeed, so report `nowhere` rather than pretending
    // a retry might help.
    MediaObject? object;
    try {
      object = await registry.getByRelativePath(ref);
    } catch (_) {
      return const MediaResolution(MediaAvailability.nowhere);
    }
    final remoteId = object?.remoteId;
    if (remoteId == null) {
      return const MediaResolution(MediaAvailability.nowhere);
    }

    // Fetchable — join any in-flight fetch of this ref, or start one through
    // the throttle. A recent failure skips the attempt entirely (backoff):
    // the caller gets `cloudOnly`, which reads as "on its way", not an error.
    if (_isBackingOff(ref)) {
      return const MediaResolution(MediaAvailability.cloudOnly);
    }
    // putIfAbsent runs its closure synchronously, so concurrent callers of
    // the same ref always share ONE future — no isolate-level lock needed.
    final fetch =
        _fetches.putIfAbsent(ref, () => _downloadToStore(ref, remoteId));
    await fetch;
    final fetched = _resolvedFiles[ref];
    if (fetched != null && await fetched.exists()) {
      return MediaResolution(MediaAvailability.onDevice, file: fetched);
    }
    return const MediaResolution(MediaAvailability.cloudOnly);
  }

  // ---- Resolution pipeline internals --------------------------------------

  /// Successfully resolved refs → their files. Bounded; files are just paths,
  /// so the limit is generous. Failed resolutions are NOT cached here — they
  /// live in [_lastFetchFailure] under a short backoff instead, so recovery
  /// (network returns, Drive reconnects) happens automatically.
  final Map<String, File> _resolvedFiles = {};

  /// Shared in-flight downloads keyed by ref. Map operations between awaits
  /// are atomic within an isolate, so concurrent callers always observe a
  /// consistent view without an explicit lock.
  final Map<String, Future<void>> _fetches = {};
  int _activeFetches = 0;
  final List<Completer<void>> _fetchWaiters = [];

  /// How many Drive downloads may run at once. A gallery scroll must feel
  /// instant, not saturate the radio — three keeps visible tiles filling
  /// quickly while capping contention.
  static const _maxParallelFetches = 3;

  final Map<String, DateTime> _lastFetchFailure = {};

  /// How long a failed download of one ref waits before another attempt.
  /// Short enough that toggling a plane-mode switch recovers within a browse;
  /// long enough that rapid grid rebuilds don't retry per frame. Public so
  /// read-side widgets can align their self-retry timers with it.
  static const fetchFailureBackoff = Duration(seconds: 15);
  static const _fetchFailureBackoff = fetchFailureBackoff;

  /// Upper bound on memoized successes — evicting oldest-inserted is fine;
  /// a re-evicted ref costs one cheap disk stat to warm again.
  static const _resolvedCacheLimit = 512;

  void _rememberResolved(String ref, File file) {
    if (_resolvedFiles.length >= _resolvedCacheLimit) {
      _resolvedFiles.remove(_resolvedFiles.keys.first);
    }
    _resolvedFiles[ref] = file;
  }

  bool _isBackingOff(String ref) {
    final last = _lastFetchFailure[ref];
    return last != null &&
        DateTime.now().difference(last) < _fetchFailureBackoff;
  }

  Future<void> _downloadToStore(String ref, String remoteId) async {
    // Respect the parallelism cap: beyond it, waiters queue FIFO and proceed
    // as slots free up.
    if (_activeFetches >= _maxParallelFetches) {
      final waiter = Completer<void>();
      _fetchWaiters.add(waiter);
      await waiter.future;
    }
    _activeFetches++;
    try {
      if (!await _ensureSilentSession()) throw const _FetchUnavailable();
      final bytes = await backup!.download(remoteId);
      if (bytes == null || bytes.isEmpty) throw const _FetchUnavailable();
      final file = await store.writeBytes(ref, bytes);
      _rememberResolved(ref, file);
      _lastFetchFailure.remove(ref);
    } catch (_) {
      _lastFetchFailure[ref] = DateTime.now();
    } finally {
      _activeFetches--;
      _fetches.remove(ref);
      if (_fetchWaiters.isNotEmpty) {
        _fetchWaiters.removeAt(0).complete();
      }
    }
  }

  // ---- Immediate auto-upload on capture ------------------------------------

  /// Ids with an auto-upload currently running — a rapid capture→edit→save
  /// sequence must not stack two uploads of the same id racing each other.
  final Set<String> _autoUploadsInFlight = {};

  /// Fire-and-forget push of a fresh capture to Drive. Every gate is silent:
  /// no connection, no restorable session, or the user turned auto-upload off
  /// simply means "not now" — the manual "Back up now" flow remains complete
  /// fallback coverage. Never throws.
  void _scheduleAutoUpload(MediaObject object) {
    if (!_autoUploadsInFlight.add(object.id)) return;
    unawaited(_autoUpload(object));
  }

  Future<void> _autoUpload(MediaObject object) async {
    final id = object.id;
    try {
      final provider = backup;
      if (provider == null) return;
      if (!await _backupConnectionValidForCurrentAccount()) return;
      if (!provider.hasLiveSession) {
        if (!await _ensureSilentSession()) return;
      }
      final file = await store.resolve(object.relativePath);
      if (file == null || !await file.exists()) return;
      final remoteId = await provider.upload(
        file: file,
        fileName: p.posix.basename(object.relativePath),
        mimeType: object.mimeType,
        accountFolder: object.ownerUid, // per-account isolation
        replaceRemoteId: object.remoteId,
      );
      if (remoteId == null) return;

      // Patch ONLY the backup fields onto the freshest record: the user may
      // have edited/re-captured while the upload ran. If those newer bytes
      // differ from what was just pushed, leave remoteBackup pending so the
      // next backup pushes them — marking done would be a lie.
      MediaObject? latest;
      try {
        latest = await registry.get(id);
      } catch (_) {
        latest = null;
      }
      final target = latest ?? object;
      final pushedBytesAreCurrent =
          latest == null || latest.contentHash == object.contentHash;
      if (pushedBytesAreCurrent) {
        await registry.put(
          target.copyWith(remoteBackup: BackupState.done, remoteId: remoteId),
        );
      } else {
        await registry.put(
          target.copyWith(remoteId: target.remoteId ?? remoteId),
        );
      }
    } catch (_) {
      // Deliberately swallowed — see the doc on [_scheduleAutoUpload].
    } finally {
      _autoUploadsInFlight.remove(id);
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

/// Internal signal that a cloud fetch couldn't proceed (no session, empty
/// response, provider error) — caught by [_downloadToStore] to start the
/// ref's backoff. Never escapes the service.
final class _FetchUnavailable implements Exception {
  const _FetchUnavailable();
}
