import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/ziad_workout_plan.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';

void main() {
  group('ziadWorkoutPlan (ingested PDF split)', () {
    test('is an active, pdf-sourced 5-day rotating cycle', () {
      final plan = ziadWorkoutPlan();
      expect(plan.source, WorkoutPlanSource.pdf);
      expect(plan.status, WorkoutPlanStatus.active);
      expect(plan.cycleCursor, 0);
      expect(plan.days, hasLength(5));
      expect(plan.days.map((d) => d.slot), ['A', 'B', 'C', 'D', 'E']);
      expect(
        plan.days.map((d) => d.label),
        ['Push', 'Pull', 'Chest & Back', 'Full Arm', 'Legs'],
      );
      // Days are contiguous, 0-based.
      expect(plan.days.map((d) => d.order), [0, 1, 2, 3, 4]);
    });

    test('exercise counts per day match the split (abs excluded, lumped split)', () {
      final days = {for (final d in ziadWorkoutPlan().days) d.label: d};
      expect(days['Push']!.exercises, hasLength(7));
      expect(days['Pull']!.exercises, hasLength(8));
      expect(days['Chest & Back']!.exercises, hasLength(6));
      expect(days['Full Arm']!.exercises, hasLength(7));
      // Legs: 6 lines, but the two lumped entries were split → 8.
      expect(days['Legs']!.exercises, hasLength(8));
    });

    test('rep targets: hypertrophy range, fixed-15 machines, and to-failure', () {
      final days = {for (final d in ziadWorkoutPlan().days) d.label: d};

      // Push: 8–10 range everywhere; the shoulder press machine is a single set.
      final push = days['Push']!;
      expect(push.exercises.every((e) => e.sets.every((s) => s.repTarget == const RepTarget.range(8, 10))), isTrue);
      final shoulderPress = push.exercises.firstWhere((e) => e.name == 'Shoulder Press Machine');
      expect(shoulderPress.sets, hasLength(1));

      // Pull: Hip Extension is 2 sets to failure, typed as failure.
      final hipExtension =
          days['Pull']!.exercises.firstWhere((e) => e.name == 'Hip Extension');
      expect(hipExtension.sets, hasLength(2));
      expect(hipExtension.sets.every((s) => s.repTarget == const RepTarget.toFailure()), isTrue);
      expect(hipExtension.sets.every((s) => s.type == SetType.failure), isTrue);

      // Legs: the split machine work is fixed 15 reps; the compounds are 8–10.
      final legs = days['Legs']!;
      for (final name in ['Adductor', 'Abductor', 'Leg Press', 'Standing Calf Raise']) {
        final e = legs.exercises.firstWhere((e) => e.name == name);
        expect(e.sets.every((s) => s.repTarget == const RepTarget.fixed(15)), isTrue, reason: name);
        expect(e.sets, hasLength(3), reason: name);
      }
      final hackSquat = legs.exercises.firstWhere((e) => e.name == 'Hack Squat');
      expect(hackSquat.sets, hasLength(3));
      expect(hackSquat.sets.first.repTarget, const RepTarget.range(8, 10));
    });

    test('rest defaults: 90s for strength sets, 60s for 15-rep / to-failure', () {
      final days = {for (final d in ziadWorkoutPlan().days) d.label: d};
      // An 8–10 set rests 90s.
      final bench = days['Push']!.exercises.first;
      expect(bench.sets.first.restSeconds, 90);
      // A 15-rep machine set rests 60s.
      final adductor = days['Legs']!.exercises.firstWhere((e) => e.name == 'Adductor');
      expect(adductor.sets.first.restSeconds, 60);
      // A to-failure set rests 60s.
      final hipExtension = days['Pull']!.exercises.firstWhere((e) => e.name == 'Hip Extension');
      expect(hipExtension.sets.first.restSeconds, 60);
    });

    test('no set carries a target weight (PDF Current/Goal fields were blank)', () {
      final plan = ziadWorkoutPlan();
      final allSets = [
        for (final d in plan.days)
          for (final e in d.exercises) ...e.sets,
      ];
      expect(allSets.every((s) => s.targetWeightKg == null), isTrue);
    });

    test('the in-memory repository opens on the ingested plan', () {
      final repo = InMemoryWorkoutPlanRepository();
      addTearDown(repo.dispose);
      expect(repo.activePlan?.id, 'ziad-arnold-split');
      expect(repo.activePlan?.source, WorkoutPlanSource.pdf);
      expect(repo.activePlan?.days, hasLength(5));
    });
  });
}
