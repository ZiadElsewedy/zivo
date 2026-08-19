import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/media_kind.dart';
import '../domain/media_store.dart';

/// [MediaStore] backed by the app's own documents directory. Files live under
/// `<documents>/media/{kind}/{id}.{ext}` and are addressed by a *relative*
/// path (`media/{kind}/{id}.{ext}`) so they survive the container-path changes
/// that break stored absolute paths on iOS.
///
/// The documents directory is discovered once and cached; a test can bypass
/// `path_provider` (which needs a platform channel) by injecting [rootOverride].
class LocalMediaStore implements MediaStore {
  /// [rootOverride] pre-seeds the cached root (tests pass a temp dir to bypass
  /// the `path_provider` platform channel); otherwise it's discovered lazily.
  LocalMediaStore({Directory? rootOverride}) : _root = rootOverride;

  Directory? _root;

  static const String _mediaDir = 'media';

  Future<Directory> _rootDir() async {
    return _root ??= await getApplicationDocumentsDirectory();
  }

  @override
  Future<StoredMedia> importFile({
    required String sourcePath,
    required MediaKind kind,
    required String id,
  }) async {
    final root = await _rootDir();
    final ext = _extensionOf(sourcePath);
    final relativePath = p.join(_mediaDir, kind.folder, '$id.$ext');
    final dest = File(p.join(root.path, relativePath));
    await dest.parent.create(recursive: true);

    final source = File(sourcePath);
    final bytes = await source.readAsBytes();
    await dest.writeAsBytes(bytes, flush: true);

    final size = await _decodeSize(bytes);

    return StoredMedia(
      id: id,
      // Store forward-slashed relative paths for portability across platforms
      // and to backup targets; resolve() re-joins with the real root.
      relativePath: p.posix.joinAll(p.split(relativePath)),
      mimeType: _mimeForExtension(ext),
      byteSize: bytes.length,
      contentHash: sha256.convert(bytes).toString(),
      width: size?.$1,
      height: size?.$2,
      file: dest,
    );
  }

  /// Reads the image's pixel dimensions from its bytes. Best-effort — returns
  /// null for unreadable/non-image data rather than failing the import.
  Future<(int, int)?> _decodeSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final result = (image.width, image.height);
      image.dispose();
      codec.dispose();
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<File?> resolve(String? ref) async {
    if (ref == null || ref.isEmpty) return null;
    if (p.isAbsolute(ref)) return File(ref); // legacy pre-module paths
    final root = await _rootDir();
    return File(p.join(root.path, p.joinAll(p.posix.split(ref))));
  }

  @override
  Future<void> delete(String? ref) async {
    final file = await resolve(ref);
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort; a stray file on disk is harmless.
    }
  }

  String _extensionOf(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return ext.isEmpty ? 'jpg' : ext;
  }

  String _mimeForExtension(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }
}
