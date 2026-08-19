import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/workout/data/firestore_workout_plan_repository.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

WorkoutPlan _split(
  String id, {
  String name = 'Split',
  WorkoutPlanStatus status = WorkoutPlanStatus.active,
  DateTime? createdAt,
}) => WorkoutPlan(
  id: id,
  name: name,
  status: status,
  source: WorkoutPlanSource.manual,
  createdAt: createdAt ?? DateTime(2024, 1, 1),
  updatedAt: createdAt ?? DateTime(2024, 1, 1),
  days: const [],
);

/// Reads the raw active-pointer doc the repo maintains at
/// users/{uid}/workoutMeta/active.
Future<String?> _pointerId(FakeFirebaseFirestore firestore, String uid) async {
  final snap = await firestore
      .collection('users')
      .doc(uid)
      .collection('workoutMeta')
      .doc('active')
      .get();
  return snap.data()?['activeSplitId'] as String?;
}

void main() {
  group('FirestoreWorkoutPlanRepository — multi-split', () {
    test('saveSplit writes a doc that round-trips through watchSplits (createdAt order)', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutPlanRepository(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );

      await repo.saveSplit(_split('late', name: 'Late', createdAt: DateTime(2025, 1, 1)));
      await repo.saveSplit(_split('early', name: 'Early', createdAt: DateTime(2020, 1, 1)));

      final splits = await repo.watchSplits().first;
      expect(splits.map((s) => s.id), ['early', 'late']);
      expect(splits.map((s) => s.name), ['Early', 'Late']);
    });

    test('first saveSplit becomes active; a second one does NOT steal active', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutPlanRepository(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );

      await repo.saveSplit(_split('a', createdAt: DateTime(2024, 1, 1)));
      expect(await _pointerId(firestore, 'u1'), 'a');
      expect(await repo.watchActivePlan().first, isA<WorkoutPlan>().having((p) => p.id, 'id', 'a'));

      await repo.saveSplit(_split('b', createdAt: DateTime(2024, 2, 1)));
      // Pointer must stay on the first split.
      expect(await _pointerId(firestore, 'u1'), 'a');
      expect((await repo.watchActivePlan().first)!.id, 'a');
    });

    test('savePlan (back-compat) saves AND makes the saved plan active', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutPlanRepository(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );

      await repo.saveSplit(_split('a', createdAt: DateTime(2024, 1, 1)));
      // savePlan on a second plan must steal active (unlike saveSplit).
      await repo.savePlan(_split('b', createdAt: DateTime(2024, 2, 1)));

      expect(await _pointerId(firestore, 'u1'), 'b');
      expect((await repo.watchActivePlan().first)!.id, 'b');
    });

    test('setActiveSplit moves the pointer and re-emits on watchActivePlan', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutPlanRepository(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );

      await repo.saveSplit(_split('a', createdAt: DateTime(2024, 1, 1)));
      await repo.saveSplit(_split('b', createdAt: DateTime(2024, 2, 1)));

      final seen = <String?>[];
      final sub = repo.watchActivePlan().listen((p) => seen.add(p?.id));
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, 'a');

      await repo.setActiveSplit('b');
      await Future<void>.delayed(Duration.zero);
      expect(await _pointerId(firestore, 'u1'), 'b');
      expect(seen.last, 'b');

      await sub.cancel();
    });

    test('setActiveSplit throws StateError for an unknown id', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutPlanRepository(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );

      await repo.saveSplit(_split('a', createdAt: DateTime(2024, 1, 1)));
      await expectLater(repo.setActiveSplit('nope'), throwsStateError);
      expect(await _pointerId(firestore, 'u1'), 'a');
    });

    test('deleteSplit of the active split repoints to the first remaining (createdAt)', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutPlanRepository(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );

      await repo.saveSplit(_split('older', createdAt: DateTime(2020, 1, 1)));
      await repo.saveSplit(_split('newer', createdAt: DateTime(2030, 1, 1)));
      await repo.setActiveSplit('newer');

      await repo.deleteSplit('newer');
      expect(await _pointerId(firestore, 'u1'), 'older');
      expect((await repo.watchActivePlan().first)!.id, 'older');
    });

    test('deleteSplit of the last split clears the pointer; watchActivePlan emits null', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutPlanRepository(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );

      await repo.saveSplit(_split('only', createdAt: DateTime(2024, 1, 1)));
      await repo.deleteSplit('only');

      expect(await _pointerId(firestore, 'u1'), isNull);
      expect(await repo.watchActivePlan().first, isNull);
      expect(await repo.watchSplits().first, isEmpty);
    });

    test('deleteSplit of a non-active split leaves active unchanged', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutPlanRepository(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );

      await repo.saveSplit(_split('a', createdAt: DateTime(2024, 1, 1)));
      await repo.saveSplit(_split('b', createdAt: DateTime(2024, 2, 1)));
      // active is 'a'; delete the non-active 'b'.
      await repo.deleteSplit('b');

      expect(await _pointerId(firestore, 'u1'), 'a');
      expect((await repo.watchActivePlan().first)!.id, 'a');
    });

    test('migration: no pointer doc → active falls back to the first status==active plan', () async {
      final firestore = FakeFirebaseFirestore();
      // Seed docs directly, WITHOUT a workoutMeta/active pointer (legacy data).
      final plans = firestore.collection('users').doc('u1').collection('workoutPlans');
      await plans.doc('archived').set({
        'name': 'Archived',
        'status': 'archived',
        'source': 'manual',
        'cycleCursor': 0,
        'days': const [],
        'schemaVersion': 1,
        'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
      });
      await plans.doc('live').set({
        'name': 'Live',
        'status': 'active',
        'source': 'manual',
        'cycleCursor': 0,
        'days': const [],
        'schemaVersion': 1,
        'createdAt': Timestamp.fromDate(DateTime(2024, 2, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2024, 2, 1)),
      });

      final repo = FirestoreWorkoutPlanRepository(
        firestore: firestore,
        uidSource: _signedInAs('u1'),
      );

      // No pointer doc exists yet.
      expect(await _pointerId(firestore, 'u1'), isNull);
      // Active resolves the old way: the first status==active plan.
      expect((await repo.watchActivePlan().first)!.id, 'live');
    });

    test('signed-out uid source emits null/empty and guards writes', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutPlanRepository(
        firestore: firestore,
        uidSource: UidSource(currentUid: () => null, uidChanges: Stream.value(null)),
      );

      expect(await repo.watchActivePlan().first, isNull);
      expect(await repo.watchSplits().first, isEmpty);

      expect(() => repo.saveSplit(_split('a')), throwsStateError);
      expect(() => repo.savePlan(_split('a')), throwsStateError);
      expect(() => repo.setActiveSplit('a'), throwsStateError);
      expect(() => repo.deleteSplit('a'), throwsStateError);
      expect(() => repo.deletePlan('a'), throwsStateError);
    });
  });
}
