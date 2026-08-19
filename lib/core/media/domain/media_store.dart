import 'dart:io';

import 'media_kind.dart';

/// The result of importing bytes into the local [MediaStore].
class StoredMedia {
  const StoredMedia({
    required this.id,
    required this.relativePath,
    required this.mimeType,
    required this.byteSize,
    required this.contentHash,
    required this.file,
    this.width,
    this.height,
  });

  final String id;
  final String relativePath;
  final String mimeType;
  final int byteSize;
  final String contentHash;

  /// Pixel dimensions of the decoded image, when they could be read.
  final int? width;
  final int? height;

  /// The absolute file on disk right now (valid this session).
  final File file;
}

/// The durable local store for app-captured media bytes — the source of truth
/// for the actual files. Everything above (features, backup targets) goes
/// through this rather than touching `image_picker`'s ephemeral paths or the
/// documents directory directly.
///
/// The store copies imported bytes into the app's own documents directory
/// under `media/{kind}/{id}.{ext}` and hands back a *relative* path. Callers
/// persist that relative path; [resolve] turns it back into an absolute [File]
/// on demand, so files survive the app-container path changes that break
/// stored absolute paths on iOS.
abstract interface class MediaStore {
  /// Copies the file at [sourcePath] into the store under [kind], keyed by
  /// [id] (the owning entity supplies a stable id so re-imports overwrite in
  /// place rather than orphaning). Returns the stored file's metadata.
  Future<StoredMedia> importFile({
    required String sourcePath,
    required MediaKind kind,
    required String id,
  });

  /// Resolves a stored [ref] to an absolute [File].
  ///
  /// [ref] is normally a store-relative path (`media/moments/x.jpg`) joined to
  /// the (async-discovered) documents directory. For backward compatibility
  /// with media captured before this module existed, an absolute path is
  /// returned as-is. Returns null for a null/empty ref.
  ///
  /// Async because discovering the documents directory is async; the store
  /// caches it after the first call, so later resolves are effectively instant.
  Future<File?> resolve(String? ref);

  /// Best-effort deletion of a stored file by its relative [ref]. A missing
  /// file is not an error.
  Future<void> delete(String? ref);
}
