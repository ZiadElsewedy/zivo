import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/workout/data/firestore_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_type.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

LiveSession _makeSession(
  String id, {
  SessionStatus status = SessionStatus.active,
  DateTime? startedAt,
  DateTime? completedAt,
  List<SessionExercise>? exercises,
}) => LiveSession(
  id: id,
  planId: 'plan-1',
  dayId: 'day-a',
  dayLabel: 'Push',
  startedAt: startedAt ?? DateTime(2026, 1, 1),
  status: status,
  completedAt: completedAt,
  exercises: exercises ?? _defaultExercises,
);

// One exercise exercising all three RepTarget shapes plus actuals/RPE/done —
// the tree the round-trip test asserts survives storage.
const _defaultExercises = [
  SessionExercise(
    id: 'ex-bench',
    exerciseId: 'ex-bench',
    name: 'Bench Press',
    muscleGroup: 'Chest',
    restSeconds: 120,
    sets: [
      LoggedSet(
        id: 'ex-bench-s0',
        target: RepTarget.fixed(10),
        type: SetType.warmup,
        done: true,
        actualReps: 10,
        actualWeightKg: 40,
      ),
      LoggedSet(
        id: 'ex-bench-s1',
        target: RepTarget.range(6, 8),
        targetWeightKg: 60,
        type: SetType.working,
        done: true,
        actualReps: 7,
        actualWeightKg: 60,
        rpe: 8.5,
      ),
      LoggedSet(id: 'ex-bench-s2', target: RepTarget.toFailure(), type: SetType.failure),
    ],
  ),
];

void main() {
  group('FirestoreWorkoutSessionRepository', () {
    test(
      'saveSession writes the embedded exercises/sets tree and round-trips '
      'through watchAll (range, toFailure, actuals/RPE/done intact)',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreWorkoutSessionRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final seen = <List<LiveSession>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        await repo.saveSession(_makeSession('s1'));
        await Future<void>.delayed(Duration.zero);

        // Raw stored shape.
        final doc = await firestore
            .collection('users')
            .doc('test-uid')
            .collection('workoutSessions')
            .doc('s1')
            .get();
        final data = doc.data()!;
        expect(data['planId'], 'plan-1');
        expect(data['dayId'], 'day-a');
        expect(data['dayLabel'], 'Push');
        expect(data['status'], 'active');
        expect(data['schemaVersion'], 1);
        expect(data['startedAt'], isA<Timestamp>());
        expect(data['completedAt'], isNull);
        final exercises = data['exercises'] as List<dynamic>;
        expect(exercises, hasLength(1));
        final sets = (exercises.single as Map)['sets'] as List<dynamic>;
        expect(sets, hasLength(3));
        expect((sets[1] as Map)['repKind'], 'range');
        expect((sets[1] as Map)['targetWeightKg'], 60);
        expect((sets[1] as Map)['rpe'], 8.5);
        expect((sets[2] as Map)['repKind'], 'toFailure');

        // Rehydrated domain tree.
        final session = seen.last.single;
        expect(session.id, 's1');
        expect(session.status, SessionStatus.active);
        final exercise = session.exercises.single;
        expect(exercise.name, 'Bench Press');
        expect(exercise.muscleGroup, 'Chest');
        expect(exercise.sets, hasLength(3));
        expect(exercise.sets[0].target, const RepTarget.fixed(10));
        expect(exercise.sets[0].done, isTrue);
        expect(exercise.sets[0].actualReps, 10);
        expect(exercise.sets[1].target, const RepTarget.range(6, 8));
        expect(exercise.sets[1].actualWeightKg, 60);
        expect(exercise.sets[1].rpe, 8.5);
        expect(exercise.sets[2].target, const RepTarget.toFailure());
        expect(exercise.sets[2].done, isFalse);

        await sub.cancel();
      },
    );

    test('activeSession picks the most recent active session; ignores others', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutSessionRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.saveSession(
        _makeSession(
          'finished',
          status: SessionStatus.completed,
          startedAt: DateTime(2026, 1, 1),
          completedAt: DateTime(2026, 1, 1, 1),
        ),
      );
      await repo.saveSession(_makeSession('live', startedAt: DateTime(2026, 1, 2)));

      final sessions = await repo.watchAll().first;
      expect(sessions.map((s) => s.id).toSet(), {'finished', 'live'});

      // activeSession is a getter over the last-emitted snapshot, so wait a beat.
      await Future<void>.delayed(Duration.zero);
      expect(repo.activeSession?.id, 'live');
    });

    test('saveSession is idempotent by id (edits overwrite, no duplicates)', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutSessionRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.saveSession(_makeSession('s1'));
      final edited = _makeSession('s1').markSetDone('ex-bench', 'ex-bench-s2', actualReps: 12);
      await repo.saveSession(edited);

      final sessions = await repo.watchAll().first;
      expect(sessions, hasLength(1));
      expect(sessions.single.exercises.single.sets[2].done, isTrue);
      expect(sessions.single.exercises.single.sets[2].actualReps, 12);
    });

    test('deleteSession removes the doc and watchAll drops it', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutSessionRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.saveSession(_makeSession('s1'));

      final seen = <List<LiveSession>>[];
      final sub = repo.watchAll().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last.map((s) => s.id), ['s1']);

      await repo.deleteSession('s1');
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, isEmpty);

      final doc = await firestore
          .collection('users')
          .doc('test-uid')
          .collection('workoutSessions')
          .doc('s1')
          .get();
      expect(doc.exists, isFalse);

      await sub.cancel();
    });

    test('signed-out uid source emits an empty list and guards writes', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutSessionRepository(
        firestore: firestore,
        uidSource: UidSource(currentUid: () => null, uidChanges: Stream.value(null)),
      );

      final sessions = await repo.watchAll().first;
      expect(sessions, isEmpty);
      expect(repo.activeSession, isNull);

      expect(() => repo.saveSession(_makeSession('s1')), throwsStateError);
      expect(() => repo.deleteSession('s1'), throwsStateError);
    });
  });
}
