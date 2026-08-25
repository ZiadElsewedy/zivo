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
/// Isolation: uploads go into a per-account namespace ([accountFolder]) so two
/// ZIVO accounts sharing one cloud account never mix.
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

  /// Uploads [file] into the account's namespace ([accountFolder]). When
  /// [replaceRemoteId] is given, updates that remote file in place. Returns the
  /// remote id, or null on failure.
  Future<String?> upload({
    required File file,
    required String fileName,
    required String mimeType,
    required String accountFolder,
    String? replaceRemoteId,
  });

  /// Downloads a backed-up file's bytes by its remote id. Requires a live
  /// session (caller ensures it). Returns null on failure.
  Future<List<int>?> download(String remoteId);

  /// Deletes the remote copy for [remoteId] (best-effort). Requires a live
  /// session (caller ensures it). Returns whether the deletion succeeded —
  /// a null/failed result leaves the remote copy in place (safe to retry via
  /// another backup/delete cycle), never corrupting anything local.
  Future<bool> deleteRemote(String remoteId);
}
