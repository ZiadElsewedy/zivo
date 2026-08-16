import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/university/data/firestore_university_repository.dart';
import 'package:zivo/features/university/domain/university_item.dart';
import 'package:zivo/features/university/domain/university_item_type.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

UniversityItem _make(
  String id, {
  DateTime? createdAt,
  DateTime? due,
  String? courseName,
  UniversityItemType type = UniversityItemType.assignment,
}) => UniversityItem(
  id: id,
  title: 'Item $id',
  type: type,
  createdAt: createdAt ?? DateTime(2026, 1, 1),
  due: due,
  courseName: courseName,
);

void main() {
  group('FirestoreUniversityRepository', () {
    test(
      'add writes a doc with the right fields and surfaces via watchAll',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreUniversityRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final seen = <List<UniversityItem>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        final item = _make(
          'u1',
          due: DateTime(2026, 1, 5),
          courseName: 'Algorithms',
          type: UniversityItemType.exam,
        );
        await repo.add(item);
        await Future<void>.delayed(Duration.zero);

        final doc = await firestore
            .collection('users')
            .doc('test-uid')
            .collection('universityItems')
            .doc('u1')
            .get();
        final data = doc.data()!;
        expect(data['title'], 'Item u1');
        expect(data['type'], 'exam');
        expect(data['createdAt'], isA<Timestamp>());
        expect((data['due'] as Timestamp).toDate(), DateTime(2026, 1, 5));
        expect(data['courseName'], 'Algorithms');
        expect(data['done'], isFalse);
        expect(data['schemaVersion'], 1);
        expect(data['updatedAt'], isA<Timestamp>());

        expect(seen.last, hasLength(1));
        expect(seen.last.single.id, 'u1');
        expect(seen.last.single.type, UniversityItemType.exam);

        await sub.cancel();
      },
    );

    test('an unknown stored type falls back to assignment', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('users')
          .doc('test-uid')
          .collection('universityItems')
          .doc('u1')
          .set({
            'title': 'Mystery item',
            'type': 'quiz',
            'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
            'due': null,
            'courseName': null,
            'done': false,
            'schemaVersion': 1,
          });

      final repo = FirestoreUniversityRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      final items = await repo.watchAll().first;
      expect(items.single.type, UniversityItemType.assignment);
    });

    test(
      'watchAll orders by due ascending, with an undated item last (not dropped)',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreUniversityRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        await repo.add(_make('soonest', due: DateTime(2026, 1, 5)));
        await repo.add(_make('undated'));
        await repo.add(_make('later', due: DateTime(2026, 1, 20)));

        final items = await repo.watchAll().first;
        expect(items.map((i) => i.id).toList(), [
          'soonest',
          'later',
          'undated',
        ]);
      },
    );

    test(
      'setDone flips only the done field and is observed on the stream',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreUniversityRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        await repo.add(_make('u1', courseName: 'Algorithms'));

        final seen = <List<UniversityItem>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        await repo.setDone('u1', true);
        await Future<void>.delayed(Duration.zero);

        final updated = seen.last.single;
        expect(updated.done, isTrue);
        expect(updated.courseName, 'Algorithms');
        expect(updated.title, 'Item u1');

        await sub.cancel();
      },
    );

    test(
      'update replaces the editable fields, preserving id/createdAt, '
      'and is observed on the stream',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreUniversityRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        await repo.add(
          _make(
            'u1',
            createdAt: DateTime(2026, 1, 1),
            due: DateTime(2026, 1, 5),
            courseName: 'Algorithms',
          ),
        );

        final seen = <List<UniversityItem>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        final original = seen.last.single;
        await repo.update(
          original.copyWith(
            title: 'Revised title',
            type: UniversityItemType.exam,
            due: DateTime(2026, 2, 1),
            courseName: 'Data Structures',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final updated = seen.last.single;
        expect(updated.id, 'u1');
        expect(updated.createdAt, DateTime(2026, 1, 1));
        expect(updated.title, 'Revised title');
        expect(updated.type, UniversityItemType.exam);
        expect(updated.due, DateTime(2026, 2, 1));
        expect(updated.courseName, 'Data Structures');

        await sub.cancel();
      },
    );

    test('remove deletes the doc and is observed on the stream', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreUniversityRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('u1'));
      await repo.add(_make('u2'));

      final seen = <List<UniversityItem>>[];
      final sub = repo.watchAll().listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      await repo.remove('u1');
      await Future<void>.delayed(Duration.zero);

      expect(seen.last.map((i) => i.id), ['u2']);

      await sub.cancel();
    });

    test(
      'signed-out uid source emits an empty list and guards writes',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreUniversityRepository(
          firestore: firestore,
          uidSource: UidSource(
            currentUid: () => null,
            uidChanges: Stream.value(null),
          ),
        );

        final items = await repo.watchAll().first;
        expect(items, isEmpty);

        expect(() => repo.add(_make('u1')), throwsStateError);
        expect(() => repo.update(_make('u1')), throwsStateError);
        expect(() => repo.setDone('u1', true), throwsStateError);
        expect(() => repo.remove('u1'), throwsStateError);
      },
    );
  });
}
