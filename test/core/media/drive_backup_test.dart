import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/media/data/in_memory_media_preferences_repository.dart';
import 'package:zivo/core/media/data/in_memory_media_registry.dart';
import 'package:zivo/core/media/data/local_media_store.dart';
import 'package:zivo/core/media/domain/media_backup_provider.dart';
import 'package:zivo/core/media/domain/media_kind.dart';
import 'package:zivo/core/media/domain/media_object.dart';
import 'package:zivo/core/media/domain/media_storage_preferences.dart';
import 'package:zivo/core/media/media_service.dart';

/// A scriptable [DriveBackupClient] — no real Google/network.
class _FakeDriveClient implements MediaBackupProvider {
  _FakeDriveClient({
    this.connectAccount,
    this.deviceConnected = false,
    this.liveSession = false,
    this.uploadId = 'drive-1',
    this.ownerId,
  });

  BackupAccount? connectAccount;
  bool deviceConnected;
  bool liveSession;
  String? uploadId;
  List<int>? downloadBytes;
  String? ownerId;

  /// The Google account this fake is connected to. Real file ids only resolve
  /// inside one account, so the service now carries this alongside every id.
  String accountKey = 'acc-1';

  final List<String> uploadedFolders = [];
  final List<String?> uploadedSubfolders = [];
  final List<String> uploaded = [];
  final List<String> downloaded = [];
  int connectCalls = 0;
  int disconnectCalls = 0;
  int restoreCalls = 0;

  @override
  bool get hasLiveSession => liveSession;

  @override
  String? get liveAccountKey => liveSession ? accountKey : null;

  @override
  Future<String?> connectedAccountKey() async =>
      deviceConnected ? accountKey : null;

  @override
  Future<bool> isDeviceConnected() async => deviceConnected;

  @override
  Future<String?> connectedEmail() async => connectAccount?.email;

  @override
  Future<String?> connectedOwnerId() async => ownerId;

  @override
  Future<BackupAccount?> connect({required String ownerAccountId}) async {
    connectCalls++;
    if (connectAccount != null) {
      deviceConnected = true;
      liveSession = true;
      ownerId = ownerAccountId;
    }
    return connectAccount;
  }

  @override
  Future<BackupAccount?> restoreSession() async {
    restoreCalls++;
    if (deviceConnected) liveSession = true;
    return liveSession ? connectAccount : null;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
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
    String? subfolder,
    String? replaceRemoteId,
    String? replaceInAccountKey,
  }) async {
    uploaded.add(fileName);
    uploadedFolders.add(accountFolder);
    uploadedSubfolders.add(subfolder);
    return uploadId;
  }

  /// Set to have the fake answer "no such file" (a 404) instead of merely
  /// failing, so a test can exercise the deleted-from-Drive path.
  bool reportGone = false;

  @override
  Future<RemoteFetch> download(String fileId, {required String expectedAccountKey}) async {
    downloaded.add(fileId);
    if (reportGone) return const RemoteFetch.gone();
    final bytes = downloadBytes;
    return bytes == null ? const RemoteFetch.unavailable() : RemoteFetch.bytes(bytes);
  }

  bool failDeletes = false;

  final List<String> deletedRemote = [];

  @override
  Future<bool> deleteRemote(String remoteId, {required String expectedAccountKey}) async {
    if (failDeletes) return false;
    deletedRemote.add(remoteId);
    return true;
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

  /// [uid] is the record's OWNER (which becomes the Drive folder); the bytes
  /// are always imported under `u1` by these tests, so the path is scoped to
  /// that regardless — the two are deliberately different in the folder test.
  MediaObject makeObject({String id = 'm1', String? remoteId, String uid = 'u1'}) =>
      MediaObject(
        id: id,
        ownerUid: uid,
        kind: MediaKind.moment,
        relativePath: 'media/u1/moments/$id.jpg',
        mimeType: 'image/jpeg',
        byteSize: 3,
        contentHash: 'h',
        capturedAt: DateTime(2026, 1, 1),
        remoteId: remoteId,
      );

  MediaService buildService(
    _FakeDriveClient client,
    InMemoryMediaRegistry registry, {
    String? account = 'u1',
  }) =>
      MediaService(
        store: store,
        registry: registry,
        preferences: InMemoryMediaPreferencesRepository(),
        backup: client,
        currentAccountId: () => account,
      );

  group('connect / disconnect', () {
    test('connectDrive returns true and marks the device connected', () async {
      final client = _FakeDriveClient(connectAccount: const BackupAccount(id: '1', email: 'x@e.com'));
      final service = buildService(client, InMemoryMediaRegistry());

      expect(await service.connectBackup(), isTrue);
      expect(client.connectCalls, 1);
      expect(await service.isBackupConnected(), isTrue);
      expect(await service.connectedBackupAccount(), 'x@e.com');
    });

    test('connectDrive returns false on cancel', () async {
      final client = _FakeDriveClient(connectAccount: null);
      expect(await buildService(client, InMemoryMediaRegistry()).connectBackup(), isFalse);
    });

    test('disconnectDrive revokes the device connection', () async {
      final client = _FakeDriveClient(deviceConnected: true, liveSession: true);
      await buildService(client, InMemoryMediaRegistry()).disconnectBackup();
      expect(client.disconnectCalls, 1);
      expect(await client.isDeviceConnected(), isFalse);
    });

    test('supportsDrive reflects whether a client is wired', () async {
      expect(buildService(_FakeDriveClient(), InMemoryMediaRegistry()).supportsBackup, isTrue);
      final withoutDrive = MediaService(
        store: store,
        registry: InMemoryMediaRegistry(),
        preferences: InMemoryMediaPreferencesRepository(),
      );
      expect(withoutDrive.supportsBackup, isFalse);
    });
  });

  group('background upload of pending photos', () {
    // The photo taken while this device couldn't reach Drive (offline, or
    // before Drive was connected here). Without this pass it stayed on this
    // phone until someone tapped "Back up now", and the account's other
    // devices showed a record with no image.
    test('pushes a local photo the account does not have yet, into the '
        "account's Moments folder", () async {
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', owner: 'u1');
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject());
      final client = _FakeDriveClient(
        connectAccount: const BackupAccount(id: '1', email: 'x@e.com'),
        deviceConnected: true,
        ownerId: 'u1',
        uploadId: 'drive-xyz',
      );
      final service = buildService(client, registry);

      await service.uploadPendingInBackground();

      expect(client.uploadedFolders, ['u1'], reason: 'keyed by account, not device');
      expect(client.uploadedSubfolders, ['Moments']);
      final record = await registry.get('m1');
      expect(record!.remoteId, 'drive-xyz');
      expect(record.remoteBackup, BackupState.done);
      expect(record.remoteAccountKey, 'acc-1');
    });

    test("skips a record whose bytes live only on another device", () async {
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject()); // no local file for it here
      final client = _FakeDriveClient(
        connectAccount: const BackupAccount(id: '1', email: 'x@e.com'),
        deviceConnected: true,
        liveSession: true,
        ownerId: 'u1',
      );
      await buildService(client, registry).uploadPendingInBackground();

      expect(client.uploaded, isEmpty);
      expect((await registry.get('m1'))!.remoteBackup, BackupState.pending,
          reason: 'still pending — the device holding the bytes will push it');
    });

    test('respects auto-upload being off, and a device with no connection',
        () async {
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', owner: 'u1');
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject());

      final off = _FakeDriveClient(deviceConnected: true, liveSession: true, ownerId: 'u1');
      final prefs = InMemoryMediaPreferencesRepository();
      await prefs.save(const MediaStoragePreferences(autoUploadToDrive: false));
      await MediaService(
        store: store,
        registry: registry,
        preferences: prefs,
        backup: off,
        currentAccountId: () => 'u1',
      ).uploadPendingInBackground();
      expect(off.uploaded, isEmpty);

      final unconnected = _FakeDriveClient();
      await buildService(unconnected, registry).uploadPendingInBackground();
      expect(unconnected.uploaded, isEmpty);
      expect(unconnected.restoreCalls, 0, reason: 'never prompts or restores');
    });

    test('overlapping calls share one pass (no duplicate Drive files)', () async {
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', owner: 'u1');
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject());
      final client = _FakeDriveClient(deviceConnected: true, liveSession: true, ownerId: 'u1');
      final service = buildService(client, registry);

      await Future.wait([
        service.uploadPendingInBackground(),
        service.uploadPendingInBackground(),
      ]);

      expect(client.uploaded, hasLength(1));
    });
  });

  test('cloud file names lead with the capture time', () {
    final name = MediaService.remoteFileName(MediaObject(
      id: 'abcdef1234567890',
      ownerUid: 'u1',
      kind: MediaKind.moment,
      relativePath: 'media/u1/moments/abcdef1234567890.png',
      mimeType: 'image/png',
      byteSize: 1,
      contentHash: 'h',
      capturedAt: DateTime(2026, 9, 25, 11, 15, 3),
    ));
    expect(name, 'ZIVO 2026-09-25 11.15.03 abcdef12.png');
  });

  group('backupNow (manual)', () {
    test('uploads pending media to the per-account folder and records the id', () async {
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', owner: 'u1');
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject(uid: 'acct-9'));
      final client = _FakeDriveClient(deviceConnected: true, liveSession: true, uploadId: 'drive-xyz', ownerId: 'u1');
      final service = buildService(client, registry);

      final pushed = await service.backupNow();

      expect(pushed, 1);
      expect(client.uploaded, ['ZIVO 2026-01-01 00.00.00 m1.jpg']);
      expect(client.uploadedFolders, ['acct-9']); // per-account subfolder
      expect((await registry.get('m1'))!.remoteId, 'drive-xyz');
      expect((await registry.get('m1'))!.remoteBackup, BackupState.done);
    });

    test('does nothing when Drive is not connected on this device', () async {
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', owner: 'u1');
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject());
      final client = _FakeDriveClient(deviceConnected: false, liveSession: false);
      final service = buildService(client, registry);

      expect(await service.backupNow(), 0);
      expect(client.uploaded, isEmpty);
    });

    test('restores the session first when connected but not live (Back up now)', () async {
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', owner: 'u1');
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject());
      final client = _FakeDriveClient(
        connectAccount: const BackupAccount(id: '1', email: 'x@e.com'),
        deviceConnected: true,
        liveSession: false,
        ownerId: 'u1',
      );
      final service = buildService(client, registry);

      await service.backupNow();
      expect(client.restoreCalls, 1);
      expect(client.uploaded, ['ZIVO 2026-01-01 00.00.00 m1.jpg']);
    });
  });

  group('resolveOrFetch never prompts', () {
    const ref = 'media/u1/moments/m1.jpg';

    test('returns the local file without downloading when it exists', () async {
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1', owner: 'u1');
      final client = _FakeDriveClient(deviceConnected: true, liveSession: true);
      final file = await buildService(client, InMemoryMediaRegistry()).resolveOrFetch(ref);
      expect(file!.existsSync(), isTrue);
      expect(client.downloaded, isEmpty);
    });

    test('does NOT touch Drive when no session is live (passive read)', () async {
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject(remoteId: 'd1'));
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
      await registry.put(makeObject(remoteId: 'd1'));
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
      await registry.put(makeObject(id: 'm1', remoteId: 'd1'));
      await registry.put(makeObject(id: 'm2')); // no drive backup → skipped
      final client = _FakeDriveClient(deviceConnected: true, liveSession: true, ownerId: 'u1')
        ..downloadBytes = [7];
      final service = buildService(client, registry);

      final fetched = await service.syncFromBackup();
      expect(fetched, 1);
      expect(client.downloaded, ['d1']);
      expect((await store.resolve('media/u1/moments/m1.jpg'))!.existsSync(), isTrue);
    });

    test('does nothing when Drive is not connected', () async {
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject(remoteId: 'd1'));
      final client = _FakeDriveClient(deviceConnected: false, liveSession: false);
      expect(await buildService(client, registry).syncFromBackup(), 0);
    });
  });
}
