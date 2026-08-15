import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/notes/data/firestore_note_repository.dart';
import 'package:zivo/features/notes/domain/note.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

Note _make(
  String id, {
  String body = 'Body',
  DateTime? updatedAt,
  String? title,
}) => Note(
  id: id,
  body: body,
  updatedAt: updatedAt ?? DateTime(2026, 1, 1, 9),
  title: title,
);

void main() {
  group('FirestoreNoteRepository', () {
    test(
      'add writes a doc with the right fields and surfaces via watchAll',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreNoteRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final seen = <List<Note>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        final note = _make(
          'n1',
          body: 'Visa appointment notes',
          title: 'Visa',
          updatedAt: DateTime(2026, 1, 2, 10),
        );
        await repo.add(note);
        await Future<void>.delayed(Duration.zero);

        final doc = await firestore
            .collection('users')
            .doc('test-uid')
            .collection('notes')
            .doc('n1')
            .get();
        final data = doc.data()!;
        expect(data['body'], 'Visa appointment notes');
        expect(data['title'], 'Visa');
        expect(data['updatedAt'], Timestamp.fromDate(note.updatedAt));
        expect(data['schemaVersion'], 1);
        expect(data['createdAt'], isA<Timestamp>());

        expect(seen.last, hasLength(1));
        expect(seen.last.single.id, 'n1');

        await sub.cancel();
      },
    );

    test('the domain updatedAt round-trips through watchAll', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreNoteRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      final updatedAt = DateTime(2026, 3, 4, 15, 30);
      await repo.add(_make('n1', updatedAt: updatedAt));

      final notes = await repo.watchAll().first;
      expect(notes.single.updatedAt, updatedAt);
    });

    test('watchAll returns notes newest-updated first', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreNoteRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('older', updatedAt: DateTime(2026, 1, 1)));
      await repo.add(_make('newer', updatedAt: DateTime(2026, 1, 5)));

      final notes = await repo.watchAll().first;
      expect(notes.map((n) => n.id).toList(), ['newer', 'older']);
    });

    test('a title-less note round-trips with title null', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreNoteRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('n1'));

      final notes = await repo.watchAll().first;
      expect(notes.single.title, isNull);
    });

    test(
      'signed-out uid source emits an empty list and guards writes',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreNoteRepository(
          firestore: firestore,
          uidSource: UidSource(
            currentUid: () => null,
            uidChanges: Stream.value(null),
          ),
        );

        final notes = await repo.watchAll().first;
        expect(notes, isEmpty);

        expect(() => repo.add(_make('n1')), throwsStateError);
      },
    );
  });
}
