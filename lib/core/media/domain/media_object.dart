import 'media_kind.dart';

/// How a photo entered the app — surfaced in the gallery's metadata and used
/// for filtering ("Camera" vs "Library").
enum CaptureSource {
  /// Taken with the in-app camera.
  camera,

  /// Chosen from the device's photo library.
  library,

  /// Unknown (legacy media captured before this was tracked).
  unknown;

  static CaptureSource fromName(String? name) => CaptureSource.values
      .firstWhere((s) => s.name == name, orElse: () => CaptureSource.unknown);

  /// Human label for the metadata panel.
  String get label => switch (this) {
        CaptureSource.camera => 'Camera',
        CaptureSource.library => 'Photo Library',
        CaptureSource.unknown => 'Unknown',
      };
}

/// Where a single backup target stands for one media file.
enum BackupState {
  /// Never attempted, or the target is off. The default for a fresh file.
  pending,

  /// Successfully copied to the target at least once.
  done,

  /// The last attempt failed; safe to retry.
  failed,
}

/// The registry record for one app-managed media file — the durable link
/// between the actual bytes (stored locally, and optionally mirrored to
/// backup targets) and the app's own data.
///
/// This is intentionally decoupled from any feature entity: a [Moment] or a
/// [UserProfile] references media by [id], and this record owns everything
/// about the file itself — where the bytes live locally, how big they are,
/// and the per-target backup status the "Back up now" / auto-backup flows read
/// and update. Bytes never live in Firestore; only this metadata does.
class MediaObject {
  const MediaObject({
    required this.id,
    required this.ownerUid,
    required this.kind,
    required this.relativePath,
    required this.mimeType,
    required this.byteSize,
    required this.contentHash,
    required this.capturedAt,
    this.source = CaptureSource.unknown,
    this.width,
    this.height,
    this.gallery = BackupState.pending,
    this.drive = BackupState.pending,
    this.driveFileId,
  });

  /// Stable id, also embedded in [relativePath] and referenced by the owning
  /// feature entity (`Moment.imagePath` / `UserProfile.photoPath` hold the
  /// relative path, whose basename is this id).
  final String id;
  final String ownerUid;
  final MediaKind kind;

  /// Path relative to the app documents directory, e.g. `media/moments/ab12.jpg`.
  /// Resolved to an absolute [File] at read time by the [MediaStore], which
  /// fixes the iOS "container UUID changes across reinstalls" problem that
  /// storing an absolute path suffers from.
  final String relativePath;

  final String mimeType;
  final int byteSize;

  /// SHA-256 of the bytes — lets backup targets skip re-uploading unchanged
  /// files and detect edits.
  final String contentHash;

  /// The moment the media was captured/imported (domain time, not server time).
  final DateTime capturedAt;

  /// How the photo entered the app (camera vs library).
  final CaptureSource source;

  /// Pixel dimensions of the stored image, when known.
  final int? width;
  final int? height;

  /// Per-target backup status.
  final BackupState gallery;
  final BackupState drive;

  /// The Google Drive file id once uploaded (for update/delete/restore). Null
  /// until a Drive backup succeeds.
  final String? driveFileId;

  MediaObject copyWith({
    BackupState? gallery,
    BackupState? drive,
    String? driveFileId,
  }) {
    return MediaObject(
      id: id,
      ownerUid: ownerUid,
      kind: kind,
      relativePath: relativePath,
      mimeType: mimeType,
      byteSize: byteSize,
      contentHash: contentHash,
      capturedAt: capturedAt,
      source: source,
      width: width,
      height: height,
      gallery: gallery ?? this.gallery,
      drive: drive ?? this.drive,
      driveFileId: driveFileId ?? this.driveFileId,
    );
  }
}
