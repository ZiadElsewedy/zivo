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
        remoteBackup: BackupState.done,
      ));

      final m1 = await registry.get('m1');
      expect(m1, isNotNull);
      expect(m1!.relativePath, 'media/moments/m1.jpg');
      expect(m1.kind, MediaKind.moment);
      expect(m1.remoteBackup, BackupState.pending);

      // m2 is fully backed up; only m1 remains pending.
      final pending = await registry.pendingBackups();
      expect(pending.map((m) => m.id), ['m1']);
    });

    test('the Drive account key round-trips, and a record backed up to another '
        'account is still pending here', () async {
      final firestore = FakeFirebaseFirestore();
      final registry = FirestoreMediaRegistry(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );

      MediaObject backedUpTo(String id, String? accountKey) => MediaObject(
            id: id,
            ownerUid: 'u1',
            kind: MediaKind.moment,
            relativePath: 'media/moments/$id.jpg',
            mimeType: 'image/jpeg',
            byteSize: 10,
            contentHash: 'h',
            capturedAt: DateTime(2026, 1, 2),
            remoteBackup: BackupState.done,
            remoteId: 'file-$id',
            remoteAccountKey: accountKey,
          );

      await registry.put(backedUpTo('here', 'drive-1'));
      await registry.put(backedUpTo('elsewhere', 'drive-2'));
      await registry.put(backedUpTo('legacy', null)); // written pre-schema-2

      expect((await registry.get('here'))!.remoteAccountKey, 'drive-1');
      expect((await registry.get('legacy'))!.remoteAccountKey, isNull);

      // Connected to drive-1: the drive-2 copy is unreachable from here and
      // must be re-pushed; the legacy record's account is unknown, so it is
      // given the benefit of the doubt rather than re-uploaded on a guess.
      final pending = await registry.pendingBackups(forAccountKey: 'drive-1');
      expect(pending.map((m) => m.id), ['elsewhere']);

      // With nothing connected there is no destination to compare against, so
      // the answer falls back to the destination-agnostic one.
      expect(await registry.pendingBackups(), isEmpty);
    });

    test('refuses to file a record under an owner that is not the signed-in '
        'account', () async {
      final firestore = FakeFirebaseFirestore();
      final registry = FirestoreMediaRegistry(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );

      // `put` rejects synchronously — the caller never gets a Future to await,
      // so a swallowed background tail cannot hide the mistake.
      expect(
        () => registry.put(MediaObject(
          id: 'm1',
          ownerUid: 'local', // the old signed-out placeholder
          kind: MediaKind.moment,
          relativePath: 'media/moments/m1.jpg',
          mimeType: 'image/jpeg',
          byteSize: 10,
          contentHash: 'h',
          capturedAt: DateTime(2026, 1, 2),
        )),
        throwsStateError,
      );
      // Nothing was written to an unroutable path.
      expect(
        (await firestore.collection('users').doc('local').collection('media').get())
            .docs,
        isEmpty,
      );
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

      await repo.save(const MediaStoragePreferences(saveToPhotos: true));

      final read = await repo.read();
      expect(read.saveToPhotos, isTrue);
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
