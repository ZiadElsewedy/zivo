import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  /// Which cloud account is on the other end of this device's connection, or
  /// null when there is none (or the connection predates account keys, in
  /// which case *unknown* is the honest answer and callers fall back to their
  /// pre-existing optimistic behaviour).
  ///
  /// This is the second half of isolation, and a deliberately different
  /// question from [_backupConnectionValidForCurrentAccount], which asks "may
  /// this ZIVO account use this device's connection?" and *fails closed by
  /// disconnecting*. This one only reads local state and has no side effects,
  /// because passive reads call it: tearing down a connection while rendering
  /// a photo grid is not something a read should ever do. The ZIVO-ownership
  /// gate still guards every path that actually talks to the provider.
  Future<String?> _connectedBackupAccountKey() async =>
      backup?.connectedAccountKey() ?? Future.value();

  /// Drops the read-side memoization. Called whenever the identity behind a
  /// reference can have changed — connect, disconnect, ZIVO account switch —
  /// because these caches are keyed by ref alone and would otherwise keep
  /// serving a previous account's answers (including its failure backoffs,
  /// which would make a freshly-connected account look broken for the next
  /// 15 seconds and suppress session restore for two minutes).
  void invalidateResolutionCaches() {
    _resolvedFiles.clear();
    _lastFetchFailure.clear();
    _lastSilentRestoreAttempt = null;
  }

  /// Imports a just-captured/picked file into durable local storage and
  /// returns the store-relative reference to embed in the owning entity.
  ///
  /// **Local-first**: this awaits the on-device copy and nothing else. The
  /// registry write, the optional "Save to Photos" copy and the cloud push
  /// all happen on a background tail ([_captureTail]) once the bytes are
  /// safe. That ordering is the point — the copy is a few milliseconds of
  /// disk, while the tail is two Firestore round trips and possibly a Drive
  /// upload, and a capture screen that awaited the lot read as the app
  /// freezing on Save. Nothing is lost by not waiting: the bytes are on disk,
  /// the ref is final, and the tail is best-effort by construction (a failed
  /// registry write leaves the photo intact and the next "Back up now"
  /// catches it).
  ///
  /// Tests that assert on the registry/gallery/backup must await
  /// [settleCaptures].
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
    // The ONLY thing on the caller's path: the durable local copy. Once this
    // returns, the photo is safe on disk and the ref is real — which is all
    // the capture screen needs to write its entity and pop.
    final stored = await store.importFile(sourcePath: sourcePath, kind: kind, id: id);
    _scheduleCaptureTail(
      id: id,
      ownerUid: ownerUid,
      kind: kind,
      stored: stored,
      source: source,
      capturedAt: capturedAt,
    );
    return stored.relativePath;
  }

  /// Per-id serialization of [_captureTail]. A capture → edit → save in
  /// quick succession issues two tails for the same id, and they must not
  /// interleave: two `registry.put`s racing on one record, or the second
  /// tail's "previous" read landing before the first tail's write, would
  /// leave the record describing bytes that aren't there. Chaining also gives
  /// [deleteMedia] something to wait on, so a delete can't be undone by a
  /// tail still in flight behind it.
  final Map<String, Future<void>> _captureTails = {};

  void _scheduleCaptureTail({
    required String id,
    required String ownerUid,
    required MediaKind kind,
    required StoredMedia stored,
    required CaptureSource source,
    required DateTime? capturedAt,
  }) {
    final queued = (_captureTails[id] ?? Future<void>.value()).then(
      (_) => _captureTail(
        id: id,
        ownerUid: ownerUid,
        kind: kind,
        stored: stored,
        source: source,
        capturedAt: capturedAt,
      ),
      // Never let one tail's failure poison the next capture of this id.
      onError: (Object _) {},
    );
    _captureTails[id] = queued;
    unawaited(
      queued.whenComplete(() {
        if (identical(_captureTails[id], queued)) _captureTails.remove(id);
      }),
    );
  }

  /// Everything after the bytes are safe: reconcile with any previous record
  /// for this id, clean an orphaned old path, copy to Photos if asked,
  /// register the metadata, and push to the cloud. All of it is bookkeeping
  /// the user is not waiting on — and two thirds of it is Firestore round
  /// trips, which is exactly what used to make Save on a photo feel like the
  /// app had frozen.
  Future<void> _captureTail({
    required String id,
    required String ownerUid,
    required MediaKind kind,
    required StoredMedia stored,
    required CaptureSource source,
    required DateTime? capturedAt,
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

    // Everything below is best-effort and must never lose the photo.
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
  }

  /// Completes once every capture's background tail has settled.
  ///
  /// For **tests** (and nothing else): [capture] now returns at the local
  /// copy, so a test that asserts on the registry, the gallery target, or the
  /// backup provider has to wait for the tail that writes them.
  @visibleForTesting
  Future<void> settleCaptures() async {
    while (_captureTails.isNotEmpty) {
      await Future.wait(_captureTails.values.toList());
    }
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

    // A file id is a location inside ONE cloud account. If this device is
    // connected to a different one, the bytes are not lost — they simply are
    // not here, and no retry will change that — so say `otherAccount` instead
    // of firing a request the wrong account can only 404, then reporting
    // `cloudOnly` ("on its way") about bytes that are never coming.
    final connectedKey = await _connectedBackupAccountKey();
    if (connectedKey != null && !object!.isRemoteReachableFrom(connectedKey)) {
      return const MediaResolution(MediaAvailability.otherAccount);
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
        _fetches.putIfAbsent(ref, () => _downloadToStore(ref, object!));
    final outcome = await fetch;
    final fetched = _resolvedFiles[ref];
    if (fetched != null && await fetched.exists()) {
      return MediaResolution(MediaAvailability.onDevice, file: fetched);
    }
    // The fetch's own verdict, not a blanket `cloudOnly`: a copy the provider
    // confirmed is gone must not be reported as arriving, or the tile pulses
    // for a file that no longer exists.
    return MediaResolution(
      outcome == MediaAvailability.onDevice
          ? MediaAvailability.cloudOnly
          : outcome,
    );
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
  final Map<String, Future<MediaAvailability>> _fetches = {};
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

  /// Fetches one ref's bytes and reports what the attempt established:
  /// [MediaAvailability.onDevice] on success, [MediaAvailability.nowhere] when
  /// the provider confirmed the remote copy is gone (the dead reference is
  /// dropped and the record re-enters the backup work list), and
  /// [MediaAvailability.cloudOnly] for everything transient.
  Future<MediaAvailability> _downloadToStore(String ref, MediaObject object) async {
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
      final provider = backup!;
      // Re-read the live account here, not at queue time: this fetch may have
      // waited behind three others while the user changed accounts.
      final live = provider.liveAccountKey;
      final expected = object.remoteAccountKey ?? live;
      if (live == null || expected != live) throw const _FetchUnavailable();

      // `expected == live` here, and `live` is the promoted non-null one.
      final fetched =
          await provider.download(object.remoteId!, expectedAccountKey: live);

      // The copy is confirmed gone — the user deleted it from Drive, or it was
      // purged from the trash. Drop the dead reference so reads stop promising
      // bytes that will never arrive, and mark the record outstanding so any
      // device that still holds the local file re-uploads it on the next
      // backup. That is the whole recovery path: nothing else can restore it.
      if (fetched.gone) {
        await _forgetRemoteCopy(object);
        return MediaAvailability.nowhere;
      }

      if (!fetched.hasBytes) throw const _FetchUnavailable();
      final file = await store.writeBytes(ref, fetched.data!);
      _rememberResolved(ref, file);
      _lastFetchFailure.remove(ref);

      // Lazy migration: a record written before account keys existed just
      // proved which account holds it. Stamp it, and it never has to be
      // guessed about again. Best-effort — the bytes are already safe.
      if (object.remoteAccountKey == null) {
        unawaited(_stampRemoteAccount(object, live));
      }
      return MediaAvailability.onDevice;
    } catch (_) {
      _lastFetchFailure[ref] = DateTime.now();
      return MediaAvailability.cloudOnly;
    } finally {
      _activeFetches--;
      _fetches.remove(ref);
      if (_fetchWaiters.isNotEmpty) {
        _fetchWaiters.removeAt(0).complete();
      }
    }
  }

  /// Drops a remote reference the provider has confirmed is gone, and puts the
  /// record back on the backup work list.
  ///
  /// Clearing the id is the point: keeping it would leave every later read
  /// dereferencing a file that does not exist, and — because the record still
  /// claimed [BackupState.done] — `pendingBackups` would keep skipping the one
  /// operation that could restore it. [BackupState.failed] with no id is the
  /// honest description of "we had a copy, it is gone, push it again from
  /// whichever device still has the bytes".
  Future<void> _forgetRemoteCopy(MediaObject object) async {
    try {
      final latest = await registry.get(object.id) ?? object;
      // Something re-uploaded while this fetch was in flight; that newer
      // reference is not the one we just proved dead.
      if (latest.remoteId != object.remoteId) return;
      await registry.put(
        latest.copyWith(remoteBackup: BackupState.failed, clearRemote: true),
      );
    } catch (_) {
      // Best-effort: the read still reports `nowhere`, so nothing pulses.
    }
  }

  /// Records which cloud account a legacy reference turned out to live in.
  /// Reads the freshest record first so a concurrent capture/backup is not
  /// clobbered by a stale copy.
  Future<void> _stampRemoteAccount(MediaObject object, String accountKey) async {
    try {
      final latest = await registry.get(object.id) ?? object;
      if (latest.remoteId != object.remoteId) return; // moved on; leave it
      if (latest.remoteAccountKey != null) return;
      await registry.put(latest.copyWith(remoteAccountKey: accountKey));
    } catch (_) {
      // Best-effort backfill.
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

      // Capture which account we are pushing to BEFORE the upload, and refuse
      // to record anything if it changed underneath us. Reading "the current
      // account" after the await would attribute this file to whichever
      // account the user happened to connect while the bytes were in flight.
      final startedWith = provider.liveAccountKey;
      if (startedWith == null) return;

      final remoteId = await provider.upload(
        file: file,
        fileName: p.posix.basename(object.relativePath),
        mimeType: object.mimeType,
        accountFolder: object.ownerUid, // per-ZIVO-account isolation
        replaceRemoteId: object.remoteId,
        replaceInAccountKey: object.remoteAccountKey,
      );
      if (remoteId == null) return;
      if (provider.liveAccountKey != startedWith) return; // switched mid-flight

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
          target.copyWith(
            remoteBackup: BackupState.done,
            remoteId: remoteId,
            remoteAccountKey: startedWith,
          ),
        );
      } else {
        // Newer bytes exist locally; leave the push pending, but remember the
        // location so the next one can update in place instead of duplicating.
        await registry.put(
          target.remoteId == null
              ? target.copyWith(remoteId: remoteId, remoteAccountKey: startedWith)
              : target,
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
    // A capture's background tail may still be on its way to registering
    // this id. Let it land first, or its `registry.put` would resurrect the
    // record we are about to remove.
    try {
      await _captureTails[id];
    } catch (_) {
      // A failed tail is not a reason to refuse the delete.
    }
    var idToDelete = remoteId;
    String? idAccountKey;
    if (backup?.hasLiveSession == true) {
      try {
        final record = await registry.get(id);
        idToDelete ??= record?.remoteId;
        idAccountKey = record?.remoteAccountKey;
      } catch (_) {
        // Registry unavailable — fall back to whatever the caller passed.
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
    // Only the account that holds the file can delete it. When the copy lives
    // in an account the user has since disconnected, the delete is skipped —
    // deleting by id against the wrong account would at best fail and at worst
    // hit an unrelated file there.
    final deleteIn = idAccountKey ?? provider?.liveAccountKey;
    if (idToDelete != null &&
        provider != null &&
        provider.hasLiveSession &&
        deleteIn != null &&
        deleteIn == provider.liveAccountKey) {
      try {
        await provider.deleteRemote(idToDelete, expectedAccountKey: deleteIn);
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
    final connected = await provider.connect(ownerAccountId: owner) != null;
    // Whatever this device could and couldn't resolve a moment ago was an
    // answer about a different account.
    invalidateResolutionCaches();
    return connected;
  }

  /// Disconnects the backup provider on this device — clears both the in-memory
  /// session and the persisted connection state. Called on sign-out / account
  /// switch, and when a stale cross-account connection is detected.
  Future<void> disconnectBackup() async {
    invalidateResolutionCaches();
    await backup?.disconnect();
  }

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

    // The destination this run is pushing to. Everything below is relative to
    // it: a photo already backed up to a DIFFERENT cloud account still needs
    // backing up here, which is what makes connecting a new account re-protect
    // the existing library instead of reporting "everything is already backed
    // up" over a destination that holds nothing.
    final accountKey = provider.liveAccountKey;
    final pending = await registry.pendingBackups(forAccountKey: accountKey);
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
      // Re-check every iteration, not once at the top: a long run can outlive
      // the account it started against, and half a run's ids attributed to the
      // wrong account is worse than a run that stops.
      if (provider.liveAccountKey != accountKey) break;

      final remoteId = await provider.upload(
        file: file,
        fileName: p.posix.basename(object.relativePath),
        mimeType: object.mimeType,
        accountFolder: object.ownerUid, // per-ZIVO-account isolation
        replaceRemoteId: object.remoteId,
        replaceInAccountKey: object.remoteAccountKey,
      );
      if (remoteId != null) {
        await registry.put(object.copyWith(
          remoteBackup: BackupState.done,
          remoteId: remoteId,
          remoteAccountKey: accountKey,
        ));
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

    // Resolve the missing-locally candidates first so progress has a real
    // total — and count only what THIS account can actually serve, so the
    // progress bar doesn't promise photos that live in an account the user
    // disconnected.
    final accountKey = provider.liveAccountKey;
    final all = await registry.getAll();
    final missing = <MediaObject>[];
    for (final object in all) {
      if (object.remoteId == null) continue;
      if (accountKey != null && !object.isRemoteReachableFrom(accountKey)) continue;
      final local = await store.resolve(object.relativePath);
      if (local != null && await local.exists()) continue;
      missing.add(object);
    }

    final total = missing.length;
    var done = 0;
    onProgress?.call(done, total);
    var fetched = 0;
    for (final object in missing) {
      final expected = object.remoteAccountKey ?? accountKey;
      if (expected == null || expected != provider.liveAccountKey) {
        onProgress?.call(++done, total);
        continue;
      }
      final result =
          await provider.download(object.remoteId!, expectedAccountKey: expected);
      if (result.gone) {
        // Same treatment as a failed passive read: drop the dead reference so
        // this Sync — and every later one — stops asking for a file Drive has
        // already told us is not there.
        await _forgetRemoteCopy(object);
      } else if (result.hasBytes) {
        await store.writeBytes(object.relativePath, result.data!);
        if (object.remoteAccountKey == null) {
          await _stampRemoteAccount(object, expected);
        }
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
