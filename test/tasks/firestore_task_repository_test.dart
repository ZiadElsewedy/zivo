import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/tasks/data/firestore_task_repository.dart';
import 'package:zivo/features/tasks/domain/task.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

Task _make(
  String id, {
  DateTime? createdAt,
  DateTime? due,
  bool priority = false,
}) => Task(
  id: id,
  title: 'Task $id',
  createdAt: createdAt ?? DateTime(2026, 1, 1),
  due: due,
  priority: priority,
);

void main() {
  group('FirestoreTaskRepository', () {
    test(
      'add writes a doc with the right fields and surfaces via watchAll',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreTaskRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final seen = <List<Task>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        final task = _make('t1', due: DateTime(2026, 1, 5), priority: true);
        await repo.add(task);
        await Future<void>.delayed(Duration.zero);

        final doc = await firestore
            .collection('users')
            .doc('test-uid')
            .collection('tasks')
            .doc('t1')
            .get();
        final data = doc.data()!;
        expect(data['title'], 'Task t1');
        expect(data['createdAt'], isA<Timestamp>());
        expect((data['due'] as Timestamp).toDate(), DateTime(2026, 1, 5));
        expect(data['priority'], isTrue);
        expect(data['done'], isFalse);
        expect(data['schemaVersion'], 1);
        expect(data['updatedAt'], isA<Timestamp>());

        expect(seen.last, hasLength(1));
        expect(seen.last.single.id, 't1');

        await sub.cancel();
      },
    );

    test('watchAll returns tasks newest-first (createdAt desc)', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreTaskRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('older', createdAt: DateTime(2026, 1, 1)));
      await repo.add(_make('newer', createdAt: DateTime(2026, 1, 5)));

      final tasks = await repo.watchAll().first;
      expect(tasks.map((t) => t.id).toList(), ['newer', 'older']);
    });

    test(
      'setDone flips only the done field and is observed on the stream',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreTaskRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        await repo.add(_make('t1', priority: true));

        final seen = <List<Task>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        await repo.setDone('t1', true);
        await Future<void>.delayed(Duration.zero);

        final updated = seen.last.single;
        expect(updated.done, isTrue);
        expect(updated.priority, isTrue);
        expect(updated.title, 'Task t1');

        await sub.cancel();
      },
    );

    test(
      'signed-out uid source emits an empty list and guards writes',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreTaskRepository(
          firestore: firestore,
          uidSource: UidSource(
            currentUid: () => null,
            uidChanges: Stream.value(null),
          ),
        );

        final tasks = await repo.watchAll().first;
        expect(tasks, isEmpty);

        expect(() => repo.add(_make('t1')), throwsStateError);
        expect(() => repo.setDone('t1', true), throwsStateError);
        expect(() => repo.update(_make('t1')), throwsStateError);
      },
    );

    test(
      'update replaces title/due/priority, preserves id/createdAt, and is '
      'observed on the stream',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreTaskRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final created = DateTime(2026, 1, 1);
        await repo.add(_make('t1', createdAt: created, due: DateTime(2026, 1, 5)));

        final seen = <List<Task>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        await repo.update(
          Task(
            id: 't1',
            title: 'Renamed task',
            createdAt: created,
            due: DateTime(2026, 2, 1),
            priority: true,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final updated = seen.last.single;
        expect(updated.id, 't1');
        expect(updated.title, 'Renamed task');
        expect(updated.createdAt, created);
        expect(updated.due, DateTime(2026, 2, 1));
        expect(updated.priority, isTrue);

        await sub.cancel();
      },
    );

    test('update can clear the due date to null', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreTaskRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('t1', due: DateTime(2026, 1, 5)));
      await repo.update(_make('t1', due: null));

      final tasks = await repo.watchAll().first;
      expect(tasks.single.due, isNull);
    });

    test('delete removes the doc and is observed on the stream', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreTaskRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('t1'));
      await repo.add(_make('t2'));

      final seen = <List<Task>>[];
      final sub = repo.watchAll().listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      await repo.delete('t1');
      await Future<void>.delayed(Duration.zero);

      expect(seen.last.map((t) => t.id), ['t2']);

      final doc = await firestore
          .collection('users')
          .doc('test-uid')
          .collection('tasks')
          .doc('t1')
          .get();
      expect(doc.exists, isFalse);

      await sub.cancel();
    });
  });
}
