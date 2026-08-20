import 'dart:io';

/// A connected Google account for Drive backup — just the identity bits the UI
/// shows. The OAuth tokens live inside the client, never here.
class DriveAccount {
  const DriveAccount({required this.id, required this.email});

  final String id;
  final String email;
}

/// The seam between the app and Google Drive. Wraps the OAuth dance
/// (google_sign_in incremental authorization for the `drive.file` scope) and
/// the actual file upload, so the rest of the media pipeline — [MediaService]
/// and [GoogleDriveTarget] — depends only on this interface and can be tested
/// with a fake.
///
/// `drive.file` means the app only ever sees files it created; uploads land in
/// an app-owned folder. There is deliberately no "list everything" method.
abstract interface class DriveBackupClient {
  /// Interactive connect: signs the user into Google if needed and authorizes
  /// the `drive.file` scope. Returns the account, or null if cancelled/failed.
  Future<DriveAccount?> connect();

  /// Whether a Google account is currently connected with the scope granted,
  /// without prompting. Used as the target's "isConfigured" check.
  Future<bool> isConnected();

  /// Revokes authorization / signs out of the Google session.
  Future<void> disconnect();

  /// Uploads [file] to the app's Drive folder. When [replaceFileId] is given,
  /// updates that existing Drive file in place (idempotent re-backup). Returns
  /// the Drive file id on success, or null on failure.
  Future<String?> uploadImage({
    required File file,
    required String fileName,
    required String mimeType,
    String? replaceFileId,
  });

  /// Downloads the bytes of a previously-backed-up file by its Drive id — the
  /// counterpart to [uploadImage], used to pull a photo onto a second device
  /// (or after a reinstall). Returns null if unavailable/failed.
  Future<List<int>?> download(String fileId);
}
