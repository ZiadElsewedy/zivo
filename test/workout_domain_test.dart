import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/exercise.dart';
import 'package:zivo/features/workout/domain/workout.dart';
import 'package:zivo/features/workout/domain/workout_format.dart';

void main() {
  group('setRepLabel', () {
    test('omits the load when none is set', () {
      const e = Exercise(name: 'Cable Fly', sets: 3, reps: 12);
      expect(setRepLabel(e), '3 × 12');
    });

    test('shows an integer weight without a trailing .0', () {
      const e = Exercise(name: 'Bench Press', sets: 4, reps: 8, weightKg: 60);
      expect(setRepLabel(e), '4 × 8 · 60kg');
    });

    test('keeps a fractional weight', () {
      const e = Exercise(name: 'Incline DB', sets: 3, reps: 10, weightKg: 22.5);
      expect(setRepLabel(e), '3 × 10 · 22.5kg');
    });
  });

  group('workoutMeta', () {
    test('pluralises exercises and appends duration', () {
      final w = Workout(
        id: 'w1',
        title: 'Push',
        performedAt: DateTime(2026, 1, 1),
        durationMinutes: 50,
        exercises: const [
          Exercise(name: 'A', sets: 3, reps: 10),
          Exercise(name: 'B', sets: 3, reps: 10),
        ],
      );
      expect(workoutMeta(w), '2 exercises · ~50 min');
    });

    test('uses the singular for one exercise and drops absent duration', () {
      final w = Workout(
        id: 'w2',
        title: 'Quick',
        performedAt: DateTime(2026, 1, 1),
        exercises: const [Exercise(name: 'A', sets: 1, reps: 5)],
      );
      expect(workoutMeta(w), '1 exercise');
    });
  });

  group('Workout getters', () {
    test('summary joins exercise names and count matches', () {
      final w = Workout(
        id: 'w3',
        title: 'Pull',
        performedAt: DateTime(2026, 1, 1),
        exercises: const [
          Exercise(name: 'Row', sets: 4, reps: 8),
          Exercise(name: 'Curl', sets: 3, reps: 12),
        ],
      );
      expect(w.exerciseCount, 2);
      expect(w.summary, 'Row · Curl');
    });
  });
}
