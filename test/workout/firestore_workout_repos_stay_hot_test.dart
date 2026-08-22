import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/workout/data/firestore_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/firestore_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';

/// Regression coverage for the Home/Workout-tab training-card drift: a
/// workout finishing while the reader that would have shown it (Home's
/// Training card, scrolled off-screen — see `today_page.dart`'s
/// `_TrainingSection`) had already unsubscribed from
/// `watchActivePlan()`/`watchActiveSession()`. Previously the repositories
/// tore down their Firestore `.snapshots()` listener the moment the last
/// Flutter-side subscriber cancelled (`onCancel` → `_stop()`), so the finish
/// write landed in Firestore with nobody listening — the cached
/// `_activePlan`/`_sessions` value went stale until *something* (opening the
/// Workout tab) re-subscribed and forced a fresh query. The fix makes both
/// repositories start their Firestore listener once, in the constructor,
/// and never stop it — these tests assert the *synchronous* cache
/// (`activePlan`/`current`/`activeSession`) reflects a write made with zero
/// active Flutter-side subscribers, which only holds if the underlying
/// Firestore listener was already live at write time.
UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

WorkoutPlan _plan({int cycleCursor = 0}) => WorkoutPlan(
  id: 'p1',
  name: 'Push Pull Legs',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  cycleCursor: cycleCursor,
  days: const [
    WorkoutDay(
      id: 'day-a',
      slot: 'A',
      label: 'Push',
      order: 0,
      exercises: [
        PlannedExercise(
          id: 'e1',
          name: 'Bench Press',
          order: 0,
          defaultRestSeconds: 90,
          sets: [PlannedSet(order: 0, repTarget: RepTarget.fixed(5), restSeconds: 90, type: SetType.working)],
        ),
      ],
    ),
    WorkoutDay(
      id: 'day-b',
      slot: 'B',
      label: 'Pull',
      order: 1,
      exercises: [
        PlannedExercise(
          id: 'e2',
          name: 'Row',
          order: 0,
          defaultRestSeconds: 90,
          sets: [PlannedSet(order: 0, repTarget: RepTarget.fixed(5), restSeconds: 90, type: SetType.working)],
        ),
      ],
    ),
  ],
);

LiveSession _completedSession(String id) => LiveSession(
  id: id,
  planId: 'p1',
  dayId: 'day-a',
  dayLabel: 'Push',
  startedAt: DateTime(2026, 3, 1, 6),
  completedAt: DateTime(2026, 3, 1, 7),
  status: SessionStatus.completed,
  exercises: const [],
);

void main() {
  group('R1 — the always-on Firestore listener stays live with zero Flutter-side subscribers', () {
    test(
      'FirestoreWorkoutSessionRepository: a session saved with NO watchAll()/watchActiveSession() '
      'subscriber ever attached is still reflected by the sync `current`/`activeSession` getters',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreWorkoutSessionRepository(firestore: firestore, uidSource: _signedInAs('u1'));
        addTearDown(repo.dispose);

        // Nothing has ever called watchAll()/watchActiveSession() — this is
        // the "Home's Training card was scrolled off-screen" state. Under
        // the old on-demand lifecycle, the Firestore listener would not
        // even have started yet.
        await Future<void>.delayed(Duration.zero); // let the constructor's eager _start() settle

        await repo.saveSession(_completedSession('s1'));
        await Future<void>.delayed(Duration.zero); // let the fake Firestore snapshot propagate

        expect(repo.current, hasLength(1));
        expect(repo.current.single.id, 's1');
        expect(repo.activeSession, isNull); // completed, not active — sanity check on the data itself
      },
    );

    test(
      'FirestoreWorkoutSessionRepository: unsubscribing (card disposed) then saving then '
      're-subscribing sees the FRESH value immediately, never a stale replay',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreWorkoutSessionRepository(firestore: firestore, uidSource: _signedInAs('u1'));
        addTearDown(repo.dispose);

        // A first subscriber (Home's card, mounted) sees the empty initial state.
        final firstSub = repo.watchAll().listen((_) {});
        await Future<void>.delayed(Duration.zero);
        await firstSub.cancel(); // the card is scrolled off-screen / disposed

        // The workout finishes while nothing is subscribed.
        await repo.saveSession(_completedSession('s1'));
        await Future<void>.delayed(Duration.zero);

        // Re-subscribing (the card back on-screen) must replay the FRESH
        // value, not whatever was cached before the save.
        final seen = <List<LiveSession>>[];
        final secondSub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);
        addTearDown(secondSub.cancel);

        expect(seen, isNotEmpty);
        expect(seen.first.map((s) => s.id), ['s1']);
      },
    );

    test(
      'FirestoreWorkoutPlanRepository: a cursor advance saved with NO watchActivePlan() subscriber '
      'ever attached is still reflected by the sync `activePlan` getter',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreWorkoutPlanRepository(firestore: firestore, uidSource: _signedInAs('u1'));
        addTearDown(repo.dispose);
        await Future<void>.delayed(Duration.zero);

        await repo.savePlan(_plan());
        await Future<void>.delayed(Duration.zero);
        expect(repo.activePlan?.cycleCursor, 0);

        // Simulates live_session_page.dart's finish flow: advance the
        // cursor, with nothing subscribed via watchActivePlan().
        await repo.savePlan(_plan().advanceCursor());
        await Future<void>.delayed(Duration.zero);

        expect(repo.activePlan?.cycleCursor, 1);
        expect(repo.activePlan?.nextDay?.label, 'Pull');
      },
    );
  });

  group('starting the listener at construction still re-scopes cleanly across sign-out/user-switch', () {
    test(
      'FirestoreWorkoutSessionRepository: signing out clears the cache, and signing in as a '
      'DIFFERENT user never bleeds the previous user\'s sessions',
      () async {
        final firestore = FakeFirebaseFirestore();
        final uidController = StreamController<String?>.broadcast();
        addTearDown(uidController.close);
        String? currentUid = 'u1';
        final repo = FirestoreWorkoutSessionRepository(
          firestore: firestore,
          uidSource: UidSource(currentUid: () => currentUid, uidChanges: uidController.stream),
        );
        addTearDown(repo.dispose);
        await Future<void>.delayed(Duration.zero);

        await repo.saveSession(_completedSession('s1'));
        await Future<void>.delayed(Duration.zero);
        expect(repo.current.map((s) => s.id), ['s1']);

        // Sign out: the cache must clear, not keep showing u1's session.
        currentUid = null;
        uidController.add(null);
        await Future<void>.delayed(Duration.zero);
        expect(repo.current, isEmpty);

        // A different user signs in: their (empty) collection must not
        // somehow surface u1's data, and writes now go to u2's own docs.
        currentUid = 'u2';
        uidController.add('u2');
        await Future<void>.delayed(Duration.zero);
        expect(repo.current, isEmpty);

        await repo.saveSession(_completedSession('s2'));
        await Future<void>.delayed(Duration.zero);
        expect(repo.current.map((s) => s.id), ['s2']); // only u2's session, no s1 bleed
      },
    );

    test(
      'FirestoreWorkoutPlanRepository: signing out clears activePlan, and a different user '
      'signing in never bleeds the previous user\'s plan',
      () async {
        final firestore = FakeFirebaseFirestore();
        final uidController = StreamController<String?>.broadcast();
        addTearDown(uidController.close);
        String? currentUid = 'u1';
        final repo = FirestoreWorkoutPlanRepository(
          firestore: firestore,
          uidSource: UidSource(currentUid: () => currentUid, uidChanges: uidController.stream),
        );
        addTearDown(repo.dispose);
        await Future<void>.delayed(Duration.zero);

        await repo.savePlan(_plan());
        await Future<void>.delayed(Duration.zero);
        expect(repo.activePlan?.id, 'p1');

        currentUid = null;
        uidController.add(null);
        await Future<void>.delayed(Duration.zero);
        expect(repo.activePlan, isNull);

        currentUid = 'u2';
        uidController.add('u2');
        await Future<void>.delayed(Duration.zero);
        expect(repo.activePlan, isNull); // u2 has no plans yet — not u1's
      },
    );
  });

  group('WorkoutPlan.nextDay never returns null while days exist (already-hardened fallback)', () {
    test('a cycleCursor with no matching day.order falls back to the first day by order, not null', () {
      final plan = WorkoutPlan(
        id: 'p1',
        name: 'X',
        status: WorkoutPlanStatus.active,
        source: WorkoutPlanSource.manual,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        cycleCursor: 99, // no day has order == 99
        days: const [
          WorkoutDay(id: 'a', slot: 'A', label: 'Push', order: 0, exercises: []),
          WorkoutDay(id: 'b', slot: 'B', label: 'Pull', order: 1, exercises: []),
        ],
      );
      expect(plan.nextDay, isNotNull);
      expect(plan.nextDay!.label, 'Push'); // first by order, not null
    });
  });
}
