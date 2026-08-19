import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/core/media/data/firestore_media_preferences_repository.dart';
import 'package:zivo/core/media/data/firestore_media_registry.dart';
import 'package:zivo/core/media/domain/media_kind.dart';
import 'package:zivo/core/media/domain/media_object.dart';
import 'package:zivo/core/media/domain/media_storage_preferences.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

void main() {
  group('FirestoreMediaRegistry', () {
    test('put round-trips a MediaObject and pendingBackups filters by state', () async {
      final firestore = FakeFirebaseFirestore();
      final registry = FirestoreMediaRegistry(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );

      await registry.put(MediaObject(
        id: 'm1',
        ownerUid: 'u1',
        kind: MediaKind.moment,
        relativePath: 'media/moments/m1.jpg',
        mimeType: 'image/jpeg',
        byteSize: 10,
        contentHash: 'hash',
        capturedAt: DateTime(2026, 1, 2),
      ));
      await registry.put(MediaObject(
        id: 'm2',
        ownerUid: 'u1',
        kind: MediaKind.avatar,
        relativePath: 'media/avatars/m2.jpg',
        mimeType: 'image/jpeg',
        byteSize: 20,
        contentHash: 'hash2',
        capturedAt: DateTime(2026, 1, 3),
        drive: BackupState.done,
      ));

      final m1 = await registry.get('m1');
      expect(m1, isNotNull);
      expect(m1!.relativePath, 'media/moments/m1.jpg');
      expect(m1.kind, MediaKind.moment);
      expect(m1.drive, BackupState.pending);

      // m2 is fully backed up; only m1 remains pending.
      final pending = await registry.pendingBackups();
      expect(pending.map((m) => m.id), ['m1']);
    });
  });

  group('FirestoreMediaPreferencesRepository', () {
    test('save then read round-trips preferences', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreMediaPreferencesRepository(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );

      expect(await repo.read(), MediaStoragePreferences.defaults);

      await repo.save(const MediaStoragePreferences(
        saveToPhotos: true,
        driveBackupEnabled: true,
        driveConnected: true,
        driveAccountEmail: 'x@example.com',
        autoBackupEveryDays: 3,
        wifiOnly: false,
      ));

      final read = await repo.read();
      expect(read.saveToPhotos, isTrue);
      expect(read.driveBackupEnabled, isTrue);
      expect(read.driveConnected, isTrue);
      expect(read.driveAccountEmail, 'x@example.com');
      expect(read.autoBackupEveryDays, 3);
      expect(read.wifiOnly, isFalse);
    });

    test('watch emits defaults for the signed-out account', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreMediaPreferencesRepository(
        firestore: firestore,
        uidSource: UidSource(currentUid: () => null, uidChanges: const Stream.empty()),
      );
      expect(await repo.watch().first, MediaStoragePreferences.defaults);
    });
  });
}
