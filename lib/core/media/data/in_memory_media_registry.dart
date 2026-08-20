import '../domain/media_object.dart';
import '../domain/media_registry.dart';

/// In-memory [MediaRegistry] for offline/dev runs and tests.
class InMemoryMediaRegistry implements MediaRegistry {
  final Map<String, MediaObject> _items = {};

  @override
  Future<void> put(MediaObject object) async {
    _items[object.id] = object;
  }

  @override
  Future<MediaObject?> get(String id) async => _items[id];

  @override
  Future<MediaObject?> getByRelativePath(String relativePath) async {
    for (final object in _items.values) {
      if (object.relativePath == relativePath) return object;
    }
    return null;
  }

  @override
  Future<List<MediaObject>> getAll() async => _items.values.toList(growable: false);

  @override
  Future<List<MediaObject>> pendingBackups() async {
    return _items.values
        .where((m) => m.remoteBackup != BackupState.done || m.gallery == BackupState.failed)
        .toList(growable: false);
  }

  @override
  Future<void> remove(String id) async {
    _items.remove(id);
  }
}
