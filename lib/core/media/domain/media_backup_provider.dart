import 'dart:io';

/// A connected cloud account for backup — just the identity bits the UI shows.
/// Credentials/tokens live inside the provider, never here.
class BackupAccount {
  const BackupAccount({required this.id, required this.email});

  final String id;
  final String email;
}

/// The provider-agnostic seam for remote media backup + restore. Google Drive
/// is one implementation; a future provider (iCloud, Dropbox, …) implements the
/// same interface and is injected in its place — the `MediaService`, Moments,
/// and the rest of the media layer never change.
///
/// Critical contract: the provider's auth is engaged only from **user-initiated**
/// actions ([connect], [restoreSession], and the uploads/downloads they drive).
/// Passive flows (opening Moments, taking a photo) must gate on [hasLiveSession]
/// — a pure in-memory check that never shows a sign-in prompt. This keeps
/// day-to-day use silent.
///
/// Connection is **per device**: [isDeviceConnected] is persisted locally, kept
/// separate from account-level (Firestore) preferences, so a device that never
/// connected is never nagged to authenticate.
///
/// Isolation runs on two independent axes, and both are enforced here:
///
/// - **ZIVO account → cloud account.** Uploads go into a per-account namespace
///   ([accountFolder]) so two ZIVO accounts sharing one cloud account never
///   mix, and [connectedOwnerId] lets the service reject a connection made by
///   a different ZIVO account.
/// - **Remote reference → cloud account.** A provider file id is a location
///   inside ONE cloud account, so every method that dereferences one takes the
///   account key it was minted in and refuses when the live session belongs to
///   a different account. Putting that check at the seam rather than at each
///   call site is deliberate: a caller cannot forget it, and a cloud account
///   swapped mid-flight fails loudly instead of writing a reference nothing
///   can resolve later.
abstract interface class MediaBackupProvider {
  /// Interactive connect on this device: authenticates + authorizes and
  /// persists the connection, tagged with the [ownerAccountId] (the ZIVO
  /// account connecting it). Returns the account, or null if cancelled/failed.
  Future<BackupAccount?> connect({required String ownerAccountId});

  /// Disconnects: clears this device's connection (in-memory session AND
  /// persisted state) and signs out.
  Future<void> disconnect();

  /// Whether an authorized session is live in memory right now — a pure,
  /// synchronous check that never touches the provider SDK.
  bool get hasLiveSession;

  /// The stable account key of the live session, or null when none is live.
  /// Synchronous and side-effect free, so it is safe to capture at the start
  /// of an async operation and re-check at its end.
  ///
  /// "Stable" excludes the email: providers let users rename and reuse those.
  /// Google Drive uses the Google account id.
  String? get liveAccountKey;

  /// The stable account key persisted for this device's connection, or null.
  /// Available without a live session (it is local state), which is what lets
  /// a passive read decide whether a stored reference is reachable *here*
  /// without triggering any authentication.
  Future<String?> connectedAccountKey();

  /// Whether this device was previously connected (persisted). For status UI.
  Future<bool> isDeviceConnected();

  /// The connected account email on this device, if any.
  Future<String?> connectedEmail();

  /// The ZIVO account uid that connected this device, or null — used to reject
  /// a stale connection after a sign-out / account switch.
  Future<String?> connectedOwnerId();

  /// Restores a prior session (may briefly show native auth UI). Call ONLY from
  /// user-initiated actions (Back up now / Sync).
  Future<BackupAccount?> restoreSession();

  /// Uploads [file] into the account's namespace ([accountFolder]). Returns
  /// the remote id, or null on failure.
  ///
  /// [replaceRemoteId] is an *optimisation*, never a requirement: when the id
  /// is given and [replaceInAccountKey] matches the live session's account,
  /// the file is updated in place (no duplicate next to an orphan). When the
  /// key differs, or the update fails because the file is gone, the upload
  /// falls back to creating a new file — an id from another account must never
  /// turn a re-upload into a permanent failure.
  Future<String?> upload({
    required File file,
    required String fileName,
    required String mimeType,
    required String accountFolder,
    String? replaceRemoteId,
    String? replaceInAccountKey,
  });

  /// Downloads a backed-up file's bytes by its remote id. Requires a live
  /// session (caller ensures it). Returns null on failure.
  ///
  /// [expectedAccountKey] is the account [remoteId] was minted in; the call is
  /// refused without touching the network when the live session belongs to a
  /// different account, so a stale reference can never be silently resolved
  /// against whichever account happens to be connected now.
  Future<List<int>?> download(String remoteId, {required String expectedAccountKey});

  /// Deletes the remote copy for [remoteId] (best-effort). Requires a live
  /// session (caller ensures it). Returns whether the deletion succeeded —
  /// a null/failed result leaves the remote copy in place (safe to retry via
  /// another backup/delete cycle), never corrupting anything local.
  ///
  /// [expectedAccountKey] guards the same way it does for [download]: deleting
  /// by an id minted elsewhere would at best fail and at worst hit an
  /// unrelated file in the connected account.
  Future<bool> deleteRemote(String remoteId, {required String expectedAccountKey});
}
