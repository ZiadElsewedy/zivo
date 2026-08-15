import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/moments/data/firestore_moment_repository.dart';
import 'package:zivo/features/moments/domain/moment.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

Moment _make(
  String id, {
  String caption = 'Caption',
  DateTime? takenAt,
  String? imagePath,
  String? location,
}) => Moment(
  id: id,
  caption: caption,
  takenAt: takenAt ?? DateTime(2026, 1, 1, 9),
  imagePath: imagePath,
  location: location,
);

void main() {
  group('FirestoreMomentRepository', () {
    test(
      'add writes a doc with the right fields and surfaces via watchAll',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreMomentRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final seen = <List<Moment>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        final moment = _make(
          'm1',
          caption: 'First sketch of the ZIVO home screen.',
          takenAt: DateTime(2026, 1, 2, 10),
          imagePath: '/tmp/pic.jpg',
          location: 'Studio',
        );
        await repo.add(moment);
        await Future<void>.delayed(Duration.zero);

        final doc = await firestore
            .collection('users')
            .doc('test-uid')
            .collection('moments')
            .doc('m1')
            .get();
        final data = doc.data()!;
        expect(data['caption'], 'First sketch of the ZIVO home screen.');
        expect(data['takenAt'], Timestamp.fromDate(moment.takenAt));
        expect(data['imagePath'], '/tmp/pic.jpg');
        expect(data['location'], 'Studio');
        expect(data['schemaVersion'], 1);
        expect(data['createdAt'], isA<Timestamp>());
        expect(data['updatedAt'], isA<Timestamp>());

        expect(seen.last, hasLength(1));
        expect(seen.last.single.id, 'm1');

        await sub.cancel();
      },
    );

    test('the domain takenAt round-trips through watchAll', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreMomentRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      final takenAt = DateTime(2026, 3, 4, 15, 30);
      await repo.add(_make('m1', takenAt: takenAt));

      final moments = await repo.watchAll().first;
      expect(moments.single.takenAt, takenAt);
    });

    test('imagePath round-trips when present', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreMomentRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('m1', imagePath: '/tmp/pic.jpg'));

      final moments = await repo.watchAll().first;
      expect(moments.single.imagePath, '/tmp/pic.jpg');
    });

    test('imagePath round-trips as null when absent', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreMomentRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('m1'));

      final moments = await repo.watchAll().first;
      expect(moments.single.imagePath, isNull);
    });

    test('a location-less moment round-trips with location null', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreMomentRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('m1'));

      final moments = await repo.watchAll().first;
      expect(moments.single.location, isNull);
    });

    test('watchAll returns moments newest-taken first', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreMomentRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('older', takenAt: DateTime(2026, 1, 1)));
      await repo.add(_make('newer', takenAt: DateTime(2026, 1, 5)));

      final moments = await repo.watchAll().first;
      expect(moments.map((m) => m.id).toList(), ['newer', 'older']);
    });

    test(
      'signed-out uid source emits an empty list and guards writes',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreMomentRepository(
          firestore: firestore,
          uidSource: UidSource(
            currentUid: () => null,
            uidChanges: Stream.value(null),
          ),
        );

        final moments = await repo.watchAll().first;
        expect(moments, isEmpty);

        expect(() => repo.add(_make('m1')), throwsStateError);
      },
    );
  });
}
