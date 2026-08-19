import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/ziad_workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';

/// Builds a minimal split. [createdAt] drives the createdAt ordering the repo
/// exposes via [splits] / [watchSplits].
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

void main() {
  late InMemoryWorkoutPlanRepository repo;

  setUp(() => repo = InMemoryWorkoutPlanRepository());
  tearDown(() => repo.dispose());

  group('seed', () {
    test('opens on the owner real split, active', () {
      final seed = ziadWorkoutPlan();
      expect(repo.splits, hasLength(1));
      expect(repo.splits.single.id, seed.id);
      expect(repo.activeSplitId, seed.id);
      expect(repo.activePlan!.id, seed.id);
    });

    test('watchActivePlan replays the current active to a late subscriber', () {
      expect(repo.watchActivePlan(), emits(isA<WorkoutPlan>()));
    });

    test('watchSplits replays the current list to a late subscriber', () {
      expect(
        repo.watchSplits(),
        emits(predicate<List<WorkoutPlan>>((l) => l.length == 1)),
      );
    });
  });

  group('saveSplit', () {
    test('adds new splits without disturbing the active pointer', () async {
      final seed = ziadWorkoutPlan();
      await repo.saveSplit(_split('b', createdAt: DateTime(2024, 2, 1)));
      await repo.saveSplit(_split('c', createdAt: DateTime(2024, 3, 1)));

      expect(repo.splits.map((s) => s.id), containsAll(['b', 'c', seed.id]));
      expect(repo.splits, hasLength(3));
      // Adding new splits must not move active off the seed.
      expect(repo.activeSplitId, seed.id);
    });

    test('replaces by id (idempotent edit), no duplicate', () async {
      await repo.saveSplit(_split('b', name: 'First', createdAt: DateTime(2024, 2, 1)));
      await repo.saveSplit(_split('b', name: 'Renamed', createdAt: DateTime(2024, 2, 1)));

      final matches = repo.splits.where((s) => s.id == 'b').toList();
      expect(matches, hasLength(1));
      expect(matches.single.name, 'Renamed');
    });

    test('exposes splits in createdAt order', () async {
      await repo.saveSplit(_split('late', createdAt: DateTime(2025, 1, 1)));
      await repo.saveSplit(_split('early', createdAt: DateTime(2020, 1, 1)));

      final ids = repo.splits.map((s) => s.id).toList();
      expect(ids.indexOf('early'), lessThan(ids.indexOf('late')));
    });

    test('first save on an empty repo becomes active', () async {
      // Drain the seed so there is no active pointer.
      await repo.deleteSplit(ziadWorkoutPlan().id);
      expect(repo.activeSplitId, isNull);
      expect(repo.splits, isEmpty);

      await repo.saveSplit(_split('fresh'));
      expect(repo.activeSplitId, 'fresh');
      expect(repo.activePlan!.id, 'fresh');
    });

    test('watchSplits emits the updated list on save', () async {
      final expectation = expectLater(
        repo.watchSplits(),
        emitsInOrder([
          predicate<List<WorkoutPlan>>((l) => l.length == 1),
          predicate<List<WorkoutPlan>>((l) => l.length == 2),
        ]),
      );
      await pumpEventQueue();
      await repo.saveSplit(_split('b', createdAt: DateTime(2024, 2, 1)));
      await expectation;
    });
  });

  group('setActiveSplit', () {
    test('switches the active split and emits on watchActivePlan', () async {
      final seed = ziadWorkoutPlan();
      await repo.saveSplit(_split('b', createdAt: DateTime(2024, 2, 1)));

      final expectation = expectLater(
        repo.watchActivePlan(),
        emitsInOrder([
          predicate<WorkoutPlan?>((p) => p?.id == seed.id),
          predicate<WorkoutPlan?>((p) => p?.id == 'b'),
        ]),
      );
      await pumpEventQueue();

      await repo.setActiveSplit('b');
      await expectation;
      expect(repo.activeSplitId, 'b');
      expect(repo.activePlan!.id, 'b');
    });

    test('throws for an unknown id and leaves active unchanged', () async {
      final seed = ziadWorkoutPlan();
      expect(() => repo.setActiveSplit('nope'), throwsStateError);
      expect(repo.activeSplitId, seed.id);
    });
  });

  group('deleteSplit', () {
    test('removes a non-active split, active unchanged', () async {
      final seed = ziadWorkoutPlan();
      await repo.saveSplit(_split('b', createdAt: DateTime(2024, 2, 1)));

      await repo.deleteSplit('b');
      expect(repo.splits.map((s) => s.id), isNot(contains('b')));
      expect(repo.activeSplitId, seed.id);
    });

    test('repoints active to the first remaining split (createdAt order)', () async {
      await repo.saveSplit(_split('older', createdAt: DateTime(2020, 1, 1)));
      await repo.saveSplit(_split('newer', createdAt: DateTime(2030, 1, 1)));
      await repo.setActiveSplit('newer');

      await repo.deleteSplit('newer');
      // First remaining by createdAt is 'older' (2020) before the seed.
      expect(repo.activeSplitId, 'older');
    });

    test('active falls to null when the last split is deleted', () async {
      await repo.deleteSplit(ziadWorkoutPlan().id);
      expect(repo.splits, isEmpty);
      expect(repo.activeSplitId, isNull);
      expect(repo.activePlan, isNull);
    });

    test('deleting an unknown id is a no-op', () async {
      await repo.deleteSplit('ghost');
      expect(repo.splits, hasLength(1));
    });
  });

  group('back-compat facade', () {
    test('savePlan edits the active split in place', () async {
      final seed = ziadWorkoutPlan();
      final edited = _split(seed.id, name: 'Edited', createdAt: seed.createdAt);

      await repo.savePlan(edited);
      expect(repo.splits, hasLength(1));
      expect(repo.activeSplitId, seed.id);
      expect(repo.activePlan!.name, 'Edited');
    });

    test('savePlan saves a new plan AND makes it active (back-compat)', () async {
      // The old single-plan API replaced its one slot, so the saved plan was
      // always the active one. saveSplit (new) would leave the seed active;
      // savePlan must not.
      await repo.savePlan(_split('b', createdAt: DateTime(2024, 2, 1)));
      expect(repo.splits.map((s) => s.id), contains('b'));
      expect(repo.activeSplitId, 'b');
      expect(repo.activePlan!.id, 'b');
    });

    test('saveSplit adds a new split WITHOUT stealing active', () async {
      final seed = ziadWorkoutPlan();
      await repo.saveSplit(_split('b', createdAt: DateTime(2024, 2, 1)));
      expect(repo.splits.map((s) => s.id), contains('b'));
      expect(repo.activeSplitId, seed.id);
    });

    test('deletePlan is an alias for deleteSplit', () async {
      await repo.deletePlan(ziadWorkoutPlan().id);
      expect(repo.splits, isEmpty);
      expect(repo.activePlan, isNull);
    });

    test('watchActivePlan reflects an in-place edit of the active split', () async {
      final seed = ziadWorkoutPlan();
      final expectation = expectLater(
        repo.watchActivePlan(),
        emitsInOrder([
          predicate<WorkoutPlan?>((p) => p?.id == seed.id && p?.name != 'Edited'),
          predicate<WorkoutPlan?>((p) => p?.name == 'Edited'),
        ]),
      );
      await pumpEventQueue();
      await repo.savePlan(_split(seed.id, name: 'Edited', createdAt: seed.createdAt));
      await expectation;
    });
  });
}
