import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/home/presentation/training_builder.dart';
import 'package:zivo/features/workout/domain/exercise.dart';
import 'package:zivo/features/workout/domain/workout.dart';

void main() {
  final now = DateTime(2026, 1, 10, 18);

  Workout workout(String id, DateTime performedAt) => Workout(
    id: id,
    title: 'Push',
    performedAt: performedAt,
    exercises: const [Exercise(name: 'Bench Press', sets: 4, reps: 8)],
  );

  group('todaysWorkout', () {
    test('null when the list is empty', () {
      expect(todaysWorkout(const [], now), isNull);
    });

    test('null when no workout was performed today', () {
      final all = [
        workout('w1', now.subtract(const Duration(days: 1))),
        workout('w2', now.add(const Duration(days: 1))),
      ];
      expect(todaysWorkout(all, now), isNull);
    });

    test('returns the workout performed today', () {
      final today = workout('w1', DateTime(2026, 1, 10, 7));
      final all = [
        workout('w0', now.subtract(const Duration(days: 1))),
        today,
      ];
      expect(todaysWorkout(all, now), same(today));
    });

    test('picks the most-recent workout when several match today', () {
      final earlier = workout('w1', DateTime(2026, 1, 10, 7));
      final later = workout('w2', DateTime(2026, 1, 10, 17));
      final all = [earlier, later];
      expect(todaysWorkout(all, now), same(later));
    });
  });
}
