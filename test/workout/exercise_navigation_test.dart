import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zivo/features/workout/data/in_memory_exercise_library_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/identity/canonical_exercise.dart';
import 'package:zivo/features/workout/domain/identity/equipment.dart';
import 'package:zivo/features/workout/domain/identity/exercise_choice.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/controllers/live_session_controller.dart';
import 'package:zivo/features/workout/presentation/widgets/live_session/exercise_navigation_sheets.dart';

/// Moving around a live workout: next/previous, jump, do later, skip, swap,
/// add — and the promise underneath all of it, that the current set stays
/// derived and nothing already logged is ever lost or re-attributed.
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  final t0 = DateTime(2026, 9, 25, 18);

  List<String> order(LiveSession s) => [for (final e in s.exercises) e.id];

  group('LiveSession exercise order', () {
    test('next then previous lands back where it started', () {
      final s = _session(t0);
      final next = s.rotatePending(1);
      expect(order(next), ['a', 'b', 'c'].sublist(1) + ['a']);
      expect(next.currentExercise!.id, 'b');
      expect(order(next.rotatePending(-1)), ['a', 'b', 'c']);
      expect(order(s.rotatePending(-1)), ['c', 'a', 'b']);
    });

    test('finished exercises stay ahead; only what is left moves', () {
      var s = _session(t0);
      for (final set in s.exercises.first.sets) {
        s = s.markSetDone('a', set.id, now: t0);
      }
      final moved = s.rotatePending(1);
      expect(order(moved), ['a', 'c', 'b']);
      expect(moved.currentExercise!.id, 'c');
    });

    test('rotating with one exercise left is a no-op', () {
      var s = _session(t0);
      s = s.skipRemainingSets('a', now: t0).skipRemainingSets('b', now: t0);
      expect(identical(s.rotatePending(1), s), isTrue);
    });

    test('bringForward makes the chosen exercise current, the rest keep '
        'their order', () {
      final s = _session(t0).bringForward('c');
      expect(order(s), ['c', 'a', 'b']);
      expect(s.currentExercise!.id, 'c');
    });

    test('moveToEnd defers an exercise without touching its sets', () {
      final s = _session(t0).moveToEnd('a');
      expect(order(s), ['b', 'c', 'a']);
      expect(s.exercises.last.sets.every((x) => x.pending), isTrue);
    });

    test('a half-done exercise moved later keeps its logged set', () {
      var s = _session(t0);
      s = s.markSetDone('a', 'a-s0', now: t0, actualReps: 8, actualWeightKg: 60);
      s = s.moveToEnd('a');
      expect(order(s), ['b', 'c', 'a']);
      expect(s.exercises.last.sets.first.done, isTrue);
      expect(s.exercises.last.sets.first.actualWeightKg, 60);
      expect(s.currentExercise!.id, 'b');
    });

    test('skipRemainingSets skips only what was still pending', () {
      var s = _session(t0);
      s = s.markSetDone('a', 'a-s0', now: t0, actualReps: 8);
      s = s.skipRemainingSets('a', now: t0);
      final a = s.exercises.first;
      expect(a.sets[0].done, isTrue);
      expect(a.sets[1].skipped, isTrue);
      expect(s.completedSetCount, 1, reason: 'a skip is never counted');
      expect(s.currentExercise!.id, 'b');
    });
  });

  group('previousResolvedSet follows time, not list order', () {
    test('after a jump, Back walks back the set resolved last', () {
      var s = _session(t0);
      s = s.markSetDone('a', 'a-s0', now: t0);
      s = s.bringForward('c');
      s = s.markSetDone('c', 'c-s0', now: t0.add(const Duration(minutes: 3)));
      expect(s.previousResolvedSet!.$2.id, 'c-s0');
      s = s.clearOutcome('c', 'c-s0');
      expect(s.previousResolvedSet!.$2.id, 'a-s0');
    });

    test('equal timestamps fall back to list order (the later set)', () {
      var s = _session(t0);
      s = s.markSetDone('a', 'a-s0', now: t0).markSetDone('a', 'a-s1', now: t0);
      expect(s.previousResolvedSet!.$2.id, 'a-s1');
    });
  });

  group('swapExercise', () {
    test('nothing logged → replaced in place, slot kept, loads dropped', () {
      final s = _session(t0).swapExercise(
        'a',
        newId: 'z',
        canonicalId: 'x-db-press',
        name: 'Dumbbell Press',
        muscleGroup: 'Chest',
      );
      expect(order(s), ['z', 'b', 'c']);
      final z = s.exercises.first;
      expect(z.exerciseId, 'x-db-press');
      expect(z.slotId, 'a', reason: 'the substitute filled the same slot');
      expect(z.sets, hasLength(2));
      expect(z.sets.every((x) => x.targetWeightKg == null), isTrue);
      expect(z.sets.first.target, const RepTarget.range(6, 8));
    });

    test('some sets logged → they stay on the original exercise, the rest '
        'move to the substitute right after it', () {
      var s = _session(t0);
      s = s.markSetDone('a', 'a-s0', now: t0, actualReps: 8, actualWeightKg: 60);
      s = s.swapExercise('a', newId: 'z', canonicalId: 'x-z', name: 'Z');
      expect(order(s), ['a', 'z', 'b', 'c']);
      expect(s.exercises[0].exerciseId, 'a');
      expect(s.exercises[0].sets.single.actualWeightKg, 60);
      expect(s.exercises[1].sets, hasLength(1));
      expect(s.currentExercise!.id, 'z');
    });

    test('a finished exercise cannot be swapped', () {
      var s = _session(t0).skipRemainingSets('a', now: t0);
      expect(
        identical(
          s.swapExercise('a', newId: 'z', canonicalId: 'x', name: 'Z'),
          s,
        ),
        isTrue,
      );
    });
  });

  group('resolveExerciseChoice', () {
    final library = [
      CanonicalExercise(
        id: 'x-incline-db',
        name: 'Incline Dumbbell Press',
        equipment: Equipment.dumbbell,
        createdAt: DateTime(2026),
      ),
    ];

    test('a picked exercise keeps its id', () {
      final r = resolveExerciseChoice(
        const ExerciseChoice(canonicalId: 'x-1', name: 'Anything'),
        library: library,
        newId: () => 'new',
        now: t0,
      );
      expect(r.canonicalId, 'x-1');
      expect(r.created, isNull);
    });

    test('a typed name that is confidently an existing exercise links to it',
        () {
      final r = resolveExerciseChoice(
        const ExerciseChoice(name: 'incline db press'),
        library: library,
        newId: () => 'new',
        now: t0,
      );
      expect(r.canonicalId, 'x-incline-db');
      expect(r.created, isNull);
    });

    test('a different variation or equipment becomes a new exercise', () {
      final machine = resolveExerciseChoice(
        const ExerciseChoice(name: 'Incline Machine Press'),
        library: library,
        newId: () => 'new',
        now: t0,
      );
      expect(machine.canonicalId, 'new');
      expect(machine.created!.equipment, Equipment.machine);
    });
  });

  group('the controller', () {
    test('next/previous re-prefill for the exercise that became current',
        () {
      final c = _controller(t0);
      addTearDown(c.dispose);
      c.start();
      c.endWarmup();
      expect(c.canChangeExercise, isTrue);
      c.nextExercise();
      expect(c.session.currentExercise!.id, 'b');
      expect(c.weight.text, '40', reason: "b's own plan load, not a's");
      c.previousExercise();
      expect(c.session.currentExercise!.id, 'a');
      expect(c.weight.text, '60');
    });

    test('a typed draft stays on the set it was typed for when moving on',
        () {
      final c = _controller(t0);
      addTearDown(c.dispose);
      c.start();
      c.endWarmup();
      c.reps.text = '7';
      c.onActualChanged();
      c.nextExercise();
      final a = c.session.exercises.firstWhere((e) => e.id == 'a');
      expect(a.sets.first.actualReps, 7);
      expect(a.sets.first.pending, isTrue);
    });

    test('skipping the last exercise still owed completes the session', () {
      final c = _controller(t0);
      addTearDown(c.dispose);
      c.start();
      c.endWarmup();
      c.skipExercise('a');
      c.skipExercise('b');
      expect(c.session.isComplete, isFalse);
      c.skipExercise('c');
      expect(c.session.isComplete, isTrue);
    });

    test('a swap to a typed name gets its own identity, saved to the library',
        () async {
      final library = InMemoryExerciseLibraryRepository();
      final c = _controller(t0, library: library);
      addTearDown(c.dispose);
      c.start();
      c.endWarmup();
      c.swapExercise('a', const ExerciseChoice(name: 'Machine Chest Press'));
      await Future<void>.delayed(Duration.zero);
      final swapped = c.session.exercises.first;
      expect(swapped.name, 'Machine Chest Press');
      expect(swapped.exerciseId, startsWith('x-'));
      expect(library.current.exercises[swapped.exerciseId]?.name,
          'Machine Chest Press');
    });

    test('adding an exercise appends it; start-now makes it current', () {
      final c = _controller(t0);
      addTearDown(c.dispose);
      c.start();
      c.endWarmup();
      c.addExercise(const ExerciseChoice(canonicalId: 'x-f', name: 'Face Pull'));
      expect(c.session.exercises.last.exerciseId, 'x-f');
      expect(c.session.exercises.last.slotId, isNull);
      c.addExercise(
        const ExerciseChoice(canonicalId: 'x-g', name: 'Shrug'),
        startNow: true,
      );
      expect(c.session.currentExercise!.exerciseId, 'x-g');
    });

    test('an exercise with a logged set cannot be removed; a pending set '
        'can, a done one cannot', () async {
      final c = _controller(t0);
      addTearDown(c.dispose);
      c.start();
      c.endWarmup();
      c.reps.text = '8';
      c.setDone(reducedMotion: true);
      // The resolve settles on the next turn; structure waits for it.
      await Future<void>.delayed(Duration.zero);
      c.removeExercise('a');
      expect(c.session.exercises.map((e) => e.id), contains('a'));
      c.removeSet('a', 'a-s0');
      expect(c.session.exercises.first.sets, hasLength(2));
      c.removeSet('a', 'a-s1');
      expect(c.session.exercises.first.sets, hasLength(1));
      c.removeExercise('b');
      expect(c.session.exercises.map((e) => e.id), isNot(contains('b')));
    });

    test('adding a set to a finished exercise makes it current again', () {
      final c = _controller(t0);
      addTearDown(c.dispose);
      c.start();
      c.endWarmup();
      c.skipExercise('a');
      expect(c.session.currentExercise!.id, 'b');
      c.addSet('a');
      expect(c.session.currentExercise!.id, 'a');
      expect(c.session.exercises.first.sets, hasLength(3));
    });
  });

  group('actionsFor', () {
    test('only what keeps the record intact is offered', () {
      var s = _session(t0);
      expect(actionsFor(s, s.exercises.first), [
        ExerciseAction.doLater,
        ExerciseAction.swap,
        ExerciseAction.addSet,
        ExerciseAction.removeSet,
        ExerciseAction.skip,
        ExerciseAction.remove,
      ]);
      s = s.markSetDone('a', 'a-s0', now: t0);
      expect(actionsFor(s, s.exercises.first), isNot(contains(ExerciseAction.remove)));
      final c = s.exercises.last;
      expect(actionsFor(s, c), contains(ExerciseAction.doNow));
      expect(actionsFor(s, c), isNot(contains(ExerciseAction.doLater)),
          reason: 'already last');
      s = s.skipRemainingSets('a', now: t0);
      expect(actionsFor(s, s.exercises.first), [ExerciseAction.addSet]);
    });
  });
}

PlannedExercise _slot(String id, String name, double load, {int sets = 2}) =>
    PlannedExercise(
      id: id,
      name: name,
      order: 0,
      muscleGroup: 'Chest',
      defaultRestSeconds: 90,
      sets: [
        for (var i = 0; i < sets; i++)
          PlannedSet(
            order: i,
            repTarget: const RepTarget.range(6, 8),
            restSeconds: 90,
            targetWeightKg: load,
            type: SetType.working,
          ),
      ],
    );

final WorkoutDay _day = WorkoutDay(
  id: 'd',
  slot: 'A',
  label: 'Push',
  order: 0,
  exercises: [
    _slot('a', 'Bench Press', 60),
    _slot('b', 'Incline Dumbbell Press', 40),
    _slot('c', 'Cable Fly', 20, sets: 1),
  ],
);

LiveSession _session(DateTime now) =>
    LiveSession.start(_day, id: 's', planId: 'p', now: now);

LiveSessionController _controller(
  DateTime now, {
  InMemoryExerciseLibraryRepository? library,
}) => LiveSessionController(
  day: _day,
  plan: WorkoutPlan(
    id: 'p',
    name: 'Split',
    status: WorkoutPlanStatus.active,
    source: WorkoutPlanSource.manual,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    days: [_day],
  ),
  sessions: InMemoryWorkoutSessionRepository(),
  vsync: _NoopTickerProvider(),
  now: () => now,
  exerciseLibrary: library,
);

class _NoopTickerProvider implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}
