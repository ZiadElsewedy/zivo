import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/features/workout/data/firestore_workout_repository.dart';
import 'package:zivo/features/workout/domain/exercise.dart';
import 'package:zivo/features/workout/domain/workout.dart';

UidSource _signedInAs(String uid) =>
    UidSource(currentUid: () => uid, uidChanges: Stream.value(uid));

Workout _make(
  String id, {
  String title = 'Push',
  DateTime? performedAt,
  int? durationMinutes,
  List<Exercise> exercises = const [
    Exercise(name: 'Bench Press', sets: 4, reps: 8, weightKg: 60),
  ],
}) => Workout(
  id: id,
  title: title,
  performedAt: performedAt ?? DateTime(2026, 1, 1, 9),
  durationMinutes: durationMinutes,
  exercises: exercises,
);

void main() {
  group('FirestoreWorkoutRepository', () {
    test(
      'add writes a doc with the right fields and surfaces via watchAll',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreWorkoutRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        final seen = <List<Workout>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        final workout = _make(
          'w1',
          title: 'Push',
          performedAt: DateTime(2026, 1, 2, 10),
          durationMinutes: 50,
        );
        await repo.add(workout);
        await Future<void>.delayed(Duration.zero);

        final doc = await firestore
            .collection('users')
            .doc('test-uid')
            .collection('workouts')
            .doc('w1')
            .get();
        final data = doc.data()!;
        expect(data['title'], 'Push');
        expect(data['performedAt'], Timestamp.fromDate(workout.performedAt));
        expect(data['durationMinutes'], 50);
        expect(data['schemaVersion'], 1);
        expect(data['createdAt'], isA<Timestamp>());
        expect(data['updatedAt'], isA<Timestamp>());
        expect(data['exercises'], isA<List>());

        expect(seen.last, hasLength(1));
        expect(seen.last.single.id, 'w1');

        await sub.cancel();
      },
    );

    test('embedded exercises round-trip, including a null weightKg', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      const exercises = [
        Exercise(name: 'Bench Press', sets: 4, reps: 8, weightKg: 60),
        Exercise(name: 'Push-up', sets: 3, reps: 20),
      ];
      await repo.add(_make('w1', exercises: exercises));

      final workouts = await repo.watchAll().first;
      final roundTripped = workouts.single.exercises;
      expect(roundTripped, hasLength(2));
      expect(roundTripped[0].name, 'Bench Press');
      expect(roundTripped[0].sets, 4);
      expect(roundTripped[0].reps, 8);
      expect(roundTripped[0].weightKg, 60);
      expect(roundTripped[1].name, 'Push-up');
      expect(roundTripped[1].sets, 3);
      expect(roundTripped[1].reps, 20);
      expect(roundTripped[1].weightKg, isNull);
    });

    test('a workout with durationMinutes null round-trips with null', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('w1', durationMinutes: null));

      final workouts = await repo.watchAll().first;
      expect(workouts.single.durationMinutes, isNull);
    });

    test('watchAll returns workouts newest-performed first', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('older', performedAt: DateTime(2026, 1, 1)));
      await repo.add(_make('newer', performedAt: DateTime(2026, 1, 5)));

      final workouts = await repo.watchAll().first;
      expect(workouts.map((w) => w.id).toList(), ['newer', 'older']);
    });

    test(
      'signed-out uid source emits an empty list and guards writes',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreWorkoutRepository(
          firestore: firestore,
          uidSource: UidSource(
            currentUid: () => null,
            uidChanges: Stream.value(null),
          ),
        );

        final workouts = await repo.watchAll().first;
        expect(workouts, isEmpty);

        expect(() => repo.add(_make('w1')), throwsStateError);
        expect(() => repo.update(_make('w1')), throwsStateError);
        expect(() => repo.remove('w1'), throwsStateError);
      },
    );

    test(
      'update replaces title/exercises/performedAt in place, observed on the stream',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreWorkoutRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        await repo.add(
          _make(
            'w1',
            title: 'Push',
            performedAt: DateTime(2026, 1, 2, 10),
            durationMinutes: 50,
          ),
        );

        final seen = <List<Workout>>[];
        final sub = repo.watchAll().listen(seen.add);
        await Future<void>.delayed(Duration.zero);

        await repo.update(
          _make(
            'w1',
            title: 'Pull',
            performedAt: DateTime(2026, 1, 2, 10),
            durationMinutes: 50,
            exercises: const [
              Exercise(name: 'Lat Pulldown', sets: 4, reps: 10, weightKg: 45),
            ],
          ),
        );
        await Future<void>.delayed(Duration.zero);

        // watchAll() is a broadcast stream, so a fresh `.first` here would wait
        // for the *next* emission (which never comes) — read the accumulated
        // emissions instead.
        final workouts = seen.last;
        expect(workouts, hasLength(1));
        final updated = workouts.single;
        expect(updated.id, 'w1');
        expect(updated.title, 'Pull');
        expect(updated.performedAt, DateTime(2026, 1, 2, 10));
        expect(updated.exercises.single.name, 'Lat Pulldown');

        final doc = await firestore
            .collection('users')
            .doc('test-uid')
            .collection('workouts')
            .doc('w1')
            .get();
        expect(doc.data()!['createdAt'], isA<Timestamp>());

        await sub.cancel();
      },
    );

    test(
      'add is idempotent by id: calling it twice with the same id overwrites, '
      'never duplicates (the guarantee LiveSessionPage\'s Finish relies on)',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repo = FirestoreWorkoutRepository(
          firestore: firestore,
          uidSource: _signedInAs('test-uid'),
        );

        // Same id, as a rapid double-tap on Finish would produce (the second
        // call races the first with an unchanged Workout built from the same
        // session).
        await repo.add(_make('w1', title: 'Push'));
        await repo.add(_make('w1', title: 'Push'));

        final workouts = await repo.watchAll().first;
        expect(workouts, hasLength(1));
        expect(workouts.single.id, 'w1');
      },
    );

    test('remove deletes the doc, no longer observed on the stream', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreWorkoutRepository(
        firestore: firestore,
        uidSource: _signedInAs('test-uid'),
      );

      await repo.add(_make('w1'));

      final seen = <List<Workout>>[];
      final sub = repo.watchAll().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, hasLength(1));

      await repo.remove('w1');
      await Future<void>.delayed(Duration.zero);
      expect(seen.last, isEmpty);

      await sub.cancel();
    });
  });
}
