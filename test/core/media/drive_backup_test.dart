import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/media/data/google_drive_target.dart';
import 'package:zivo/core/media/data/in_memory_media_preferences_repository.dart';
import 'package:zivo/core/media/data/in_memory_media_registry.dart';
import 'package:zivo/core/media/data/local_media_store.dart';
import 'package:zivo/core/media/domain/drive_backup_client.dart';
import 'package:zivo/core/media/domain/media_backup_target.dart';
import 'package:zivo/core/media/domain/media_kind.dart';
import 'package:zivo/core/media/domain/media_object.dart';
import 'package:zivo/core/media/domain/media_storage_preferences.dart';
import 'package:zivo/core/media/media_service.dart';

/// A scriptable [DriveBackupClient] — no real Google/network.
class _FakeDriveClient implements DriveBackupClient {
  _FakeDriveClient({this.account, this.connected = false, this.uploadId = 'drive-1'});

  DriveAccount? account;
  bool connected;
  String? uploadId;
  final List<String> uploaded = [];
  final List<String> downloaded = [];
  List<int>? downloadBytes;
  int disconnectCalls = 0;

  @override
  Future<DriveAccount?> connect() async {
    if (account != null) connected = true;
    return account;
  }

  @override
  Future<bool> isConnected() async => connected;

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    connected = false;
  }

  @override
  Future<String?> uploadImage({
    required File file,
    required String fileName,
    required String mimeType,
    String? replaceFileId,
  }) async {
    uploaded.add(fileName);
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

  MediaObject makeObject({String? driveFileId}) => MediaObject(
        id: 'm1',
        ownerUid: 'u1',
        kind: MediaKind.moment,
        relativePath: 'media/moments/m1.jpg',
        mimeType: 'image/jpeg',
        byteSize: 3,
        contentHash: 'h',
        capturedAt: DateTime(2026, 1, 1),
        driveFileId: driveFileId,
      );

  group('GoogleDriveTarget', () {
    test('uploads the resolved file and returns the Drive id', () async {
      // Put a real file at the object's relative path.
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1');
      final client = _FakeDriveClient(uploadId: 'drive-xyz');
      final target = GoogleDriveTarget(client: client, store: store);

      final result = await target.backup(makeObject());
      expect(result.succeeded, isTrue);
      expect(result.remoteId, 'drive-xyz');
      expect(client.uploaded, ['m1.jpg']);
    });

    test('fails when the local file is missing', () async {
      final client = _FakeDriveClient();
      final target = GoogleDriveTarget(client: client, store: store);
      final result = await target.backup(makeObject());
      expect(result.succeeded, isFalse);
      expect(client.uploaded, isEmpty);
    });

    test('fails when the client returns no id', () async {
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1');
      final client = _FakeDriveClient(uploadId: null);
      final target = GoogleDriveTarget(client: client, store: store);
      final result = await target.backup(makeObject());
      expect(result.succeeded, isFalse);
    });

    test('isConfigured reflects the client connection', () async {
      final client = _FakeDriveClient(connected: true);
      final target = GoogleDriveTarget(client: client, store: store);
      expect(await target.isConfigured(), isTrue);
    });
  });

  group('MediaService Drive connection', () {
    MediaService buildService(
      _FakeDriveClient client, {
      Future<bool> Function()? isUnmetered,
      InMemoryMediaPreferencesRepository? prefs,
    }) =>
        MediaService(
          store: store,
          registry: InMemoryMediaRegistry(),
          preferences: prefs ?? InMemoryMediaPreferencesRepository(),
          driveClient: client,
          isUnmetered: isUnmetered,
        );

    test('connectDrive records the account and enables backup', () async {
      final prefs = InMemoryMediaPreferencesRepository();
      final client = _FakeDriveClient(account: const DriveAccount(id: '1', email: 'x@e.com'));
      final service = buildService(client, prefs: prefs);

      final ok = await service.connectDrive();
      expect(ok, isTrue);
      final saved = await prefs.read();
      expect(saved.driveConnected, isTrue);
      expect(saved.driveBackupEnabled, isTrue);
      expect(saved.driveAccountEmail, 'x@e.com');
    });

    test('connectDrive returns false and records nothing on cancel', () async {
      final prefs = InMemoryMediaPreferencesRepository();
      final client = _FakeDriveClient(account: null);
      final service = buildService(client, prefs: prefs);

      expect(await service.connectDrive(), isFalse);
      expect((await prefs.read()).driveConnected, isFalse);
    });

    test('disconnectDrive revokes and clears the connection', () async {
      final prefs = InMemoryMediaPreferencesRepository(const MediaStoragePreferences(
        driveConnected: true,
        driveBackupEnabled: true,
        driveAccountEmail: 'x@e.com',
      ));
      final client = _FakeDriveClient(connected: true);
      final service = buildService(client, prefs: prefs);

      await service.disconnectDrive();
      expect(client.disconnectCalls, 1);
      final saved = await prefs.read();
      expect(saved.driveConnected, isFalse);
      expect(saved.driveBackupEnabled, isFalse);
      expect(saved.driveAccountEmail, isNull);
    });

    test('supportsDrive reflects whether a client is wired', () async {
      final withDrive = buildService(_FakeDriveClient());
      expect(withDrive.supportsDrive, isTrue);
      final withoutDrive = MediaService(
        store: store,
        registry: InMemoryMediaRegistry(),
        preferences: InMemoryMediaPreferencesRepository(),
      );
      expect(withoutDrive.supportsDrive, isFalse);
    });
  });

  group('runAutoBackupIfDue Wi-Fi gating', () {
    test('skips on a metered connection when Wi-Fi only is on', () async {
      final prefs = InMemoryMediaPreferencesRepository(MediaStoragePreferences(
        driveBackupEnabled: true,
        autoBackupEveryDays: 3,
        wifiOnly: true,
        lastBackupAt: DateTime(2026, 1, 1),
      ));
      final client = _FakeDriveClient(connected: true);
      final service = MediaService(
        store: store,
        registry: InMemoryMediaRegistry(),
        preferences: prefs,
        driveClient: client,
        targets: {BackupTargetId.drive: GoogleDriveTarget(client: client, store: store)},
        isUnmetered: () async => false,
      );

      await service.runAutoBackupIfDue(now: DateTime(2026, 1, 10));
      expect(client.uploaded, isEmpty);
    });

    test('runs on wifi when Wi-Fi only is on', () async {
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1');
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject());
      final prefs = InMemoryMediaPreferencesRepository(MediaStoragePreferences(
        driveBackupEnabled: true,
        autoBackupEveryDays: 3,
        wifiOnly: true,
        lastBackupAt: DateTime(2026, 1, 1),
      ));
      final client = _FakeDriveClient(connected: true);
      final service = MediaService(
        store: store,
        registry: registry,
        preferences: prefs,
        driveClient: client,
        targets: {BackupTargetId.drive: GoogleDriveTarget(client: client, store: store)},
        isUnmetered: () async => true,
      );

      await service.runAutoBackupIfDue(now: DateTime(2026, 1, 10));
      expect(client.uploaded, ['m1.jpg']);
    });
  });

  group('resolveOrFetch (second-device / reinstall download)', () {
    const ref = 'media/moments/m1.jpg';

    MediaService buildService(_FakeDriveClient client, InMemoryMediaRegistry registry) =>
        MediaService(
          store: store,
          registry: registry,
          preferences: InMemoryMediaPreferencesRepository(),
          driveClient: client,
        );

    test('returns the local file without downloading when it already exists', () async {
      await store.importFile(sourcePath: src('m.jpg'), kind: MediaKind.moment, id: 'm1');
      final client = _FakeDriveClient(connected: true);
      final service = buildService(client, InMemoryMediaRegistry());

      final file = await service.resolveOrFetch(ref);
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
      expect(client.downloaded, isEmpty);
    });

    test('downloads from Drive and writes locally when the file is missing', () async {
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject(driveFileId: 'd1'));
      final client = _FakeDriveClient(connected: true)..downloadBytes = [4, 5, 6];
      final service = buildService(client, registry);

      final file = await service.resolveOrFetch(ref);
      expect(client.downloaded, ['d1']);
      expect(file, isNotNull);
      expect(file!.readAsBytesSync(), [4, 5, 6]);
      // Now cached locally — a second call doesn't download again.
      await service.resolveOrFetch(ref);
      expect(client.downloaded, ['d1']);
    });

    test('returns null when there is no Drive backup for the media', () async {
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject()); // no driveFileId
      final client = _FakeDriveClient(connected: true);
      final service = buildService(client, registry);

      expect(await service.resolveOrFetch(ref), isNull);
      expect(client.downloaded, isEmpty);
    });

    test('returns null when Drive is not connected on this device', () async {
      final registry = InMemoryMediaRegistry();
      await registry.put(makeObject(driveFileId: 'd1'));
      final client = _FakeDriveClient(connected: false)..downloadBytes = [1];
      final service = buildService(client, registry);

      expect(await service.resolveOrFetch(ref), isNull);
      expect(client.downloaded, isEmpty);
    });
  });
}
