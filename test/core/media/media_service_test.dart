import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/media/data/in_memory_media_preferences_repository.dart';
import 'package:zivo/core/media/data/in_memory_media_registry.dart';
import 'package:zivo/core/media/data/local_media_store.dart';
import 'package:zivo/core/media/domain/media_backup_target.dart';
import 'package:zivo/core/media/domain/media_kind.dart';
import 'package:zivo/core/media/domain/media_object.dart';
import 'package:zivo/core/media/domain/media_registry.dart';
import 'package:zivo/core/media/domain/media_storage_preferences.dart';
import 'package:zivo/core/media/media_service.dart';

/// A registry whose writes always fail — models Firestore rules denying the
/// media path, to prove capture degrades gracefully.
class _ThrowingRegistry implements MediaRegistry {
  @override
  Future<void> put(MediaObject object) async => throw StateError('denied');
  @override
  Future<MediaObject?> get(String id) async => null;
  @override
  Future<MediaObject?> getByRelativePath(String relativePath) async => null;
  @override
  Future<List<MediaObject>> getAll() async => const [];
  @override
  Future<List<MediaObject>> pendingBackups() async => const [];
  @override
  Future<void> remove(String id) async {}
}

/// Records every gallery-copy call and returns a scripted result.
class _FakeTarget implements MediaBackupTarget {
  _FakeTarget({this.succeed = true});

  final bool succeed;
  final List<String> backedUp = [];

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<bool> backup(MediaObject object) async {
    backedUp.add(object.id);
    return succeed;
  }
}

void main() {
  late Directory root;
  late Directory srcDir;
  late LocalMediaStore storeImpl;
  late InMemoryMediaRegistry registry;
  late InMemoryMediaPreferencesRepository prefs;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zivo_svc_root');
    srcDir = Directory.systemTemp.createTempSync('zivo_svc_src');
    storeImpl = LocalMediaStore(rootOverride: root);
    registry = InMemoryMediaRegistry();
    prefs = InMemoryMediaPreferencesRepository();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (srcDir.existsSync()) srcDir.deleteSync(recursive: true);
  });

  String src(String name) {
    final f = File('${srcDir.path}/$name')..writeAsBytesSync([1, 2, 3]);
    return f.path;
  }

  MediaService buildService({MediaBackupTarget? galleryTarget}) =>
      MediaService(store: storeImpl, registry: registry, preferences: prefs, galleryTarget: galleryTarget);

  group('capture', () {
    test('stores bytes, registers metadata, and returns the relative ref', () async {
      final service = buildService();
      final ref = await service.capture(
        sourcePath: src('m.jpg'),
        kind: MediaKind.moment,
        id: 'm1',
        ownerUid: 'u1',
      );

      expect(ref, 'media/moments/m1.jpg');
      // `capture` returns at the durable LOCAL copy and registers on a
      // background tail (see its doc) — the registry assertions below are
      // about that tail, so wait for it.
      await service.settleCaptures();
      final object = await registry.get('m1');
      expect(object, isNotNull);
      expect(object!.ownerUid, 'u1');
      expect(object.relativePath, ref);
      expect(object.gallery, BackupState.pending);
      expect((await storeImpl.resolve(ref))!.existsSync(), isTrue);
    });

    test('does not touch the gallery when Save to Photos is off', () async {
      final gallery = _FakeTarget();
      final service = buildService(galleryTarget: gallery);
      await service.capture(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', ownerUid: 'u1');
      await service.settleCaptures();
      expect(gallery.backedUp, isEmpty);
    });

    test('copies to the gallery and records done when Save to Photos is on', () async {
      await prefs.save(const MediaStoragePreferences(saveToPhotos: true));
      final gallery = _FakeTarget();
      final service = buildService(galleryTarget: gallery);

      await service.capture(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', ownerUid: 'u1');
      await service.settleCaptures();

      expect(gallery.backedUp, ['m1']);
      expect((await registry.get('m1'))!.gallery, BackupState.done);
    });

    test('still stores locally and returns the ref when the registry throws '
        '(e.g. Firestore rules deny) — the moment/photo is never lost', () async {
      final service = MediaService(
        store: storeImpl,
        registry: _ThrowingRegistry(),
        preferences: prefs,
      );

      final ref = await service.capture(
        sourcePath: src('m.jpg'),
        kind: MediaKind.moment,
        id: 'm1',
        ownerUid: 'u1',
      );

      expect(ref, 'media/moments/m1.jpg');
      expect((await storeImpl.resolve(ref))!.existsSync(), isTrue);
    });

    test('records a gallery failure without throwing', () async {
      await prefs.save(const MediaStoragePreferences(saveToPhotos: true));
      final gallery = _FakeTarget(succeed: false);
      final service = buildService(galleryTarget: gallery);

      await service.capture(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', ownerUid: 'u1');
      await service.settleCaptures();
      expect((await registry.get('m1'))!.gallery, BackupState.failed);
    });
  });

  group('deleteMedia', () {
    test('removes the local file and the registry entry', () async {
      final service = buildService();
      final ref = await service.capture(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', ownerUid: 'u1');
      await service.deleteMedia(id: 'm1', ref: ref);
      expect(await registry.get('m1'), isNull);
      expect((await storeImpl.resolve(ref))!.existsSync(), isFalse);
    });
  });

  // Drive backup/sync behavior (manual, device-gated) lives in
  // drive_backup_test.dart against the DriveBackupClient seam.
}
