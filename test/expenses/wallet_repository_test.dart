import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/expenses/data/firestore_wallet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_wallet_repository.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

void main() {
  group('InMemoryWalletRepository', () {
    test('starts unset', () {
      final repo = InMemoryWalletRepository();
      expect(repo.current, isNull);
      repo.dispose();
    });

    test('setBalance overwrites the exact amount', () async {
      final repo = InMemoryWalletRepository();
      addTearDown(repo.dispose);

      await repo.setBalance(10000, currency: 'EGP');
      expect(repo.current!.balanceMinor, 10000);

      await repo.setBalance(5000);
      expect(repo.current!.balanceMinor, 5000);
    });

    test('adjustBy accumulates, including going negative', () async {
      final repo = InMemoryWalletRepository();
      addTearDown(repo.dispose);

      await repo.setBalance(1000);
      await repo.adjustBy(-4500);
      expect(repo.current!.balanceMinor, -3500);

      await repo.adjustBy(2000);
      expect(repo.current!.balanceMinor, -1500);
    });

    test('adjustBy before any balance is set is a no-op', () async {
      final repo = InMemoryWalletRepository();
      addTearDown(repo.dispose);

      await repo.adjustBy(-500);
      expect(repo.current, isNull);
    });
  });

  group('FirestoreWalletRepository', () {
    test('setBalance writes the doc and surfaces via watch', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWalletRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      final seen = [];
      final sub = repo.watch().listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      await repo.setBalance(10000, currency: 'EGP');
      await Future<void>.delayed(Duration.zero);

      expect(seen.last!.balanceMinor, 10000);
      expect(seen.last!.currency, 'EGP');

      await sub.cancel();
    });

    test('adjustBy increments an existing balance atomically', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWalletRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.setBalance(1000);
      await repo.adjustBy(-4500);

      final wallet = await repo.watch().first;
      expect(wallet!.balanceMinor, -3500);
    });

    test('adjustBy before a balance exists is a no-op', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWalletRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.adjustBy(-500);

      final doc = await firestore
          .collection('users')
          .doc('test-uid')
          .collection('wallet')
          .doc('main')
          .get();
      expect(doc.exists, isFalse);
    });
  });
}
