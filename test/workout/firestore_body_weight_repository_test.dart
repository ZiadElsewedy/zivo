import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/workout/data/firestore_body_weight_repository.dart';
import 'package:zivo/features/workout/domain/body_weight_entry.dart';

/// Regression coverage for the "saved weigh-ins vanish" bug — the
/// body-weight flavour of the always-on-listener regressions in
/// `firestore_workout_repos_stay_hot_test.dart`. Previously this repository
/// started/stopped its Firestore `.snapshots()` listener per subscriber
/// (`onListen`/`onCancel`), so a save made while nothing was subscribed
/// landed with nobody listening and the cached `_current` went stale until
/// the next subscription forced a fresh query — the first replay after
/// re-subscribing showed the OLD list, reading as if the weigh-in never
/// saved. The fix starts the listener in the constructor and never stops
/// it; these tests assert the synchronous cache reflects writes made with
/// zero active Flutter-side subscribers, which only holds if the listener
/// was already live at write time.
UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

BodyWeightEntry _entry(String id, double kg, DateTime at) =>
    BodyWeightEntry(id: id, weightKg: kg, loggedAt: at);

void main() {
  test(
    'a weigh-in saved with NO watchAll() subscriber ever attached is still '
    'reflected by the sync `current` getter',
    () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreBodyWeightRepository(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );
      addTearDown(repo.dispose);

      // Nothing has ever called watchAll() — under the old on-demand
      // lifecycle the Firestore listener would not even have started yet.
      await Future<void>.delayed(Duration.zero);

      await repo.save(_entry('w1', 82.5, DateTime(2026, 3, 1)));
      await Future<void>.delayed(Duration.zero); // let the snapshot propagate

      expect(repo.current, hasLength(1));
      expect(repo.current.single.weightKg, 82.5);
    },
  );

  test(
    'unsubscribing, then saving, then re-subscribing sees the FRESH value '
    'immediately — never a stale replay of the pre-save cache',
    () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreBodyWeightRepository(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );
      addTearDown(repo.dispose);

      // A first subscriber (the dashboard's weight card, mounted) seeds the
      // cache with the initial empty state.
      final firstSub = repo.watchAll().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await repo.save(_entry('w1', 82.5, DateTime(2026, 3, 1)));
      await Future<void>.delayed(Duration.zero);
      await firstSub.cancel(); // the card is scrolled off-screen / disposed

      // Another weigh-in lands while nothing is subscribed.
      await repo.save(_entry('w2', 83.0, DateTime(2026, 3, 2)));
      await Future<void>.delayed(Duration.zero);

      // Re-subscribing must replay BOTH entries immediately.
      final seen = <List<BodyWeightEntry>>[];
      final secondSub = repo.watchAll().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      addTearDown(secondSub.cancel);

      expect(seen, isNotEmpty);
      expect(seen.first.map((e) => e.id).toSet(), {'w1', 'w2'});
    },
  );

  test(
    'signing out clears the cache, and signing in as a DIFFERENT user never '
    'bleeds the previous user\'s weigh-ins',
    () async {
      final firestore = FakeFirebaseFirestore();
      final uidController = StreamController<String?>.broadcast();
      addTearDown(uidController.close);
      String? currentUid = 'u1';
      final repo = FirestoreBodyWeightRepository(
        firestore: firestore,
        uidSource: UidSource(
          currentUid: () => currentUid,
          uidChanges: uidController.stream,
        ),
      );
      addTearDown(repo.dispose);
      await Future<void>.delayed(Duration.zero);

      await repo.save(_entry('w1', 82.5, DateTime(2026, 3, 1)));
      await Future<void>.delayed(Duration.zero);
      expect(repo.current.map((e) => e.id), ['w1']);

      currentUid = null;
      uidController.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(repo.current, isEmpty);

      currentUid = 'u2';
      uidController.add('u2');
      await Future<void>.delayed(Duration.zero);
      expect(repo.current, isEmpty);

      await repo.save(_entry('w2', 90.0, DateTime(2026, 3, 3)));
      await Future<void>.delayed(Duration.zero);
      expect(repo.current.map((e) => e.id), ['w2']); // only u2's entry
    },
  );

  test('save() surfaces a signed-out StateError to the caller, never silently drops', () {
    final firestore = FakeFirebaseFirestore();
    final repo = FirestoreBodyWeightRepository(
      firestore: firestore,
      uidSource: UidSource(currentUid: () => null, uidChanges: const Stream.empty()),
    );
    addTearDown(repo.dispose);

    expect(
      () => repo.save(_entry('w1', 82.5, DateTime(2026, 3, 1))),
      throwsStateError,
    );
  });
}
