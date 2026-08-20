import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/media/data/in_memory_media_preferences_repository.dart';
import 'package:zivo/core/media/data/in_memory_media_registry.dart';
import 'package:zivo/core/media/data/local_media_store.dart';
import 'package:zivo/core/media/domain/drive_backup_client.dart';
import 'package:zivo/core/media/domain/media_kind.dart';
import 'package:zivo/core/media/domain/media_object.dart';
import 'package:zivo/core/media/media_service.dart';

/// A scriptable [DriveBackupClient] — no real Google/network.
class _FakeDriveClient implements DriveBackupClient {
  _FakeDriveClient({
    this.connectAccount,
    this.deviceConnected = false,
    this.liveSession = false,
    this.uploadId = 'drive-1',
  });

  DriveAccount? connectAccount;
  bool deviceConnected;
  bool liveSession;
  String? uploadId;
  List<int>? downloadBytes;

  final List<String> uploadedFolders = [];
  final List<String> uploaded = [];
  final List<String> downloaded = [];
  int connectCalls = 0;
  int disconnectCalls = 0;
  int restoreCalls = 0;

  @override
  bool get hasLiveSession => liveSession;

  @override
  Future<bool> isDeviceConnected() async => deviceConnected;

  @override
  Future<String?> connectedEmail() async => connectAccount?.email;

  @override
  Future<DriveAccount?> connect() async {
    connectCalls++;
    if (connectAccount != null) {
      deviceConnected = true;
      liveSession = true;
    }
    return connectAccount;
  }

  @override
  Future<DriveAccount?> restoreSession() async {
    restoreCalls++;
    if (deviceConnected) liveSession = true;
    return liveSession ? connectAccount : null;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    deviceConnected = false;
    liveSession = false;
  }

  @override
  Future<String?> uploadImage({
    required File file,
    required String fileName,
    required String mimeType,
    required String accountFolder,
    String? replaceFileId,
  }) async {
    uploaded.add(fileName);
    uploadedFolders.add(accountFolder);
    return uploadId;
  }

  @override
  Future<List<int>?> download(String fileId) async {
    downloaded.add(fileId);
    return downloadBytes;
  }
}

void main() {
  late Directory root;
  late Directory srcDir;
  late LocalMediaStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zivo_drive_root');
    srcDir = Directory.systemTemp.createTempSync('zivo_drive_src');
    store = LocalMediaStore(rootOverride: root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (srcDir.existsSync()) srcDir.deleteSync(recursive: true);
  });

  String src(String name) =>
      (File('${srcDir.path}/$name')..writeAsBytesSync([1, 2, 3])).path;

  MediaObject makeObject({String id = 'm1', String? driveFileId, String uid = 'u1'}) =>
      MediaObject(
        id: id,
        ownerUid: uid,
        kind: MediaKind.moment,
        relativePath: 'media/moments/$id.jpg',
        mimeType: 'image/jpeg',
        byteSize: 3,
        contentHash: 'h',
        capturedAt: DateTime(2026, 1, 1),
        driveFileId: driveFileId,
      );

  MediaService buildService(_FakeDriveClient client, InMemoryMediaRegistry registry) =>
      MediaService(
        store: store,
        registry: registry,
        preferences: InMemoryMediaPreferencesRepository(),
        driveClient: client,
      );

  group('connect / disconnect', () {
    test('connectDrive returns true and marks the device connected', () async {
      final client = _FakeDriveClient(connectAccount: const DriveAccount(id: '1', email: 'x@e.com'));
      final service = buildService(client, InMemoryMediaRegistry());

      expect(await service.connectDrive(), isTrue);
      expect(client.connectCalls, 1);
      expect(await service.isDriveConnected(), isTrue);
      expect(await service.connectedDriveEmail(), 'x@e.com');
    });

    test('connectDrive returns false on cancel', () async {
      final client = _FakeDriveClient(connectAccount: null);
      expect(await buildService(client, InMemoryMediaRegistry()).connectDrive(), isFalse);
    });

    test('disconnectDrive revokes the device connection', () async {
      final client = _FakeDriveClient(deviceConnected: true, liveSession: true);
      await buildService(client, InMemoryMediaRegistry()).disconnectDrive();
      expect(client.disconnectCalls, 1);
      expect(await client.isDeviceConnected(), isFalse);
    });

    test('supportsDrive reflects whether a client is wired', () async {
      expect(buildService(_FakeDriveClient(), InMemoryMediaRegistry()).supportsDrive, isTrue);
      final withoutDrive = MediaService(
        store: store,
        registry: InMemoryMediaRegistry(),
        preferences: InMemoryMediaPreferencesRepository(),
      );
      expect(withoutDrive.supportsDrive, isFalse);
    });
  });

  group('backupNow (manual)', () {
    test('uploads pending media to the per-account folder and records the id', () async {
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1');
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject(uid: 'acct-9'));
      final client = _FakeDriveClient(deviceConnected: true, liveSession: true, uploadId: 'drive-xyz');
      final service = buildService(client, registry);

      final pushed = await service.backupNow();

      expect(pushed, 1);
      expect(client.uploaded, ['m1.jpg']);
      expect(client.uploadedFolders, ['acct-9']); // per-account subfolder
      expect((await registry.get('m1'))!.driveFileId, 'drive-xyz');
      expect((await registry.get('m1'))!.drive, BackupState.done);
    });

    test('does nothing when Drive is not connected on this device', () async {
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1');
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject());
      final client = _FakeDriveClient(deviceConnected: false, liveSession: false);
      final service = buildService(client, registry);

      expect(await service.backupNow(), 0);
      expect(client.uploaded, isEmpty);
    });

    test('restores the session first when connected but not live (Back up now)', () async {
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1');
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject());
      final client = _FakeDriveClient(
        connectAccount: const DriveAccount(id: '1', email: 'x@e.com'),
        deviceConnected: true,
        liveSession: false,
      );
      final service = buildService(client, registry);

      await service.backupNow();
      expect(client.restoreCalls, 1);
      expect(client.uploaded, ['m1.jpg']);
    });
  });

  group('resolveOrFetch never prompts', () {
    const ref = 'media/moments/m1.jpg';

    test('returns the local file without downloading when it exists', () async {
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1');
      final client = _FakeDriveClient(deviceConnected: true, liveSession: true);
      final file = await buildService(client, InMemoryMediaRegistry()).resolveOrFetch(ref);
      expect(file!.existsSync(), isTrue);
      expect(client.downloaded, isEmpty);
    });

    test('does NOT touch Drive when no session is live (passive read)', () async {
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject(driveFileId: 'd1'));
      // Connected on device, but session not live → still must not download.
      final client = _FakeDriveClient(deviceConnected: true, liveSession: false)
        ..downloadBytes = [9];
      final service = buildService(client, registry);

      expect(await service.resolveOrFetch(ref), isNull);
      expect(client.downloaded, isEmpty);
      expect(client.restoreCalls, 0);
    });

    test('downloads when a session is live and the file is backed up', () async {
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject(driveFileId: 'd1'));
      final client = _FakeDriveClient(deviceConnected: true, liveSession: true)
        ..downloadBytes = [4, 5, 6];
      final service = buildService(client, registry);

      final file = await service.resolveOrFetch(ref);
      expect(client.downloaded, ['d1']);
      expect(file!.readAsBytesSync(), [4, 5, 6]);
    });
  });

  group('syncFromDrive (manual)', () {
    test('downloads backed-up media that is missing locally', () async {
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject(id: 'm1', driveFileId: 'd1'));
      await registry.put(makeObject(id: 'm2')); // no drive backup → skipped
      final client = _FakeDriveClient(deviceConnected: true, liveSession: true)
        ..downloadBytes = [7];
      final service = buildService(client, registry);

      final fetched = await service.syncFromDrive();
      expect(fetched, 1);
      expect(client.downloaded, ['d1']);
      expect((await store.resolve('media/moments/m1.jpg'))!.existsSync(), isTrue);
    });

    test('does nothing when Drive is not connected', () async {
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject(driveFileId: 'd1'));
      final client = _FakeDriveClient(deviceConnected: false, liveSession: false);
      expect(await buildService(client, registry).syncFromDrive(), 0);
    });
  });
}
