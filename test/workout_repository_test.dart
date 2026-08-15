import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/domain/exercise.dart';
import 'package:zivo/features/workout/domain/workout.dart';

Workout _make(String id) => Workout(
      id: id,
      title: 'Session $id',
      performedAt: DateTime(2026, 1, 1),
      exercises: const [Exercise(name: 'Bench', sets: 3, reps: 10)],
    );

void main() {
  test('seeds with a demo workout exposed via current', () {
    final repo = InMemoryWorkoutRepository();
    addTearDown(repo.dispose);

    expect(repo.current, isNotEmpty);
    expect(repo.current.first.title, 'Push');
  });

  test('add inserts newest-first', () async {
    final repo = InMemoryWorkoutRepository();
    addTearDown(repo.dispose);

    await repo.add(_make('a'));
    expect(repo.current.first.id, 'a');

    await repo.add(_make('b'));
    expect(repo.current.first.id, 'b');
  });

  test('current is unmodifiable', () {
    final repo = InMemoryWorkoutRepository();
    addTearDown(repo.dispose);

    expect(() => repo.current.add(_make('x')), throwsUnsupportedError);
  });

  test('watchAll emits the seed then each addition', () async {
    final repo = InMemoryWorkoutRepository();
    addTearDown(repo.dispose);

    final seen = <int>[];
    final sub = repo.watchAll().listen((list) => seen.add(list.length));
    await Future<void>.delayed(Duration.zero);

    await repo.add(_make('a'));
    await Future<void>.delayed(Duration.zero);

    await sub.cancel();
    expect(seen, [1, 2]);
  });
}
