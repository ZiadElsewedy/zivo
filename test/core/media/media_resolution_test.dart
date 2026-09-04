import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/media/data/in_memory_media_preferences_repository.dart';
import 'package:zivo/core/media/data/in_memory_media_registry.dart';
import 'package:zivo/core/media/data/local_media_store.dart';
import 'package:zivo/core/media/domain/media_backup_provider.dart';
import 'package:zivo/core/media/domain/media_kind.dart';
import 'package:zivo/core/media/domain/media_object.dart';
import 'package:zivo/core/media/domain/media_resolution.dart';
import 'package:zivo/core/media/domain/media_storage_preferences.dart';
import 'package:zivo/core/media/media_service.dart';

/// A scriptable [MediaBackupProvider] — no real Google/network.
class _FakeDrive implements MediaBackupProvider {
  _FakeDrive({
    this.deviceConnected = false,
    this.liveSession = false,
    this.ownerId,
    this.uploadId,
    this.downloadBytes,
  });

  bool deviceConnected;
  bool liveSession;
  String? ownerId;
  String? uploadId;
  List<int>? downloadBytes;

  final List<String> uploaded = [];
  final List<String> downloaded = [];

  @override
  bool get hasLiveSession => liveSession;

  @override
  Future<bool> isDeviceConnected() async => deviceConnected;

  @override
  Future<String?> connectedEmail() async => 'test@example.com';

  @override
  Future<String?> connectedOwnerId() async => ownerId;

  @override
  Future<BackupAccount?> connect({required String ownerAccountId}) async {
    deviceConnected = true;
    liveSession = true;
    ownerId = ownerAccountId;
    return const BackupAccount(id: 'acc-1', email: 'test@example.com');
  }

  @override
  Future<BackupAccount?> restoreSession() async {
    if (deviceConnected) liveSession = true;
    return liveSession ? const BackupAccount(id: 'acc-1', email: 'test@example.com') : null;
  }

  @override
  Future<void> disconnect() async {
    deviceConnected = false;
    liveSession = false;
    ownerId = null;
  }

  @override
  Future<String?> upload({
    required File file,
    required String fileName,
    required String mimeType,
    required String accountFolder,
    String? replaceRemoteId,
  }) async {
    uploaded.add(fileName);
    return uploadId;
  }

  @override
  Future<List<int>?> download(String fileId) async {
    downloaded.add(fileId);
    return downloadBytes;
  }

  @override
  Future<bool> deleteRemote(String remoteId) async => true;
}

void main() {
  late Directory root;
  late Directory srcDir;
  late LocalMediaStore store;
  late InMemoryMediaRegistry registry;
  late InMemoryMediaPreferencesRepository prefs;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zivo_res_root');
    srcDir = Directory.systemTemp.createTempSync('zivo_res_src');
    store = LocalMediaStore(rootOverride: root);
    registry = InMemoryMediaRegistry();
    prefs = InMemoryMediaPreferencesRepository();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (srcDir.existsSync()) srcDir.deleteSync(recursive: true);
  });

  MediaService buildService({_FakeDrive? backup}) => MediaService(
        store: store,
        registry: registry,
        preferences: prefs,
        backup: backup,
        currentAccountId: () => 'u1',
      );

  Future<String> capture(String id) {
    final f = File('${srcDir.path}/$id.jpg')..writeAsBytesSync([1, 2, 3]);
    return buildService().capture(
      sourcePath: f.path,
      kind: MediaKind.moment,
      id: id,
      ownerUid: 'u1',
    );
  }

  group('resolveWithStatus', () {
    test('a freshly captured photo resolves onDevice', () async {
      final service = buildService();
      final src = File('${srcDir.path}/a.jpg')..writeAsBytesSync([1]);
      final ref = await service.capture(
        sourcePath: src.path,
        kind: MediaKind.moment,
        id: 'm1',
        ownerUid: 'u1',
      );
      final r = await service.resolveWithStatus(ref);
      expect(r.availability, MediaAvailability.onDevice);
      expect(r.file, isNotNull);
    });

    test('missing bytes WITH a remote copy are fetched automatically '
        '(cloud-only metadata becomes on-device)', () async {
      final drive = _FakeDrive(
        deviceConnected: true,
        liveSession: true,
        ownerId: 'u1',
        downloadBytes: [9, 9, 9],
      );
      final service = MediaService(
        store: store,
        registry: registry,
        preferences: prefs,
        backup: drive,
        currentAccountId: () => 'u1',
      );
      final src = File('${srcDir.path}/b.jpg')..writeAsBytesSync([1, 2]);
      final ref = await service.capture(
        sourcePath: src.path,
        kind: MediaKind.moment,
        id: 'm2',
        ownerUid: 'u1',
      );
      // `capture` returns at the local copy; the registry record this test
      // then patches is written on its background tail.
      await service.settleCaptures();
      // Simulate another device's world: metadata synced, bytes not here,
      // Drive holds a copy.
      (await store.resolve(ref))!.deleteSync();
      await registry.put(
        (await registry.get('m2'))!.copyWith(
          remoteBackup: BackupState.done,
          remoteId: 'drive-2',
        ),
      );

      final r = await service.resolveWithStatus(ref);

      expect(r.availability, MediaAvailability.onDevice);
      expect(drive.downloaded, ['drive-2']);
      expect((await store.resolve(ref))!.readAsBytesSync(), [9, 9, 9]);
    });

    test('missing bytes with NO remote copy are honestly `nowhere` — '
        'the captured-on-another-device case', () async {
      final service = buildService(backup: _FakeDrive(liveSession: true));
      final ref = await capture('m3');
      (await store.resolve(ref))!.deleteSync();

      final r = await service.resolveWithStatus(ref);

      expect(r.availability, MediaAvailability.nowhere);
      expect(r.file, isNull);
      expect(r.hasBytes, isFalse);
    });

    test('fetchable-but-sessionless reads as cloudOnly (on its way), not an error', () async {
      // Connected ONCE (owner persists) but no live/restorable session —
      // e.g. revoked token, offline. Fetch must not even attempt.
      final drive = _FakeDrive(deviceConnected: false, liveSession: false, ownerId: 'u1');
      final service = MediaService(
        store: store,
        registry: registry,
        preferences: prefs,
        backup: drive,
        currentAccountId: () => 'u1',
      );
      final src = File('${srcDir.path}/c.jpg')..writeAsBytesSync([1]);
      final ref = await service.capture(
        sourcePath: src.path,
        kind: MediaKind.moment,
        id: 'm4',
        ownerUid: 'u1',
      );
      // `capture` returns at the local copy; the registry record this test
      // then patches is written on its background tail.
      await service.settleCaptures();
      (await store.resolve(ref))!.deleteSync();
      await registry.put(
        (await registry.get('m4'))!
            .copyWith(remoteBackup: BackupState.done, remoteId: 'drive-4'),
      );

      final r = await service.resolveWithStatus(ref);

      expect(r.availability, MediaAvailability.cloudOnly);
      expect(r.file, isNull);
      expect(drive.downloaded, isEmpty); // never even attempted without a session
    });
  });

  group('auto-upload on capture', () {
    test('a capture uploads immediately when the device can talk to Drive', () async {
      final drive = _FakeDrive(
        deviceConnected: true,
        liveSession: true,
        ownerId: 'u1',
        uploadId: 'drive-new',
      );
      final service = MediaService(
        store: store,
        registry: registry,
        preferences: prefs,
        backup: drive,
        currentAccountId: () => 'u1',
      );
      final f = File('${srcDir.path}/d.jpg')..writeAsBytesSync([7, 7]);
      await service.capture(
        sourcePath: f.path,
        kind: MediaKind.moment,
        id: 'm5',
        ownerUid: 'u1',
      );

      // Fire-and-forget — poll briefly for the registry flip.
      MediaObject? object;
      for (var i = 0; i < 100; i++) {
        object = await registry.get('m5');
        if (object?.remoteBackup == BackupState.done) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(object, isNotNull);
      expect(object!.remoteBackup, BackupState.done);
      expect(object.remoteId, 'drive-new');
      expect(drive.uploaded, isNotEmpty);
    });

    test('no auto-upload when the preference is off', () async {
      await prefs.save(const MediaStoragePreferences(autoUploadToDrive: false));
      final drive = _FakeDrive(
        deviceConnected: true,
        liveSession: true,
        ownerId: 'u1',
        uploadId: 'drive-x',
      );
      final service = MediaService(
        store: store,
        registry: registry,
        preferences: prefs,
        backup: drive,
        currentAccountId: () => 'u1',
      );
      final f = File('${srcDir.path}/e.jpg')..writeAsBytesSync([1]);
      await service.capture(
        sourcePath: f.path,
        kind: MediaKind.moment,
        id: 'm6',
        ownerUid: 'u1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(drive.uploaded, isEmpty);
      expect((await registry.get('m6'))!.remoteBackup, BackupState.pending);
    });

    test('no auto-upload when the connection belongs to another account', () async {
      final drive = _FakeDrive(
        deviceConnected: true,
        liveSession: true,
        ownerId: 'someone-else', // foreign owner — must fail closed
        uploadId: 'drive-y',
      );
      final service = MediaService(
        store: store,
        registry: registry,
        preferences: prefs,
        backup: drive,
        currentAccountId: () => 'u1',
      );
      final f = File('${srcDir.path}/f.jpg')..writeAsBytesSync([2]);
      await service.capture(
        sourcePath: f.path,
        kind: MediaKind.moment,
        id: 'm7',
        ownerUid: 'u1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(drive.uploaded, isEmpty);
    });
  });
}
