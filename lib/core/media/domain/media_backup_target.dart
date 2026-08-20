import 'media_object.dart';

/// A device-local destination a captured photo is *also* copied to at capture
/// time — currently just the system Photos library ("Save to Photos"). Distinct
/// from [MediaBackupProvider] (remote cloud backup/sync, which is manual and
/// account-aware): a capture target is a fire-and-forget local copy.
///
/// Adding another on-capture destination = implement this and hand it to the
/// [MediaService]; no service rewrite.
abstract interface class MediaBackupTarget {
  /// Whether this target is usable right now (permissions granted). The service
  /// skips unconfigured targets rather than throwing.
  Future<bool> isConfigured();

  /// Copies the file backing [object] (resolved via the store) to the target.
  /// Returns whether it succeeded; throwing is treated as failure by the service.
  Future<bool> backup(MediaObject object);
}
