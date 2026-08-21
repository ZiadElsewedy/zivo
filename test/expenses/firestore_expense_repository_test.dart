import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/expenses/data/firestore_expense_repository.dart';
import 'package:zivo/features/expenses/domain/expense.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

Expense _make(
  String id, {
  DateTime? spentAt,
  int amountMinor = 1000,
  String currency = 'EGP',
  String categoryId = 'food',
  String? note,
}) => Expense(
  id: id,
  amountMinor: amountMinor,
  currency: currency,
  categoryId: categoryId,
  spentAt: spentAt ?? DateTime(2026, 1, 1),
  note: note,
);

void main() {
  group('FirestoreExpenseRepository', () {
    test(
      'add writes a doc with the right fields and surfaces via watchAll',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreExpenseRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final seen = <List<Expense>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        final expense = _make(
          'e1',
          amountMinor: 4500,
          categoryId: 'coffee',
          note: 'Latte',
        );
        await repo.add(expense);
        await Future<void>.delayed(Duration.zero);

        final doc = await firestore
            .collection('users')
            .doc('test-uid')
            .collection('expenses')
            .doc('e1')
            .get();
        final data = doc.data()!;
        expect(data['amountMinor'], 4500);
        expect(data['currency'], 'EGP');
        expect(data['category'], 'coffee');
        expect(data['spentAt'], isA<Timestamp>());
        expect(data['note'], 'Latte');
        expect(data['schemaVersion'], 1);
        expect(data['createdAt'], isA<Timestamp>());
        expect(data['updatedAt'], isA<Timestamp>());

        expect(seen.last, hasLength(1));
        expect(seen.last.single.id, 'e1');

        await sub.cancel();
      },
    );

    test(
      'category id round-trips verbatim — even an id no built-in or custom '
      'category matches, since resolving display is a presentation concern',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreExpenseRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        await repo.add(_make('e1', categoryId: 'transport'));

        await firestore
            .collection('users')
            .doc('test-uid')
            .collection('expenses')
            .doc('e2')
            .set({
              'amountMinor': 500,
              'currency': 'EGP',
              'category': 'not-a-real-category',
              'spentAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
              'note': null,
              'schemaVersion': 1,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });

        final expenses = await repo.watchAll().first;
        final byId = {for (final e in expenses) e.id: e};
        expect(byId['e1']!.categoryId, 'transport');
        expect(byId['e2']!.categoryId, 'not-a-real-category');
      },
    );

    test('watchAll returns expenses newest-first (spentAt desc)', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreExpenseRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('older', spentAt: DateTime(2026, 1, 1)));
      await repo.add(_make('newer', spentAt: DateTime(2026, 1, 5)));

      final expenses = await repo.watchAll().first;
      expect(expenses.map((e) => e.id).toList(), ['newer', 'older']);
    });

    test('a note-less expense round-trips with note null', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreExpenseRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('e1'));

      final expenses = await repo.watchAll().first;
      expect(expenses.single.note, isNull);
    });

    test(
      'signed-out uid source emits an empty list and guards writes',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreExpenseRepository(
          firestore: firestore,
          uidSource: UidSource(
            currentUid: () => null,
            uidChanges: Stream.value(null),
          ),
        );

        final expenses = await repo.watchAll().first;
        expect(expenses, isEmpty);

        expect(() => repo.add(_make('e1')), throwsStateError);
        expect(() => repo.update(_make('e1')), throwsStateError);
        expect(() => repo.remove('e1'), throwsStateError);
      },
    );

    test(
      'update replaces amount/category/note, preserves id, and is observed '
      'on the stream',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreExpenseRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        await repo.add(
          _make(
            'e1',
            amountMinor: 1000,
            categoryId: 'food',
            note: 'Lunch',
          ),
        );

        final seen = <List<Expense>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        await repo.update(
          _make(
            'e1',
            amountMinor: 2500,
            categoryId: 'coffee',
            note: 'Latte',
            spentAt: DateTime(2026, 2, 2),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final updated = seen.last.single;
        expect(updated.id, 'e1');
        expect(updated.amountMinor, 2500);
        expect(updated.categoryId, 'coffee');
        expect(updated.note, 'Latte');
        expect(updated.spentAt, DateTime(2026, 2, 2));

        await sub.cancel();
      },
    );

    test('remove deletes the doc and is observed on the stream', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreExpenseRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('e1'));
      await repo.add(_make('e2', spentAt: DateTime(2026, 1, 2)));

      final seen = <List<Expense>>[];
      final sub = repo.watchAll().listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      await repo.remove('e1');
      await Future<void>.delayed(Duration.zero);

      expect(seen.last.map((e) => e.id).toList(), ['e2']);

      await sub.cancel();
    });
  });
}
