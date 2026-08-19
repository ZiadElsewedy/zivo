import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/media/data/in_memory_media_preferences_repository.dart';
import 'package:zivo/core/media/data/in_memory_media_registry.dart';
import 'package:zivo/core/media/data/local_media_store.dart';
import 'package:zivo/core/media/domain/media_backup_target.dart';
import 'package:zivo/core/media/domain/media_kind.dart';
import 'package:zivo/core/media/domain/media_object.dart';
import 'package:zivo/core/media/domain/media_storage_preferences.dart';
import 'package:zivo/core/media/media_service.dart';

/// Records every backup call and returns a scripted result.
class _FakeTarget implements MediaBackupTarget {
  _FakeTarget(this.id, {this.succeed = true, this.remoteId});

  @override
  final BackupTargetId id;
  final bool succeed;
  final String? remoteId;
  final List<String> backedUp = [];

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<BackupResult> backup(MediaObject object) async {
    backedUp.add(object.id);
    return succeed ? BackupResult.success(remoteId: remoteId) : const BackupResult.failure();
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

  MediaService buildService({Map<BackupTargetId, MediaBackupTarget> targets = const {}}) =>
      MediaService(store: storeImpl, registry: registry, preferences: prefs, targets: targets);

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
      final object = await registry.get('m1');
      expect(object, isNotNull);
      expect(object!.ownerUid, 'u1');
      expect(object.relativePath, ref);
      expect(object.gallery, BackupState.pending);
      expect((await storeImpl.resolve(ref))!.existsSync(), isTrue);
    });

    test('does not touch the gallery when Save to Photos is off', () async {
      final gallery = _FakeTarget(BackupTargetId.gallery);
      final service = buildService(targets: {BackupTargetId.gallery: gallery});
      await service.capture(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', ownerUid: 'u1');
      expect(gallery.backedUp, isEmpty);
    });

    test('copies to the gallery and records done when Save to Photos is on', () async {
      await prefs.save(const MediaStoragePreferences(saveToPhotos: true));
      final gallery = _FakeTarget(BackupTargetId.gallery);
      final service = buildService(targets: {BackupTargetId.gallery: gallery});

      await service.capture(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', ownerUid: 'u1');

      expect(gallery.backedUp, ['m1']);
      expect((await registry.get('m1'))!.gallery, BackupState.done);
    });

    test('records a gallery failure without throwing', () async {
      await prefs.save(const MediaStoragePreferences(saveToPhotos: true));
      final gallery = _FakeTarget(BackupTargetId.gallery, succeed: false);
      final service = buildService(targets: {BackupTargetId.gallery: gallery});

      await service.capture(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', ownerUid: 'u1');
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

  group('backupNow', () {
    test('pushes pending media to Drive, stamps state, id, and lastBackupAt', () async {
      await prefs.save(const MediaStoragePreferences(driveBackupEnabled: true));
      final drive = _FakeTarget(BackupTargetId.drive, remoteId: 'drive-xyz');
      final service = buildService(targets: {BackupTargetId.drive: drive});
      await service.capture(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', ownerUid: 'u1');

      final pushed = await service.backupNow();

      expect(pushed, 1);
      expect(drive.backedUp, ['m1']);
      final object = await registry.get('m1');
      expect(object!.drive, BackupState.done);
      expect(object.driveFileId, 'drive-xyz');
      expect((await prefs.read()).lastBackupAt, isNotNull);
    });

    test('does nothing when Drive backup is disabled', () async {
      final drive = _FakeTarget(BackupTargetId.drive);
      final service = buildService(targets: {BackupTargetId.drive: drive});
      await service.capture(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', ownerUid: 'u1');

      expect(await service.backupNow(), 0);
      expect(drive.backedUp, isEmpty);
    });
  });

  group('runAutoBackupIfDue', () {
    test('runs when more than the cadence has elapsed', () async {
      await prefs.save(MediaStoragePreferences(
        driveBackupEnabled: true,
        autoBackupEveryDays: 3,
        lastBackupAt: DateTime(2026, 1, 1),
      ));
      final drive = _FakeTarget(BackupTargetId.drive);
      final service = buildService(targets: {BackupTargetId.drive: drive});
      await service.capture(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', ownerUid: 'u1');

      await service.runAutoBackupIfDue(now: DateTime(2026, 1, 5));
      expect(drive.backedUp, ['m1']);
    });

    test('skips when the cadence has not elapsed', () async {
      await prefs.save(MediaStoragePreferences(
        driveBackupEnabled: true,
        autoBackupEveryDays: 3,
        lastBackupAt: DateTime(2026, 1, 1),
      ));
      final drive = _FakeTarget(BackupTargetId.drive);
      final service = buildService(targets: {BackupTargetId.drive: drive});
      await service.capture(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', ownerUid: 'u1');

      await service.runAutoBackupIfDue(now: DateTime(2026, 1, 2));
      expect(drive.backedUp, isEmpty);
    });
  });
}
