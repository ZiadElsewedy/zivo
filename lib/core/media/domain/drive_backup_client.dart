import 'dart:io';

/// A connected Google account for Drive backup — just the identity bits the UI
/// shows. The OAuth tokens live inside the client, never here.
class DriveAccount {
  const DriveAccount({required this.id, required this.email});

  final String id;
  final String email;
}

/// The seam between the app and Google Drive. Wraps the OAuth dance and the
/// upload/download, so the rest of the media pipeline depends only on this
/// interface and can be tested with a fake.
///
/// Crucial contract: the Google SDK is only ever engaged from **user-initiated**
/// actions — [connect], [restoreSession] (from Back up now / Sync), [uploadImage]
/// and [download] (invoked by those). Passive flows (opening Moments, taking a
/// photo) must gate on [hasLiveSession], which is a pure in-memory check and
/// never shows a sign-in prompt. This is what keeps day-to-day use silent.
///
/// `drive.file` means the app only sees files it created; uploads go into a
/// per-account subfolder (`ZIVO/{accountFolder}`) so two ZIVO accounts sharing
/// one Google Drive never mix.
abstract interface class DriveBackupClient {
  /// Interactive connect: signs into Google if needed and authorizes the
  /// `drive.file` scope, persisting the connection for this device. Returns the
  /// account, or null if cancelled/failed. User-initiated only.
  Future<DriveAccount?> connect();

  /// Disconnects: clears this device's connection and signs out of the session.
  Future<void> disconnect();

  /// Whether an authorized session is live in memory right now — a pure,
  /// synchronous check that never touches the SDK. Passive flows gate on this.
  bool get hasLiveSession;

  /// Whether this device was previously connected (persisted). For status UI.
  Future<bool> isDeviceConnected();

  /// The connected Google account email on this device, if any.
  Future<String?> connectedEmail();

  /// Restores a prior session (may briefly show the native account UI on some
  /// platforms). Call ONLY from user-initiated actions (Back up now / Sync).
  Future<DriveAccount?> restoreSession();

  /// Uploads [file] into the account's Drive subfolder (`ZIVO/{accountFolder}`).
  /// When [replaceFileId] is given, updates that file in place. Returns the
  /// Drive file id, or null on failure.
  Future<String?> uploadImage({
    required File file,
    required String fileName,
    required String mimeType,
    required String accountFolder,
    String? replaceFileId,
  });

  /// Downloads a backed-up file's bytes by its Drive id. Returns null on
  /// failure. Requires a live session (caller ensures it).
  Future<List<int>?> download(String fileId);
}
