import '../domain/media_object.dart';
import '../domain/media_registry.dart';

/// Shared by both [MediaRegistry] implementations so the in-memory fallback and
/// Firestore can never drift on what "still needs backing up" means.
///
/// A record is outstanding when the remote push has not succeeded, when the
/// gallery copy failed, or when it succeeded against a *different* cloud
/// account than the one connected now — the last clause being what makes
/// connecting a new account queue the existing library rather than report
/// "everything is already backed up" over a destination that holds nothing.
bool needsBackup(MediaObject m, String? forAccountKey) {
  if (m.remoteBackup != BackupState.done) return true;
  if (m.gallery == BackupState.failed) return true;
  if (forAccountKey == null) return false;
  return !m.isRemoteReachableFrom(forAccountKey);
}

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
  Future<List<MediaObject>> pendingBackups({String? forAccountKey}) async {
    return _items.values
        .where((m) => needsBackup(m, forAccountKey))
        .toList(growable: false);
  }

  @override
  Future<void> remove(String id) async {
    _items.remove(id);
  }
}
