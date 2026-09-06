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
  // The on-screen name for each source lives in
  // `presentation/capture_source_labels.dart`: this enum is persisted by
  // `name`, so it is an id, and an id must not carry copy that changes with
  // the reader's language.
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
    this.remoteBackup = BackupState.pending,
    this.remoteId,
    this.remoteAccountKey,
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

  /// Copied to the device gallery ("Save to Photos").
  final BackupState gallery;

  /// Backed up to the remote cloud provider (Drive today; provider-agnostic).
  final BackupState remoteBackup;

  /// The provider-assigned id of the uploaded file (for update/restore). Null
  /// until a remote backup succeeds.
  ///
  /// **Only meaningful paired with [remoteAccountKey].** A provider file id is
  /// a location inside one cloud account, not a portable identity; the id
  /// alone cannot tell you whether the account currently connected is the one
  /// that can resolve it.
  final String? remoteId;

  /// The backup account [remoteId] lives in — the provider's stable account
  /// key (for Drive, the Google account id; never the email, which is
  /// renameable and reusable). Null on records written before this field
  /// existed, which means *unknown*, and unknown is deliberately never treated
  /// as equal to the connected account: assuming otherwise is what let a photo
  /// backed up to one Drive account be silently resolved against another.
  final String? remoteAccountKey;

  /// Whether this record's remote copy is reachable from the account currently
  /// connected on this device. A legacy record (no [remoteAccountKey]) is
  /// optimistically treated as reachable — the overwhelmingly common case is
  /// that the user never switched accounts — and is stamped with the real key
  /// the first time a transfer confirms it.
  bool isRemoteReachableFrom(String? connectedAccountKey) {
    if (remoteId == null || connectedAccountKey == null) return false;
    return remoteAccountKey == null || remoteAccountKey == connectedAccountKey;
  }

  /// [clearRemote] drops [remoteId] and [remoteAccountKey] together — the pair
  /// is meaningless apart, and the `??` fallbacks below otherwise make it
  /// impossible to un-set a remote reference that has been proven dead.
  MediaObject copyWith({
    BackupState? gallery,
    BackupState? remoteBackup,
    String? remoteId,
    String? remoteAccountKey,
    bool clearRemote = false,
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
      remoteBackup: remoteBackup ?? this.remoteBackup,
      remoteId: clearRemote ? null : (remoteId ?? this.remoteId),
      remoteAccountKey:
          clearRemote ? null : (remoteAccountKey ?? this.remoteAccountKey),
    );
  }
}
