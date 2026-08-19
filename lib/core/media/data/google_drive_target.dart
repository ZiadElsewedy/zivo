import 'package:path/path.dart' as p;

import '../domain/drive_backup_client.dart';
import '../domain/media_backup_target.dart';
import '../domain/media_object.dart';
import '../domain/media_store.dart';

/// The Google Drive [MediaBackupTarget]. Thin adapter over [DriveBackupClient]:
/// resolves a [MediaObject]'s local file and hands it to the client, mapping the
/// returned Drive file id into the [BackupResult] (so the registry can store it
/// on [MediaObject.driveFileId] for idempotent re-backup).
class GoogleDriveTarget implements MediaBackupTarget {
  GoogleDriveTarget({required this.client, required this.store});

  final DriveBackupClient client;
  final MediaStore store;

  @override
  BackupTargetId get id => BackupTargetId.drive;

  @override
  Future<bool> isConfigured() => client.isConnected();

  @override
  Future<BackupResult> backup(MediaObject object) async {
    final file = await store.resolve(object.relativePath);
    if (file == null || !await file.exists()) {
      return const BackupResult.failure();
    }
    final remoteId = await client.uploadImage(
      file: file,
      fileName: p.basename(object.relativePath),
      mimeType: object.mimeType,
      replaceFileId: object.driveFileId,
    );
    return remoteId == null
        ? const BackupResult.failure()
        : BackupResult.success(remoteId: remoteId);
  }
}
