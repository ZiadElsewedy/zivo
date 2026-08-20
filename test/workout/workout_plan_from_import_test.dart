import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_import_result.dart';
import 'package:zivo/features/workout/domain/workout_plan_from_import.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';

void main() {
  group('workoutPlanFromImport', () {
    test('mints a fresh id/createdAt/updatedAt and marks source as pdf', () {
      final result = const WorkoutImportResult(planName: 'PPL', days: []);
      final now = DateTime(2026, 1, 1);

      final plan = workoutPlanFromImport(result, id: 'p1', now: now);

      expect(plan.id, 'p1');
      expect(plan.name, 'PPL');
      expect(plan.source, WorkoutPlanSource.pdf);
      expect(plan.createdAt, now);
      expect(plan.updatedAt, now);
      expect(plan.cycleCursor, 0);
    });

    test('a fixed rep count (repsMin == repsMax) becomes RepTarget.fixed', () {
      final result = const WorkoutImportResult(
        planName: 'X',
        days: [
          ImportedDay(
            slot: 'A',
            label: 'Push',
            exercises: [
              ImportedExercise(name: 'Bench', sets: 3, repsMin: 10, repsMax: 10, toFailure: false),
            ],
          ),
        ],
      );

      final plan = workoutPlanFromImport(result, id: 'p1', now: DateTime(2026, 1, 1));
      final set = plan.days.single.exercises.single.sets.first;

      expect(set.repTarget, const RepTarget.fixed(10));
    });

    test('a real range (repsMin != repsMax) becomes RepTarget.range', () {
      final result = const WorkoutImportResult(
        planName: 'X',
        days: [
          ImportedDay(
            slot: 'A',
            label: 'Push',
            exercises: [
              ImportedExercise(name: 'Bench', sets: 3, repsMin: 8, repsMax: 12, toFailure: false),
            ],
          ),
        ],
      );

      final plan = workoutPlanFromImport(result, id: 'p1', now: DateTime(2026, 1, 1));
      final set = plan.days.single.exercises.single.sets.first;

      expect(set.repTarget, const RepTarget.range(8, 12));
    });

    test('a reversed range (repsMin > repsMax) is swapped, not passed through to the range assert', () {
      final result = const WorkoutImportResult(
        planName: 'X',
        days: [
          ImportedDay(
            slot: 'A',
            label: 'Push',
            exercises: [
              ImportedExercise(name: 'Descending Pyramid', sets: 3, repsMin: 12, repsMax: 8, toFailure: false),
            ],
          ),
        ],
      );

      final plan = workoutPlanFromImport(result, id: 'p1', now: DateTime(2026, 1, 1));
      final set = plan.days.single.exercises.single.sets.first;

      expect(set.repTarget, const RepTarget.range(8, 12));
    });

    test('toFailure: true becomes RepTarget.toFailure regardless of reps fields', () {
      final result = const WorkoutImportResult(
        planName: 'X',
        days: [
          ImportedDay(
            slot: 'A',
            label: 'Push',
            exercises: [
              ImportedExercise(name: 'Push-up', sets: 3, toFailure: true),
            ],
          ),
        ],
      );

      final plan = workoutPlanFromImport(result, id: 'p1', now: DateTime(2026, 1, 1));
      final set = plan.days.single.exercises.single.sets.first;

      expect(set.repTarget, const RepTarget.toFailure());
    });

    test('missing rep info (no range, no toFailure) falls back to a sane fixed default', () {
      final result = const WorkoutImportResult(
        planName: 'X',
        days: [
          ImportedDay(
            slot: 'A',
            label: 'Push',
            exercises: [ImportedExercise(name: 'Mystery Move', sets: 2, toFailure: false)],
          ),
        ],
      );

      final plan = workoutPlanFromImport(result, id: 'p1', now: DateTime(2026, 1, 1));
      final set = plan.days.single.exercises.single.sets.first;

      expect(set.repTarget, const RepTarget.fixed(8));
    });

    test('sets count expands into that many identical PlannedSets, all working type', () {
      final result = const WorkoutImportResult(
        planName: 'X',
        days: [
          ImportedDay(
            slot: 'A',
            label: 'Push',
            exercises: [
              ImportedExercise(
                name: 'Bench',
                sets: 4,
                repsMin: 8,
                repsMax: 8,
                toFailure: false,
                targetWeightKg: 60,
                restSeconds: 120,
              ),
            ],
          ),
        ],
      );

      final plan = workoutPlanFromImport(result, id: 'p1', now: DateTime(2026, 1, 1));
      final exercise = plan.days.single.exercises.single;

      expect(exercise.sets, hasLength(4));
      expect(exercise.sets.map((s) => s.order), [0, 1, 2, 3]);
      expect(exercise.sets.every((s) => s.targetWeightKg == 60), isTrue);
      expect(exercise.sets.every((s) => s.restSeconds == 120), isTrue);
      expect(exercise.sets.every((s) => s.type == SetType.working), isTrue);
      expect(exercise.defaultRestSeconds, 120);
    });

    test('a zero/negative sets count is clamped to at least 1 set', () {
      final result = const WorkoutImportResult(
        planName: 'X',
        days: [
          ImportedDay(
            slot: 'A',
            label: 'Push',
            exercises: [ImportedExercise(name: 'Bench', sets: 0, toFailure: false)],
          ),
        ],
      );

      final plan = workoutPlanFromImport(result, id: 'p1', now: DateTime(2026, 1, 1));
      expect(plan.days.single.exercises.single.sets, hasLength(1));
    });

    test('a missing restSeconds defaults to 90s', () {
      final result = const WorkoutImportResult(
        planName: 'X',
        days: [
          ImportedDay(
            slot: 'A',
            label: 'Push',
            exercises: [ImportedExercise(name: 'Bench', sets: 1, toFailure: false)],
          ),
        ],
      );

      final plan = workoutPlanFromImport(result, id: 'p1', now: DateTime(2026, 1, 1));
      expect(plan.days.single.exercises.single.defaultRestSeconds, 90);
    });

    test('a blank slot falls back to A, B, C… in day order', () {
      final result = const WorkoutImportResult(
        planName: 'X',
        days: [
          ImportedDay(slot: '', label: 'Push', exercises: []),
          ImportedDay(slot: '', label: 'Pull', exercises: []),
        ],
      );

      final plan = workoutPlanFromImport(result, id: 'p1', now: DateTime(2026, 1, 1));
      expect(plan.days.map((d) => d.slot), ['A', 'B']);
    });

    test('day and exercise ids are minted, unique, and derived from the plan id', () {
      final result = const WorkoutImportResult(
        planName: 'X',
        days: [
          ImportedDay(
            slot: 'A',
            label: 'Push',
            exercises: [
              ImportedExercise(name: 'Bench', sets: 1, toFailure: false),
              ImportedExercise(name: 'Overhead Press', sets: 1, toFailure: false),
            ],
          ),
          ImportedDay(
            slot: 'B',
            label: 'Pull',
            exercises: [ImportedExercise(name: 'Row', sets: 1, toFailure: false)],
          ),
        ],
      );

      final plan = workoutPlanFromImport(result, id: 'p1', now: DateTime(2026, 1, 1));
      final dayIds = plan.days.map((d) => d.id).toList();
      final exerciseIds = plan.days.expand((d) => d.exercises.map((e) => e.id)).toList();

      expect(dayIds.toSet(), hasLength(dayIds.length)); // unique
      expect(exerciseIds.toSet(), hasLength(exerciseIds.length)); // unique
      expect(dayIds.every((id) => id.startsWith('p1-')), isTrue);
      expect(exerciseIds.every((id) => id.startsWith('p1-')), isTrue);
    });
  });
}
