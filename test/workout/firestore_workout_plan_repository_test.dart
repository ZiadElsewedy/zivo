import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/workout/data/firestore_workout_plan_repository.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

WorkoutPlan _makePlan(
  String id, {
  WorkoutPlanStatus status = WorkoutPlanStatus.active,
  DateTime? createdAt,
  int cycleCursor = 0,
  List<WorkoutDay>? days,
}) => WorkoutPlan(
  id: id,
  name: 'Plan $id',
  status: status,
  source: WorkoutPlanSource.manual,
  createdAt: createdAt ?? DateTime(2026, 1, 1),
  updatedAt: createdAt ?? DateTime(2026, 1, 1),
  cycleCursor: cycleCursor,
  days: days ?? _defaultDays,
);

// A single push day whose sets exercise all three RepTarget shapes and a
// per-set target weight — the tree the round-trip test asserts survives storage.
const _defaultDays = [
  WorkoutDay(
    id: 'day-a',
    slot: 'A',
    label: 'Push',
    order: 0,
    exercises: [
      PlannedExercise(
        id: 'ex-bench',
        name: 'Bench Press',
        order: 0,
        muscleGroup: 'Chest',
        defaultRestSeconds: 120,
        sets: [
          PlannedSet(
            order: 0,
            repTarget: RepTarget.fixed(10),
            restSeconds: 90,
            type: SetType.warmup,
          ),
          PlannedSet(
            order: 1,
            repTarget: RepTarget.range(6, 8),
            restSeconds: 120,
            targetWeightKg: 60,
            type: SetType.working,
          ),
          PlannedSet(
            order: 2,
            repTarget: RepTarget.toFailure(),
            restSeconds: 60,
            type: SetType.failure,
          ),
        ],
      ),
    ],
  ),
];

void main() {
  group('FirestoreWorkoutPlanRepository', () {
    test(
      'savePlan writes the embedded days/exercises/sets tree and round-trips '
      'through watchActivePlan (range, toFailure, targetWeightKg intact)',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreWorkoutPlanRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final seen = <WorkoutPlan?>[];
        final sub = repo.watchActivePlan().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        await repo.savePlan(_makePlan('p1'));
        await Future<void>.delayed(Duration.zero);

        // Raw stored shape.
        final doc = await firestore
            .collection('users')
            .doc('test-uid')
            .collection('workoutPlans')
            .doc('p1')
            .get();
        final data = doc.data()!;
        expect(data['name'], 'Plan p1');
        expect(data['status'], 'active');
        expect(data['source'], 'manual');
        expect(data['cycleCursor'], 0);
        expect(data['schemaVersion'], 1);
        expect(data['createdAt'], isA<Timestamp>());
        expect(data['updatedAt'], isA<Timestamp>());
        final days = data['days'] as List<dynamic>;
        expect(days, hasLength(1));
        final exercises = (days.single as Map)['exercises'] as List<dynamic>;
        expect(exercises, hasLength(1));
        final sets = (exercises.single as Map)['sets'] as List<dynamic>;
        expect(sets, hasLength(3));
        expect((sets[1] as Map)['repKind'], 'range');
        expect((sets[1] as Map)['targetWeightKg'], 60);
        expect((sets[2] as Map)['repKind'], 'toFailure');

        // Rehydrated domain tree.
        final plan = seen.last!;
        expect(plan.id, 'p1');
        final day = plan.days.single;
        expect(day.slot, 'A');
        final exercise = day.exercises.single;
        expect(exercise.name, 'Bench Press');
        expect(exercise.muscleGroup, 'Chest');
        expect(exercise.sets, hasLength(3));
        expect(exercise.sets[0].repTarget, const RepTarget.fixed(10));
        expect(exercise.sets[0].type, SetType.warmup);
        expect(exercise.sets[1].repTarget, const RepTarget.range(6, 8));
        expect(exercise.sets[1].targetWeightKg, 60);
        expect(exercise.sets[1].type, SetType.working);
        expect(exercise.sets[2].repTarget, const RepTarget.toFailure());
        expect(exercise.sets[2].type, SetType.failure);

        await sub.cancel();
      },
    );

    test('savePlan normalizes order: out-of-order tree reads back contiguous 0-based', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutPlanRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      // Days, exercises, and sets all saved out of order and non-contiguous.
      final messy = _makePlan(
        'p1',
        days: const [
          WorkoutDay(
            id: 'day-late',
            slot: 'B',
            label: 'Pull',
            order: 5,
            exercises: [
              PlannedExercise(
                id: 'ex-second',
                name: 'Row',
                order: 3,
                defaultRestSeconds: 90,
                sets: [
                  PlannedSet(order: 2, repTarget: RepTarget.fixed(8), restSeconds: 60, type: SetType.working),
                  PlannedSet(order: 0, repTarget: RepTarget.fixed(8), restSeconds: 60, type: SetType.working),
                ],
              ),
              PlannedExercise(
                id: 'ex-first',
                name: 'Deadlift',
                order: 1,
                defaultRestSeconds: 180,
                sets: [
                  PlannedSet(order: 0, repTarget: RepTarget.fixed(5), restSeconds: 180, type: SetType.working),
                ],
              ),
            ],
          ),
          WorkoutDay(
            id: 'day-early',
            slot: 'A',
            label: 'Push',
            order: 2,
            exercises: [
              PlannedExercise(
                id: 'ex-only',
                name: 'Bench',
                order: 0,
                defaultRestSeconds: 120,
                sets: [
                  PlannedSet(order: 0, repTarget: RepTarget.fixed(6), restSeconds: 120, type: SetType.working),
                ],
              ),
            ],
          ),
        ],
      );
      await repo.savePlan(messy);

      final plan = await repo.watchActivePlan().first;

      // Days sorted by their old order (2 then 5) and reassigned 0,1.
      expect(plan!.days.map((d) => d.order), [0, 1]);
      expect(plan.days.map((d) => d.id), ['day-early', 'day-late']);

      // Exercises within the second day sorted (1 then 3) and reassigned 0,1.
      final pullDay = plan.days[1];
      expect(pullDay.exercises.map((e) => e.order), [0, 1]);
      expect(pullDay.exercises.map((e) => e.id), ['ex-first', 'ex-second']);

      // Sets within the reordered exercise sorted (0 then 2) and reassigned 0,1.
      final rows = pullDay.exercises[1];
      expect(rows.sets.map((s) => s.order), [0, 1]);
    });

    test('only the active-status plan is surfaced by watchActivePlan', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutPlanRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.savePlan(
        _makePlan('archived', status: WorkoutPlanStatus.archived, createdAt: DateTime(2026, 1, 1)),
      );
      await repo.savePlan(
        _makePlan('active', status: WorkoutPlanStatus.active, createdAt: DateTime(2026, 1, 2)),
      );

      final plan = await repo.watchActivePlan().first;
      expect(plan?.id, 'active');
    });

    test('deletePlan removes the doc and watchActivePlan emits null', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutPlanRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.savePlan(_makePlan('p1'));

      final seen = <WorkoutPlan?>[];
      final sub = repo.watchActivePlan().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last?.id, 'p1');

      await repo.deletePlan('p1');
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, isNull);

      final doc = await firestore
          .collection('users')
          .doc('test-uid')
          .collection('workoutPlans')
          .doc('p1')
          .get();
      expect(doc.exists, isFalse);

      await sub.cancel();
    });

    test('signed-out uid source emits null and guards writes', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutPlanRepository(
        firestore: firestore,
        uidSource: UidSource(currentUid: () => null, uidChanges: Stream.value(null)),
      );

      final plan = await repo.watchActivePlan().first;
      expect(plan, isNull);

      expect(() => repo.savePlan(_makePlan('p1')), throwsStateError);
      expect(() => repo.deletePlan('p1'), throwsStateError);
    });
  });
}
