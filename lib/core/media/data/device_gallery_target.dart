import 'package:gal/gal.dart';

import '../domain/media_backup_target.dart';
import '../domain/media_object.dart';
import '../domain/media_store.dart';

/// Saves media into the device's system Photos/Gallery — the opt-in "Save to
/// Photos" destination. Backed by the `gal` plugin (MediaStore on Android,
/// PHPhotoLibrary on iOS).
///
/// Unlike Drive this needs no account, only the OS photo-add permission, so it
/// is always "connectable"; the service still only invokes it when the account
/// has `saveToPhotos` enabled.
class DeviceGalleryTarget implements MediaBackupTarget {
  DeviceGalleryTarget({required this.store, this.album = 'ZIVO'});

  final MediaStore store;

  /// The album app photos are grouped under in the system gallery.
  final String album;

  @override
  BackupTargetId get id => BackupTargetId.gallery;

  @override
  Future<bool> isConfigured() async {
    // Permission is requested lazily on first save; treat as available so the
    // service attempts it (the request prompt appears then).
    return true;
  }

  @override
  Future<BackupResult> backup(MediaObject object) async {
    final file = await store.resolve(object.relativePath);
    if (file == null || !await file.exists()) {
      return const BackupResult.failure();
    }
    try {
      if (!await Gal.hasAccess()) {
        final granted = await Gal.requestAccess();
        if (!granted) return const BackupResult.failure();
      }
      await Gal.putImage(file.path, album: album);
      return const BackupResult.success();
    } on GalException {
      return const BackupResult.failure();
    }
  }
}
