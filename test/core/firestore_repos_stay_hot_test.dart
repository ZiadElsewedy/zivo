import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/expenses/data/firestore_category_repository.dart';
import 'package:zivo/features/expenses/data/firestore_expense_repository.dart';
import 'package:zivo/features/expenses/data/firestore_wallet_repository.dart';
import 'package:zivo/features/expenses/domain/expense.dart';
import 'package:zivo/features/expenses/domain/expense_category.dart';
import 'package:zivo/features/moments/data/firestore_moment_repository.dart';
import 'package:zivo/features/moments/domain/moment.dart';
import 'package:zivo/features/workout/data/firestore_workout_repository.dart';
import 'package:zivo/features/workout/domain/exercise.dart';
import 'package:zivo/features/workout/domain/workout.dart';

/// The Home/Workout-tab drift regression, extended to the repositories that
/// were still carrying the bug.
///
/// `firestore_workout_repos_stay_hot_test.dart` pinned this behaviour for the
/// plan and session repositories, which had been fixed by hand. The moment,
/// expense, category and workout-log repositories were **not** fixed: they
/// started their Firestore listener on the first Flutter-side subscriber and
/// tore it down when the last one cancelled (`onListen`/`onCancel`), so a
/// write that landed while nothing was subscribed had no listener to pick up
/// the fresh snapshot — and the next subscriber was replayed the STALE cached
/// value first.
///
/// Routing all of them through `UidScopedMirror` fixed that by construction.
/// These tests assert the fix per repository, so it cannot silently regress
/// for one of them.
UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

/// Subscribe, let the initial snapshot land, then leave — the "Home's card is
/// scrolled off-screen / the page was popped" state that used to stop the
/// underlying Firestore listener.
Future<void> _subscribeThenLeave(Stream<Object?> stream) async {
  final sub = stream.listen((_) {});
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('the always-on listener, per repository', () {
    test('FirestoreMomentRepository: a moment saved with nothing subscribed is not replayed stale', () async {
      final repo = FirestoreMomentRepository(
        firestore: FakeFirebaseFirestore(),
        uidSource: _signedInAs('u1'),
      );
      addTearDown(repo.dispose);
      await _settle();

      await _subscribeThenLeave(repo.watchAll());
      await repo.add(Moment(id: 'm1', caption: 'Saved offscreen', takenAt: DateTime(2026, 3, 1)));
      await _settle();

      expect(repo.current.map((m) => m.id), ['m1']);
      final seen = <List<Moment>>[];
      final sub = repo.watchAll().listen(seen.add);
      addTearDown(sub.cancel);
      await _settle();
      expect(seen.first.map((m) => m.id), ['m1']);
    });

    test('FirestoreExpenseRepository: an expense saved with nothing subscribed is not replayed stale', () async {
      final repo = FirestoreExpenseRepository(
        firestore: FakeFirebaseFirestore(),
        uidSource: _signedInAs('u1'),
      );
      addTearDown(repo.dispose);
      await _settle();

      await _subscribeThenLeave(repo.watchAll());
      await repo.add(
        Expense(
          id: 'e1',
          amountMinor: 4500,
          currency: 'EGP',
          categoryId: 'coffee',
          spentAt: DateTime(2026, 3, 1),
        ),
      );
      await _settle();

      expect(repo.current.map((e) => e.id), ['e1']);
      final seen = <List<Expense>>[];
      final sub = repo.watchAll().listen(seen.add);
      addTearDown(sub.cancel);
      await _settle();
      expect(seen.first.map((e) => e.id), ['e1']);
    });

    test('FirestoreCategoryRepository: a category added with nothing subscribed is not replayed stale', () async {
      final repo = FirestoreCategoryRepository(
        firestore: FakeFirebaseFirestore(),
        uidSource: _signedInAs('u1'),
      );
      addTearDown(repo.dispose);
      await _settle();

      await _subscribeThenLeave(repo.watchAll());
      await repo.add(const ExpenseCategory(id: 'c1', label: 'Coffee', icon: CategoryIcon.coffee));
      await _settle();

      expect(repo.current.map((c) => c.id), ['c1']);
    });

    test('FirestoreWorkoutRepository: a workout logged with nothing subscribed is not replayed stale', () async {
      final repo = FirestoreWorkoutRepository(
        firestore: FakeFirebaseFirestore(),
        uidSource: _signedInAs('u1'),
      );
      addTearDown(repo.dispose);
      await _settle();

      await _subscribeThenLeave(repo.watchAll());
      await repo.add(
        Workout(
          id: 'w1',
          title: 'Push',
          performedAt: DateTime(2026, 3, 1),
          exercises: const [Exercise(name: 'Bench Press', sets: 3, reps: 5, weightKg: 60)],
        ),
      );
      await _settle();

      expect(repo.current.map((w) => w.id), ['w1']);
      final seen = <List<Workout>>[];
      final sub = repo.watchAll().listen(seen.add);
      addTearDown(sub.cancel);
      await _settle();
      expect(seen.first.map((w) => w.id), ['w1']);
    });

    test('FirestoreWalletRepository: a balance set with nothing subscribed is not replayed stale', () async {
      final repo = FirestoreWalletRepository(
        firestore: FakeFirebaseFirestore(),
        uidSource: _signedInAs('u1'),
      );
      addTearDown(repo.dispose);
      await _settle();

      await _subscribeThenLeave(repo.watch());
      await repo.setBalance(10000);
      await _settle();

      expect(repo.current?.balanceMinor, 10000);
    });
  });

  group('re-scoping across sign-out and user switch, per repository', () {
    test('FirestoreMomentRepository: signing out clears, and a second user never sees the first\'s moments', () async {
      final firestore = FakeFirebaseFirestore();
      final uidChanges = StreamController<String?>.broadcast();
      addTearDown(uidChanges.close);
      String? uid = 'u1';
      final repo = FirestoreMomentRepository(
        firestore: firestore,
        uidSource: UidSource(currentUid: () => uid, uidChanges: uidChanges.stream),
      );
      addTearDown(repo.dispose);
      await _settle();

      await repo.add(Moment(id: 'm1', caption: 'u1', takenAt: DateTime(2026, 3, 1)));
      await _settle();
      expect(repo.current, hasLength(1));

      uid = null;
      uidChanges.add(null);
      await _settle();
      expect(repo.current, isEmpty);

      uid = 'u2';
      uidChanges.add('u2');
      await _settle();
      expect(repo.current, isEmpty);
    });

    test('FirestoreWalletRepository: signing out clears the balance rather than leaving it readable', () async {
      final firestore = FakeFirebaseFirestore();
      final uidChanges = StreamController<String?>.broadcast();
      addTearDown(uidChanges.close);
      String? uid = 'u1';
      final repo = FirestoreWalletRepository(
        firestore: firestore,
        uidSource: UidSource(currentUid: () => uid, uidChanges: uidChanges.stream),
      );
      addTearDown(repo.dispose);
      await _settle();

      await repo.setBalance(10000);
      await _settle();
      expect(repo.current?.balanceMinor, 10000);

      uid = null;
      uidChanges.add(null);
      await _settle();
      expect(repo.current, isNull);
    });
  });
}
