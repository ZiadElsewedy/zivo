import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/media/data/in_memory_media_preferences_repository.dart';
import 'package:zivo/core/media/data/in_memory_media_registry.dart';
import 'package:zivo/core/media/data/local_media_store.dart';
import 'package:zivo/core/media/domain/media_backup_provider.dart';
import 'package:zivo/core/media/domain/media_kind.dart';
import 'package:zivo/core/media/domain/media_object.dart';
import 'package:zivo/core/media/domain/media_resolution.dart';
import 'package:zivo/core/media/media_service.dart';

/// A [MediaBackupProvider] that models what the other fakes in this folder
/// deliberately abstract away: **files belong to one cloud account**.
///
/// Every other Drive fake here answers `download` from a single scripted byte
/// list, which quietly assumes the id being asked for is always resolvable —
/// exactly the assumption the production bug was built on. This one keeps a
/// separate file table per account key, so asking Drive #2 for a file id minted
/// by Drive #1 fails the way the real API fails (404 → null), with no scripting
/// required. The switch is what the test drives; the failure is emergent.
class _MultiAccountDrive implements MediaBackupProvider {
  _MultiAccountDrive({required this.platformAccountKey});

  /// Which Google account the platform hands back on the next
  /// authenticate/lightweight-restore. Changing this models the user picking a
  /// different Google account (or the system account changing underneath us).
  String platformAccountKey;

  /// accountKey → (fileId → bytes). Each account is a separate universe.
  final Map<String, Map<String, List<int>>> files = {};

  String? _liveKey;
  String? _connectedKey;
  String? _ownerUid;
  int _seq = 0;

  /// Every download the service actually attempted, as `accountKey/fileId` —
  /// so a test can assert the service never issued a cross-account request at
  /// all, rather than merely that it recovered from one.
  final List<String> downloadAttempts = [];
  final List<String> uploadedTo = [];

  /// Fired once the upload has picked its destination but before it returns —
  /// the window a real account switch would land in. Lets a test swap the live
  /// session out from under an upload that is already in flight.
  void Function()? onUploadInFlight;

  Map<String, List<int>> _filesFor(String key) => files.putIfAbsent(key, () => {});

  @override
  bool get hasLiveSession => _liveKey != null;

  @override
  String? get liveAccountKey => _liveKey;

  @override
  Future<String?> connectedAccountKey() async => _connectedKey;

  @override
  Future<bool> isDeviceConnected() async => _connectedKey != null;

  @override
  Future<String?> connectedEmail() async =>
      _connectedKey == null ? null : '$_connectedKey@gmail.com';

  @override
  Future<String?> connectedOwnerId() async => _ownerUid;

  @override
  Future<BackupAccount?> connect({required String ownerAccountId}) async {
    _connectedKey = platformAccountKey;
    _liveKey = platformAccountKey;
    _ownerUid = ownerAccountId;
    return BackupAccount(id: platformAccountKey, email: '$platformAccountKey@gmail.com');
  }

  /// Deliberately models the **unguarded** provider: a real
  /// `attemptLightweightAuthentication` hands back whichever Google account
  /// the platform considers current, which need not be the one ZIVO recorded.
  /// The fake binds to it without complaint precisely so the test proves the
  /// *service* refuses to use a session belonging to another account, rather
  /// than proving the fake is careful.
  @override
  Future<BackupAccount?> restoreSession() async {
    if (_connectedKey == null) return null;
    _liveKey = platformAccountKey;
    return BackupAccount(id: _liveKey!, email: '$_liveKey@gmail.com');
  }

  @override
  Future<void> disconnect() async {
    _liveKey = null;
    _connectedKey = null;
    _ownerUid = null;
  }

  @override
  Future<String?> upload({
    required File file,
    required String fileName,
    required String mimeType,
    required String accountFolder,
    String? replaceRemoteId,
    String? replaceInAccountKey,
  }) async {
    final key = _liveKey;
    if (key == null) return null;
    final bytes = await file.readAsBytes();
    // The destination is fixed at this point: a real request already carries
    // the old account's bearer token, so bytes land in `key` no matter what
    // the app does next.
    final hook = onUploadInFlight;
    onUploadInFlight = null;
    hook?.call();

    // An in-place update is only possible when the id lives in THIS account.
    if (replaceRemoteId != null &&
        (replaceInAccountKey == null || replaceInAccountKey == key) &&
        _filesFor(key).containsKey(replaceRemoteId)) {
      _filesFor(key)[replaceRemoteId] = bytes;
      uploadedTo.add('$key/$replaceRemoteId');
      return replaceRemoteId;
    }
    // A foreign id cannot be updated. The real client must fall back to a
    // create here; returning null instead is finding C3.
    final id = 'file-${++_seq}';
    _filesFor(key)[id] = bytes;
    uploadedTo.add('$key/$id');
    return id;
  }

  /// When true, the account answers "no such file" definitively (a 404) rather
  /// than going quiet — the difference between a deleted file and a bad line.
  bool answersDefinitively = true;

  @override
  Future<RemoteFetch> download(String remoteId,
      {required String expectedAccountKey}) async {
    final key = _liveKey;
    if (key == null) return const RemoteFetch.unavailable();
    downloadAttempts.add('$key/$remoteId');
    if (expectedAccountKey != key) return const RemoteFetch.unavailable();
    final bytes = _filesFor(key)[remoteId];
    if (bytes != null) return RemoteFetch.bytes(bytes);
    return answersDefinitively
        ? const RemoteFetch.gone()
        : const RemoteFetch.unavailable();
  }

  @override
  Future<bool> deleteRemote(String remoteId, {required String expectedAccountKey}) async {
    final key = _liveKey;
    if (key == null || expectedAccountKey != key) return false;
    return _filesFor(key).remove(remoteId) != null;
  }
}

void main() {
  late Directory root;
  late Directory srcDir;
  late LocalMediaStore store;
  late InMemoryMediaRegistry registry;
  late _MultiAccountDrive drive;
  late MediaService service;

  const ref = 'media/moments/m1.jpg';

  setUp(() {
    root = Directory.systemTemp.createTempSync('zivo_switch_root');
    srcDir = Directory.systemTemp.createTempSync('zivo_switch_src');
    store = LocalMediaStore(rootOverride: root);
    registry = InMemoryMediaRegistry();
    drive = _MultiAccountDrive(platformAccountKey: 'drive-1');
    service = MediaService(
      store: store,
      registry: registry,
      preferences: InMemoryMediaPreferencesRepository(),
      backup: drive,
      currentAccountId: () => 'u1',
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (srcDir.existsSync()) srcDir.deleteSync(recursive: true);
  });

  /// Captures `id` and waits for the background tail (registry + auto-upload).
  Future<void> captureAndSettle(String id) async {
    final f = File('${srcDir.path}/$id.jpg')..writeAsBytesSync([1, 2, 3]);
    await service.capture(
      sourcePath: f.path,
      kind: MediaKind.moment,
      id: id,
      ownerUid: 'u1',
    );
    await service.settleCaptures();
    // The auto-upload is fire-and-forget behind the tail; give it a turn.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  /// The user disconnects one Google account and connects another.
  Future<void> switchDriveTo(String key) async {
    await service.disconnectBackup();
    drive.platformAccountKey = key;
    expect(await service.connectBackup(), isTrue);
  }

  Future<void> deleteLocalBytes() async {
    final file = await store.resolve(ref);
    if (file != null && file.existsSync()) file.deleteSync();
  }

  group('records written before account keys existed', () {
    /// The migration case: `driveAccountKey` is absent, which means *unknown*.
    /// Unknown is given the benefit of the doubt exactly once — the common
    /// case is that the user never switched — and the answer is then recorded
    /// so it never has to be guessed again.
    Future<void> seedLegacyRecord(String remoteId) async {
      await registry.put(MediaObject(
        id: 'm1',
        ownerUid: 'u1',
        kind: MediaKind.moment,
        relativePath: ref,
        mimeType: 'image/jpeg',
        byteSize: 3,
        contentHash: 'h',
        capturedAt: DateTime(2026, 1, 1),
        remoteBackup: BackupState.done,
        remoteId: remoteId,
        // remoteAccountKey deliberately absent
      ));
    }

    test('a legacy record that resolves is stamped with the account that '
        'served it', () async {
      await service.connectBackup(); // drive-1
      drive.files['drive-1'] = {'legacy-1': [7, 8, 9]};
      await seedLegacyRecord('legacy-1');

      final resolution = await service.resolveWithStatus(ref);
      expect(resolution.availability, MediaAvailability.onDevice);
      expect(resolution.file!.readAsBytesSync(), [7, 8, 9]);

      // Backfilled on the strength of a transfer that actually worked — no
      // batch job, and no guess.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await registry.get('m1'))!.remoteAccountKey, 'drive-1');
    });

    test('a legacy record whose bytes are not in the connected account is '
        'left unstamped and queued for backup', () async {
      await service.connectBackup(); // drive-1 holds nothing for this id
      await seedLegacyRecord('legacy-1');

      final resolution = await service.resolveWithStatus(ref);
      expect(resolution.hasBytes, isFalse);
      expect((await registry.get('m1'))!.remoteAccountKey, isNull,
          reason: 'a failed fetch proves nothing about where the file lives');
    });
  });

  group('a file deleted inside Drive', () {
    test('stops being reported as arriving, and the dead reference is dropped',
        () async {
      await service.connectBackup();
      await captureAndSettle('m1');
      final remoteId = (await registry.get('m1'))!.remoteId!;
      await deleteLocalBytes();

      // The user tidies their Drive and removes the file by hand.
      drive.files['drive-1']!.remove(remoteId);

      final resolution = await service.resolveWithStatus(ref);

      expect(resolution.availability, MediaAvailability.nowhere,
          reason: 'a deleted file is not "on its way"');
      final record = await registry.get('m1');
      expect(record!.remoteId, isNull, reason: 'the reference is dead');
      expect(record.remoteAccountKey, isNull);
      expect(record.remoteBackup, BackupState.failed);
    });

    test('re-enters the backup work list so a device holding the bytes '
        'restores it', () async {
      await service.connectBackup();
      await captureAndSettle('m1');
      final remoteId = (await registry.get('m1'))!.remoteId!;
      drive.files['drive-1']!.remove(remoteId);

      // A read is what discovers the deletion; the local copy is still here,
      // which is exactly the device that can put it back.
      final localBytes = (await store.resolve(ref))!.readAsBytesSync();
      await deleteLocalBytes();
      await service.resolveWithStatus(ref);
      await store.writeBytes(ref, localBytes); // this device still had it

      expect(await service.backupNow(), 1,
          reason: 'a photo whose backup was deleted needs backing up again');
      expect(drive.files['drive-1'], hasLength(1));

      final record = await registry.get('m1');
      expect(record!.remoteBackup, BackupState.done);
      expect(record.remoteAccountKey, 'drive-1');
      expect(drive.files['drive-1']!.containsKey(record.remoteId), isTrue);
    });

    test('a network failure is NOT mistaken for a deletion', () async {
      await service.connectBackup();
      await captureAndSettle('m1');
      final remoteId = (await registry.get('m1'))!.remoteId!;
      await deleteLocalBytes();

      // The file is still in Drive; the line is down, so no answer comes back.
      drive.answersDefinitively = false;
      drive.files['drive-1']!.remove(remoteId);

      final resolution = await service.resolveWithStatus(ref);

      expect(resolution.availability, MediaAvailability.cloudOnly,
          reason: 'silence means try again later, not "it is gone"');
      final record = await registry.get('m1');
      expect(record!.remoteId, remoteId,
          reason: 'a good reference must survive a bad connection');
      expect(record.remoteBackup, BackupState.done);
    });

    test('Sync drops references Drive says are gone instead of retrying them '
        'every run', () async {
      await service.connectBackup();
      await captureAndSettle('m1');
      final remoteId = (await registry.get('m1'))!.remoteId!;
      await deleteLocalBytes();
      drive.files['drive-1']!.remove(remoteId);

      expect(await service.syncFromBackup(), 0);
      expect((await registry.get('m1'))!.remoteId, isNull);

      // Second run has nothing left to ask for.
      drive.downloadAttempts.clear();
      expect(await service.syncFromBackup(), 0);
      expect(drive.downloadAttempts, isEmpty);
    });
  });

  group('Drive account switch', () {
    test('a photo backed up to Drive #1 is never resolved against Drive #2', () async {
      await service.connectBackup();
      await captureAndSettle('m1');
      final backedUp = await registry.get('m1');
      expect(backedUp!.remoteBackup, BackupState.done, reason: 'precondition');
      expect(drive.files['drive-1'], hasLength(1), reason: 'precondition');

      await deleteLocalBytes(); // reinstall / second device
      await switchDriveTo('drive-2');

      final resolution = await service.resolveWithStatus(ref);

      // The bytes are NOT fetchable here, and the service must know that from
      // the record rather than by firing a doomed request at the wrong account.
      expect(drive.downloadAttempts, isEmpty);
      expect(resolution.availability, MediaAvailability.otherAccount);
      expect(resolution.hasBytes, isFalse);
    });

    test('connecting a new Drive account queues the whole library for re-upload',
        () async {
      await service.connectBackup();
      await captureAndSettle('m1');
      expect(drive.files['drive-1'], hasLength(1), reason: 'precondition');

      await switchDriveTo('drive-2'); // local bytes still present

      expect(
        await service.backupNow(),
        1,
        reason: 'a record backed up to another account still needs backing up here',
      );
      expect(drive.files['drive-2'], hasLength(1));

      final record = await registry.get('m1');
      expect(record!.remoteAccountKey, 'drive-2');
      expect(record.remoteId, isNot(equals(drive.files['drive-1']!.keys.single)));
      expect(record.remoteBackup, BackupState.done);
    });

    test('the re-uploaded copy is readable, and the Drive #1 copy is left intact',
        () async {
      await service.connectBackup();
      await captureAndSettle('m1');
      await switchDriveTo('drive-2');
      await service.backupNow();

      await deleteLocalBytes();
      final resolution = await service.resolveWithStatus(ref);

      expect(resolution.availability, MediaAvailability.onDevice);
      expect(resolution.file!.readAsBytesSync(), [1, 2, 3]);
      // Nothing was deleted from the account the user disconnected — the old
      // copy stays recoverable by reconnecting it.
      expect(drive.files['drive-1'], hasLength(1));
    });

    test('a session silently restored onto a different Google account is not '
        'used to resolve stored ids', () async {
      await service.connectBackup();
      await captureAndSettle('m1');
      await deleteLocalBytes();

      // App restart: the in-memory session is gone, the device is still
      // recorded as connected to drive-1 — but the platform's current Google
      // account has changed underneath us, so the silent restore comes back
      // holding drive-2.
      drive._liveKey = null;
      drive.platformAccountKey = 'drive-2';

      final resolution = await service.resolveWithStatus(ref);

      // The restore may well have bound to drive-2; what must not happen is
      // drive-1's file id being dereferenced against it.
      expect(drive.downloadAttempts, isEmpty);
      expect(resolution.hasBytes, isFalse);
      expect((await registry.get('m1'))!.remoteAccountKey, 'drive-1',
          reason: 'the record must stay attributed to the account that holds it');
    });

    test('an upload interrupted by an account switch is attributed to the '
        'account that actually received it', () async {
      await service.connectBackup();
      await captureAndSettle('m1');
      await switchDriveTo('drive-2');

      // The user disconnects and reconnects while the bytes are on the wire.
      drive.onUploadInFlight = () => drive._liveKey = 'drive-3';
      await service.backupNow();

      final record = await registry.get('m1');
      expect(drive.files['drive-2'], hasLength(1), reason: 'drive-2 got the bytes');
      expect(drive.files['drive-3'], anyOf(isNull, isEmpty));
      expect(
        record!.remoteAccountKey,
        anyOf(isNull, 'drive-2'),
        reason: 'a file id may only be attributed to the account that stored it',
      );
      if (record.remoteAccountKey == 'drive-2') {
        expect(drive.files['drive-2']!.containsKey(record.remoteId), isTrue);
      }
    });

    test('switching back to Drive #1 makes the original copy readable again',
        () async {
      await service.connectBackup();
      await captureAndSettle('m1');
      await deleteLocalBytes();

      await switchDriveTo('drive-2');
      expect((await service.resolveWithStatus(ref)).availability,
          MediaAvailability.otherAccount);

      await switchDriveTo('drive-1');
      final resolution = await service.resolveWithStatus(ref);

      expect(resolution.availability, MediaAvailability.onDevice);
      expect(resolution.file!.readAsBytesSync(), [1, 2, 3]);
    });
  });
}
