import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/warmup_policy.dart';

void main() {
  group('warmupRampFor', () {
    test('below the 40kg qualifying threshold generates no ramp', () {
      expect(warmupRampFor(workingWeightKg: 39), isEmpty);
      expect(warmupRampFor(workingWeightKg: 0), isEmpty);
    });

    test('isolation/small-muscle-group lifts generate no ramp regardless of weight', () {
      expect(warmupRampFor(workingWeightKg: 60, muscleGroup: 'Biceps'), isEmpty);
      expect(warmupRampFor(workingWeightKg: 150, muscleGroup: 'Calves'), isEmpty);
      // Case-insensitive substring match, same classifier as rest_policy.
      expect(warmupRampFor(workingWeightKg: 80, muscleGroup: 'Rear delts'), isEmpty);
    });

    test('a qualifying light-to-moderate compound (40-59kg) gets a 2-step ramp: 40%x8, 60%x5', () {
      final ramp = warmupRampFor(workingWeightKg: 40, muscleGroup: 'Chest');
      expect(ramp, hasLength(2));
      expect(ramp[0], (weightKg: 20.0, reps: 8)); // 16 floored to the bar
      expect(ramp[1], (weightKg: 25.0, reps: 5)); // 24 rounds to 25
    });

    test('a moderate-to-heavy compound (60-100kg) gets a 3-step ramp: adds 80%x3', () {
      final ramp = warmupRampFor(workingWeightKg: 80, muscleGroup: 'Back');
      expect(ramp, hasLength(3));
      expect(ramp[0], (weightKg: 32.5, reps: 8)); // 32 rounds to 32.5
      expect(ramp[1], (weightKg: 47.5, reps: 5)); // 48 rounds to 47.5
      expect(ramp[2], (weightKg: 65.0, reps: 3)); // 64 rounds to 65
    });

    test('a heavy compound (>100kg) gets a 4-step ramp: adds 90%x1', () {
      final ramp = warmupRampFor(workingWeightKg: 120, muscleGroup: 'Legs');
      expect(ramp, hasLength(4));
      expect(ramp[0], (weightKg: 47.5, reps: 8)); // 48 rounds to 47.5
      expect(ramp[1], (weightKg: 72.5, reps: 5)); // 72 rounds to 72.5
      expect(ramp[2], (weightKg: 95.0, reps: 3)); // 96 rounds to 95
      expect(ramp[3], (weightKg: 107.5, reps: 1)); // 108 rounds to 107.5
    });

    test('the 60kg and 100kg boundaries land on the 3-step and 4-step tiers', () {
      expect(warmupRampFor(workingWeightKg: 60, muscleGroup: 'Chest'), hasLength(3));
      expect(warmupRampFor(workingWeightKg: 100, muscleGroup: 'Chest'), hasLength(3));
      expect(warmupRampFor(workingWeightKg: 100.1, muscleGroup: 'Chest'), hasLength(4));
    });

    test('every step floors at an empty 20kg bar', () {
      final ramp = warmupRampFor(workingWeightKg: 41, muscleGroup: 'Chest');
      expect(ramp.first.weightKg, 20.0); // 41*0.4=16.4 -> would round to 17.5, floored to 20
    });

    test('a lift with no muscle group given still qualifies as a compound', () {
      expect(warmupRampFor(workingWeightKg: 60), hasLength(3));
    });
  });
}
