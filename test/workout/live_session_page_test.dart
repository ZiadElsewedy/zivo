import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_outcome.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_repository.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_repository.dart';
import 'package:zivo/features/workout/domain/workout_session_repository.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/presentation/pages/live_session_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// Records what the player writes, so tests can assert the completion path
/// persists and the discard path writes nothing. [add] resolves after a
/// small artificial delay — Finish now fires this write unawaited (so it
/// commits to the local cache and syncs later without blocking navigation,
/// the fix for hanging offline), so this delay proves the button doesn't
/// wait for it, not that it's slow to record.
class _RecordingWorkoutRepository implements WorkoutRepository {
  final List<Workout> added = [];

  @override
  List<Workout> get current => added;

  @override
  Stream<List<Workout>> watchAll() => Stream.value(added);

  @override
  Future<void> add(Workout workout) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    added.add(workout);
  }

  @override
  Future<void> update(Workout workout) async {}

  @override
  Future<void> remove(String id) async {}
}

/// A [WorkoutRepository] whose [add] never completes — simulates being
/// genuinely offline, where the write's Future waits for a server ack that
/// isn't coming. Used to prove Finish doesn't block on it.
class _NeverCompletingWorkoutRepository implements WorkoutRepository {
  @override
  List<Workout> get current => const [];

  @override
  Stream<List<Workout>> watchAll() => const Stream.empty();

  @override
  Future<void> add(Workout workout) => Completer<void>().future;

  @override
  Future<void> update(Workout workout) => Completer<void>().future;

  @override
  Future<void> remove(String id) => Completer<void>().future;
}

class _RecordingWorkoutPlanRepository implements WorkoutPlanRepository {
  final List<WorkoutPlan> saved = [];
  WorkoutPlan? _active;

  @override
  WorkoutPlan? get activePlan => _active;

  @override
  Stream<WorkoutPlan?> watchActivePlan() => Stream.value(_active);

  @override
  Future<void> savePlan(WorkoutPlan plan) async {
    saved.add(plan);
    _active = plan;
  }

  @override
  Future<void> deletePlan(String id) async {}

  @override
  List<WorkoutPlan> get splits =>
      activePlan == null ? const <WorkoutPlan>[] : <WorkoutPlan>[activePlan!];

  @override
  Stream<List<WorkoutPlan>> watchSplits() => Stream.value(splits);

  @override
  String? get activeSplitId => activePlan?.id;

  @override
  Future<void> setActiveSplit(String id) async {}

  @override
  Future<void> saveSplit(WorkoutPlan plan) => savePlan(plan);

  @override
  Future<void> deleteSplit(String id) => deletePlan(id);
}

WorkoutPlan _plan() => WorkoutPlan(
  id: 'p1',
  name: 'Test Split',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  cycleCursor: 0,
  days: const [
    WorkoutDay(
      id: 'a',
      slot: 'A',
      label: 'Push',
      order: 0,
      exercises: [
        PlannedExercise(
          id: 'ex1',
          name: 'Bench',
          order: 0,
          muscleGroup: 'Chest',
          defaultRestSeconds: 90,
          sets: [
            PlannedSet(order: 0, repTarget: RepTarget.fixed(5), restSeconds: 90, type: SetType.working),
            PlannedSet(order: 1, repTarget: RepTarget.fixed(5), restSeconds: 60, type: SetType.working),
          ],
        ),
      ],
    ),
    WorkoutDay(id: 'b', slot: 'B', label: 'Pull', order: 1, exercises: []),
  ],
);


/// A completed session from "last time", trained on the same canonical
/// exercise id ('ex1') so `lastPerformanceFor` picks it up.
LiveSession _previousSession() => LiveSession(
  id: 'prev1',
  planId: 'p1',
  dayId: 'a',
  dayLabel: 'Push',
  startedAt: DateTime(2026, 1, 1, 9),
  completedAt: DateTime(2026, 1, 1, 10),
  status: SessionStatus.completed,
  exercises: const [
    SessionExercise(
      id: 'ex1',
      exerciseId: 'ex1',
      name: 'Bench',
      restSeconds: 90,
      sets: [
        LoggedSet(
          id: 's0',
          target: RepTarget.fixed(5),
          outcome: SetOutcome.completed,
          actualReps: 5,
          actualWeightKg: 55,
        ),
        LoggedSet(
          id: 's1',
          target: RepTarget.fixed(5),
          outcome: SetOutcome.completed,
          actualReps: 5,
          actualWeightKg: 57.5,
        ),
      ],
    ),
  ],
);

/// Same shape as [_previousSession], but at a lighter weight — kept for
/// tests exercising progression/rest/finish that aren't about the (now
/// retired) per-exercise warm-up ramp.
LiveSession _previousSessionLight() => LiveSession(
  id: 'prev1',
  planId: 'p1',
  dayId: 'a',
  dayLabel: 'Push',
  startedAt: DateTime(2026, 1, 1, 9),
  completedAt: DateTime(2026, 1, 1, 10),
  status: SessionStatus.completed,
  exercises: const [
    SessionExercise(
      id: 'ex1',
      exerciseId: 'ex1',
      name: 'Bench',
      restSeconds: 90,
      sets: [
        LoggedSet(
          id: 's0',
          target: RepTarget.fixed(5),
          outcome: SetOutcome.completed,
          actualReps: 5,
          actualWeightKg: 30,
        ),
        LoggedSet(
          id: 's1',
          target: RepTarget.fixed(5),
          outcome: SetOutcome.completed,
          actualReps: 5,
          actualWeightKg: 32.5,
        ),
      ],
    ),
  ],
);

Widget _wrap({
  required WorkoutRepository workouts,
  required WorkoutPlanRepository workoutPlans,
  required WorkoutSessionRepository workoutSessions,
  required WorkoutDay day,
  required WorkoutPlan plan,
  LiveSession? resume,
  DateTime Function()? now,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: workouts,
    workoutPlans: workoutPlans,
    workoutSessions: workoutSessions,
    university: InMemoryUniversityRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      LiveSessionPage(day: day, plan: plan, resume: resume, now: now),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// [LiveSessionPage] wraps its current-set/rest indicators in *repeating*
/// animation controllers (the ember pulse, the rest ring's stroke glow) that
/// never settle on their own — `pumpAndSettle` would hang while either view
/// is on screen, so every step advances by a fixed, generous duration instead.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

/// Dismisses the Undo snackbar (shown after every Done/Skip) and lets its
/// exit animation finish — otherwise it sits over the next phase's bottom
/// action button for its multi-second duration, exactly like it would for a
/// real user who taps through it rather than waiting or tapping Undo. Only
/// needed by tests that chain another tap onto the bottom action area right
/// after a Done/Skip; everything else is unaffected by the snackbar existing.
Future<void> _dismissUndoSnackbar(WidgetTester tester) async {
  final messengers = find.byType(ScaffoldMessenger);
  if (messengers.evaluate().isEmpty) return;
  tester.state<ScaffoldMessengerState>(messengers.first).clearSnackBars();
  // Empirically needs several discrete pumps, not one big time jump, to
  // actually clear the SnackBar's hit-testable overlay entry.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Taps 'go' and settles, then skips the pre-workout warm-up phase if it's
/// showing — a genuinely fresh (non-resume, nothing-done) session always
/// opens on it now, so every test below that isn't specifically about
/// warm-up uses this instead of a bare tap+settle to land straight on the
/// first set, same as before that phase existed. A resumed session never
/// shows it, so this is safe to use unconditionally.
Future<void> _start(WidgetTester tester) async {
  await tester.tap(find.text('go'));
  await _settle(tester);
  if (find.text('Skip warm-up').evaluate().isNotEmpty) {
    await tester.tap(find.text('Skip warm-up'));
    await _settle(tester);
  }
}

String elapsedText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('elapsed-timer'))).data!;

/// The premium rest ring's sub-second label ("M:SS.CC" or "SS.CC"), read
/// back as plain text — the whole-second and ".CC" parts each live in their
/// own fixed-width slot (see `_FixedSlot` in live_session_page.dart) as
/// separate `Text` widgets, keyed individually, so this joins them back.
String restTimeText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('rest-time-whole'))).data! +
    tester.widget<Text>(find.byKey(const Key('rest-time-centis'))).data!;

/// Rounds the rest ring's displayed text back to whole seconds. Tests assert
/// against this (not the exact sub-second string) because the premium
/// countdown is continuous — its hundredths drift with however much real
/// wall-clock time a test happens to take to execute (most of these tests
/// don't inject a fake `now`), so only the coarse value is deterministic.
/// `closeTo(expected, 1)` at call sites absorbs the ±1s rounding edge.
int restWholeSeconds(WidgetTester tester) {
  final text = restTimeText(tester);
  final match = RegExp(r'^(?:(\d+):)?(\d{2})\.(\d{2})$').firstMatch(text)!;
  final minutes = int.parse(match.group(1) ?? '0');
  final seconds = int.parse(match.group(2)!);
  final centis = int.parse(match.group(3)!);
  return minutes * 60 + seconds + (centis >= 50 ? 1 : 0);
}

void main() {
  testWidgets(
    'happy path: start → previous performance + delta → done → rest (±15s) → '
    'skip → complete → finish persists + advances',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      // A weight under the 40kg warm-up threshold — this test is about
      // progression/rest/finish, not warm-up materialization (see the
      // dedicated warm-up tests below), so it uses the light fixture.
      await sessions.saveSession(_previousSessionLight());
      final plan = _plan();

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
        ),
      );
      await _start(tester);

      // Set 1 of the first exercise, last time + computed goal both shown.
      // Previous: 30kg x 5, hit the fixed target's top (5>=5) → +2.5kg
      // compound (Chest), reps reset to the same fixed count.
      expect(find.text('Set 1 of 2'), findsOneWidget);
      expect(find.text('Bench'), findsOneWidget);
      expect(find.text('Last time: 30kg × 5'), findsOneWidget);
      expect(find.text('32.5kg × 5'), findsOneWidget); // the Goal label

      // Reps/weight are prefilled from the goal, not the bare plan target.
      final repsField = tester.widget<TextField>(find.byType(TextField).at(0));
      final weightField = tester.widget<TextField>(find.byType(TextField).at(1));
      expect(repsField.controller!.text, '5');
      expect(weightField.controller!.text, '32.5');

      // Autosaved as an active session as soon as it starts.
      expect(sessions.current.any((s) => s.status == SessionStatus.active), isTrue);

      // Type a heavier weight than last time (reps unchanged at the
      // prefilled 5) → volume 150 → 175 = +16.67%, rounds to the verdict
      // badge's "Progressing +17%". Reps is the first TextField (index 0),
      // Weight the second (index 1).
      await tester.enterText(find.byType(TextField).at(1), '35');
      await tester.pump();
      expect(find.text('Progressing +17%'), findsOneWidget);

      // Complete set 1 → the session counts down the exercise's own plan
      // rest (90s, "1:30") — the plan Ziad set in Edit Workout, not a
      // computed smart-rest guess.
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await _settle(tester);
      await _dismissUndoSnackbar(tester);
      expect(find.text('Skip rest'), findsOneWidget);
      expect(restWholeSeconds(tester), closeTo(90, 1));
      expect(find.text('REST'), findsOneWidget);
      expect(find.textContaining('Next:'), findsOneWidget);

      // The just-logged set now shows as done (autosaved).
      final midSession = sessions.current.firstWhere((s) => s.status == SessionStatus.active);
      expect(midSession.exercises.single.sets[0].done, isTrue);
      expect(midSession.exercises.single.sets[0].actualWeightKg, 35);

      // Adjust the rest window.
      await tester.tap(find.text('+15s'));
      await tester.pump();
      expect(restWholeSeconds(tester), closeTo(105, 1));
      await tester.tap(find.text('-15s'));
      await tester.pump();
      expect(restWholeSeconds(tester), closeTo(90, 1));

      // Skip the rest → set 2 (already the current set — no manual pointer).
      await tester.tap(find.text('Skip rest'));
      await _settle(tester);
      expect(find.text('Set 2 of 2'), findsOneWidget);
      expect(find.text('Last time: 32.5kg × 5'), findsOneWidget);
      expect(find.text('35kg × 5'), findsOneWidget); // goal: 32.5 + 2.5

      // Complete the final set → completed summary.
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await _settle(tester);
      await _dismissUndoSnackbar(tester);
      expect(find.text('Finish'), findsOneWidget);
      expect(find.textContaining('2 of 2 sets'), findsOneWidget);

      // Finish → history written + cursor advanced + session marked completed,
      // then popped back to the launcher (nothing infinite left mid-transition).
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();

      expect(find.text('go'), findsOneWidget); // popped
      expect(workouts.added, hasLength(1));
      expect(workouts.added.single.title, 'Push');
      expect(plans.saved, hasLength(1));
      expect(plans.saved.single.cycleCursor, 1); // advanced 0 → 1
      final finished = sessions.current.firstWhere((s) => s.id != 'prev1');
      expect(finished.status, SessionStatus.completed);
    },
  );

  testWidgets('discard via the trailing trash button erases autosaved progress and pops', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await _start(tester);

    // Log a set, so there is autosaved progress to actually discard.
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
    await tester.tap(find.text('Done'));
    await _settle(tester);
    expect(sessions.current, hasLength(1));

    // Discard is the explicit destructive action, reached via the top bar's
    // trailing trash control — not the close (X) button, which now leaves.
    await tester.tap(find.byTooltip('Discard workout'));
    await _settle(tester);
    expect(find.text('Discard this workout?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('go'), findsOneWidget); // popped
    expect(workouts.added, isEmpty);
    expect(plans.saved, isEmpty);
    expect(sessions.current, isEmpty); // erased, not just left active
  });

  testWidgets('closing (X) with logged progress leaves the session active for Resume', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await _start(tester);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
    await tester.tap(find.text('Done'));
    await _settle(tester);
    expect(sessions.current, hasLength(1));

    // Close (X) is now non-destructive: no confirmation dialog, and the
    // autosaved progress (including the plan's un-advanced cursor) stays put.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('go'), findsOneWidget); // popped
    expect(find.text('Discard this workout?'), findsNothing);
    expect(workouts.added, isEmpty); // never finished
    expect(plans.saved, isEmpty); // cursor not advanced
    final left = sessions.current.single;
    expect(left.status, SessionStatus.active);
    expect(left.exercises.single.sets[0].done, isTrue); // the logged set survived

    // Resuming re-opens the exact same in-progress session rather than a
    // fresh one — set 1 already done, straight onto set 2.
    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
        resume: left,
      ),
    );
    await _start(tester);
    expect(find.text('Set 2 of 2'), findsOneWidget);
    expect(sessions.current, hasLength(1)); // no duplicate session created
  });

  testWidgets('closing (X) with zero logged sets is a silent discard', (tester) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await _start(tester);
    expect(sessions.current, hasLength(1)); // autosaved as soon as it starts

    // Nothing logged yet — closing must not leave a resumable, empty session.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('go'), findsOneWidget); // popped
    expect(find.text('Discard this workout?'), findsNothing); // no confirmation either
    expect(sessions.current, isEmpty);
  });

  testWidgets(
    'closing (X) after skipping every set (nothing completed) is ALSO a silent discard — '
    'a deliberate call, not an accident of the guard: skips carry no logged volume',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      final plan = _plan();

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
        ),
      );
      await _start(tester);

      // Bench has 2 sets — skip both, completing nothing.
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.text('Skip'));
      await _settle(tester);
      await _dismissUndoSnackbar(tester);
      await tester.tap(find.text('Skip rest'));
      await _settle(tester);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.text('Skip'));
      await _settle(tester);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.text('go'), findsOneWidget); // popped
      expect(find.text('Discard this workout?'), findsNothing);
      expect(sessions.current, isEmpty); // discarded, same as never having started one
    },
  );

  testWidgets('Skip shows an Undo snackbar; Undo restores the set to pending and current', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await _start(tester);
    final skippedId = sessions.current.single.exercises.single.sets.first.id;

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pump();
    await tester.tap(find.text('Skip'));
    await tester.pump();
    // Let the snackbar's entrance animation finish (short of its dismiss
    // duration) before inspecting/tapping it.
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Set skipped'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    var afterSkip = sessions.current.single;
    expect(afterSkip.exercises.single.sets.first.skipped, isTrue);
    expect(afterSkip.currentSet?.id, isNot(skippedId)); // advanced to set 2

    await tester.tap(find.text('Undo'));
    await _settle(tester);
    await _dismissUndoSnackbar(tester);

    final afterUndo = sessions.current.single;
    expect(afterUndo.exercises.single.sets.first.pending, isTrue);
    expect(afterUndo.currentSet?.id, skippedId); // current again
    expect(find.text('Set 1 of 2'), findsOneWidget);
  });

  testWidgets('Done shows an Undo snackbar; Undo restores the set to pending (Ziad\'s incident)', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await _start(tester);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Set done'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(sessions.current.single.completedSetCount, 1);

    await tester.tap(find.text('Undo'));
    await _settle(tester);
    await _dismissUndoSnackbar(tester);

    // Reversed, and no longer resting — back on the running screen for set 1.
    expect(sessions.current.single.completedSetCount, 0);
    expect(find.text('Set 1 of 2'), findsOneWidget);
    expect(find.text('Skip rest'), findsNothing);
  });

  testWidgets('Undo reverses the LAST set of a workout, un-completing the session', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await _start(tester);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await _settle(tester);
    await _dismissUndoSnackbar(tester);
    await tester.tap(find.text('Skip rest'));
    await _settle(tester);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pump();
    await tester.tap(find.text('Done')); // the last set — completes the session
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Set done'), findsOneWidget);
    expect(sessions.current.single.isComplete, isTrue);

    await tester.tap(find.text('Undo'));
    await _settle(tester);
    await _dismissUndoSnackbar(tester);

    final reopened = sessions.current.single;
    expect(reopened.isComplete, isFalse);
    expect(reopened.status, SessionStatus.active);
    expect(find.text('Finish'), findsNothing);
    expect(find.text('Set 2 of 2'), findsOneWidget); // back on the set just undone
  });

  testWidgets('the Back control walks back one set at a time and hides once nothing is resolved', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await _start(tester);

    // Nothing resolved yet on set 1 — no Back control.
    expect(find.text('Back'), findsNothing);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await _settle(tester);
    await _dismissUndoSnackbar(tester);
    await tester.tap(find.text('Skip rest'));
    await _settle(tester);

    // Set 1 is done — Back is offered on set 2's screen now.
    expect(find.text('Set 2 of 2'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await _settle(tester);

    // Back to set 1, pending again, and no longer counted as done.
    expect(find.text('Set 1 of 2'), findsOneWidget);
    expect(sessions.current.single.completedSetCount, 0);
    // Nothing resolved any more — Back itself disappears.
    expect(find.text('Back'), findsNothing);
  });

  testWidgets(
    'end-of-workout review: shows an exercise whose only sets were skipped, flags them, and '
    'marking one done there is what Finish actually commits',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      final plan = _plan();

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
        ),
      );
      await _start(tester);

      // Skip both of Bench's sets — nothing completed at all.
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.text('Skip'));
      await _settle(tester);
      await _dismissUndoSnackbar(tester);
      await tester.tap(find.text('Skip rest'));
      await _settle(tester);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.text('Skip'));
      await _settle(tester);
      await _dismissUndoSnackbar(tester);

      // Bench had ZERO completed sets — the old "doneSetCount > 0" filter
      // would have hidden it entirely. It must still show, flagged.
      expect(find.text('Finish'), findsOneWidget);
      expect(find.text('Bench'), findsOneWidget);
      expect(find.text('Set 1'), findsOneWidget);
      expect(find.text('Set 2'), findsOneWidget);
      expect(find.text('Skipped'), findsNWidgets(2));

      // Mark set 1 done with real numbers via the review sheet.
      await tester.tap(find.text('Set 1'));
      await tester.pumpAndSettle();
      expect(find.text('Mark done'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), '5');
      await tester.enterText(find.byType(TextField).at(1), '40');
      await tester.tap(find.text('Mark done'));
      await tester.pumpAndSettle();

      // Reflected immediately in the review list.
      expect(find.text('Skipped'), findsNWidgets(1)); // only set 2 now
      expect(find.text('40kg × 5'), findsOneWidget);
      expect(sessions.current.single.completedSetCount, 1);

      // Finish commits from THIS reviewed state, not the pre-review one.
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();

      expect(workouts.added, hasLength(1));
      final logged = workouts.added.single;
      expect(logged.exercises, hasLength(1)); // Bench — now has 1 done set
      expect(logged.exercises.single.sets, 1);
      expect(logged.exercises.single.reps, 5);
      expect(logged.exercises.single.weightKg, 40);
    },
  );

  testWidgets('end-of-workout review: correcting an already-done set\'s actuals sticks through Finish', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await _start(tester);

    // Complete both sets normally.
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await _settle(tester);
    await _dismissUndoSnackbar(tester);
    await tester.tap(find.text('Skip rest'));
    await _settle(tester);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await _settle(tester);
    await _dismissUndoSnackbar(tester);

    expect(find.text('Finish'), findsOneWidget);
    expect(find.text('Skipped'), findsNothing); // nothing was skipped

    // Correct set 1's logged weight — tap opens "Save", not "Mark done".
    await tester.tap(find.text('Set 1'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Mark done'), findsNothing);

    await tester.enterText(find.byType(TextField).at(1), '999');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('999kg × 5'), findsOneWidget);
    expect(sessions.current.single.completedSetCount, 2); // still both done

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(workouts.added.single.exercises.single.weightKg, 999);
  });

  testWidgets('the rest countdown auto-advances to the next set when it reaches zero', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();
    var fakeNow = DateTime(2026, 1, 1, 8);

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
        now: () => fakeNow,
      ),
    );
    await _start(tester);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(restWholeSeconds(tester), closeTo(90, 1)); // the exercise's own plan rest

    // Let the countdown run out (driven by wall-clock elapsed time, not tick
    // count — advance the clock alongside the pumped duration).
    fakeNow = fakeNow.add(const Duration(seconds: 91));
    await tester.pump(const Duration(seconds: 91));
    expect(find.text('Set 2 of 2'), findsOneWidget);
  });

  testWidgets(
    'the rest countdown resyncs from wall-clock time on app resume, surviving '
    "a backgrounded/suspended timer",
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      final plan = _plan();
      var fakeNow = DateTime(2026, 1, 1, 8);

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
          now: () => fakeNow,
        ),
      );
      await _start(tester);

      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(restWholeSeconds(tester), closeTo(90, 1)); // the exercise's own plan rest

      // Simulate the OS suspending the app's Ticker for 40s while backgrounded
      // — no ticks fire, only wall-clock time passes — then resuming.
      fakeNow = fakeNow.add(const Duration(seconds: 40));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // Resyncs to the real elapsed time on resume instead of staying frozen
      // at 1:30 (what a plain tick-counter would show).
      expect(restWholeSeconds(tester), closeTo(50, 1));

      // And ending naturally still works post-resume.
      fakeNow = fakeNow.add(const Duration(seconds: 50));
      await tester.pump(const Duration(seconds: 50));
      expect(find.text('Set 2 of 2'), findsOneWidget);
    },
  );

  testWidgets(
    'the "time in workout" label starts at 0:00, ticks with wall-clock time, and '
    'freezes once the session completes',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      final plan = _plan();
      var fakeNow = DateTime(2026, 1, 1, 8);

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
          now: () => fakeNow,
        ),
      );
      await _start(tester);

      // Visible immediately, from the moment the session opens.
      expect(elapsedText(tester), '0:00');

      fakeNow = fakeNow.add(const Duration(seconds: 45));
      await tester.pump(const Duration(seconds: 45));
      expect(elapsedText(tester), '0:45');

      // Keeps ticking into a new phase (resting), not just the running one.
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pump();
      fakeNow = fakeNow.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(elapsedText(tester), '0:50');
      await _dismissUndoSnackbar(tester);

      // Finish the day (single-exercise, 2-set plan) → completes and freezes.
      await tester.tap(find.text('Skip rest'));
      await _settle(tester);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await _settle(tester);
      expect(find.text('Finish'), findsOneWidget);
      final frozenAt = elapsedText(tester);

      // Time continuing to pass afterward must not move it.
      fakeNow = fakeNow.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(elapsedText(tester), frozenAt);
    },
  );

  testWidgets('the "time in workout" label resyncs on app resume and formats past an hour', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();
    var fakeNow = DateTime(2026, 1, 1, 8);

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
        now: () => fakeNow,
      ),
    );
    await _start(tester);
    expect(elapsedText(tester), '0:00');

    // Backgrounded for over an hour — no ticks fire, only wall-clock passes.
    fakeNow = fakeNow.add(const Duration(hours: 1, minutes: 4, seconds: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(elapsedText(tester), '1:04:05');
  });

  testWidgets('a resumed session keeps its original startedAt for the elapsed label', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();
    // Started 90s before "now" — as if the app was closed and reopened.
    final startedAt = DateTime(2026, 1, 1, 8);
    var fakeNow = startedAt.add(const Duration(seconds: 90));
    final resumeSession = LiveSession.start(
      plan.days.first,
      id: 'resume1',
      planId: plan.id,
      now: startedAt,
    );

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
        resume: resumeSession,
        now: () => fakeNow,
      ),
    );
    await _start(tester);

    // Reflects time since the ORIGINAL start, not since this screen opened.
    expect(elapsedText(tester), '1:30');
  });

  testWidgets(
    'no history for this exact set → "First time" and the goal is the plan '
    'prescription, not a computed one',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository(); // no prior session saved
      final plan = _plan();

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
        ),
      );
      await _start(tester);

      expect(find.text('Last time: First time'), findsOneWidget);
      // Bench's plan sets carry no targetWeightKg, fixed(5) reps → the
      // prescription-only goal is reps with no weight to suggest.
      expect(find.text('× 5'), findsOneWidget);
    },
  );

  testWidgets(
    'cross-split isolation (§3.2/Phase 5): previous performance never leaks from a '
    'different split, even one sharing this exerciseId (the shape a Duplicate produces)',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      // A completed session belonging to a DIFFERENT split ('p2'), but
      // trained on the SAME exerciseId ('ex1') as this test's plan's Bench
      // — exactly what split management's Duplicate produces. An extreme
      // weight (999kg) so any leak is unmistakable.
      await sessions.saveSession(
        LiveSession(
          id: 'other-split-prev',
          planId: 'p2',
          dayId: 'a',
          dayLabel: 'Push',
          startedAt: DateTime(2026, 1, 1, 9),
          completedAt: DateTime(2026, 1, 1, 10),
          status: SessionStatus.completed,
          exercises: const [
            SessionExercise(
              id: 'ex1',
              exerciseId: 'ex1',
              name: 'Bench',
              restSeconds: 90,
              sets: [
                LoggedSet(id: 's0', target: RepTarget.fixed(5), outcome: SetOutcome.completed, actualReps: 5, actualWeightKg: 999),
              ],
            ),
          ],
        ),
      );
      final plan = _plan(); // planId 'p1' — a different split entirely

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
        ),
      );
      await _start(tester);

      // "First time" for THIS split's Bench — split p2's 999kg must never
      // surface here, even though the exerciseId matches.
      expect(find.text('Last time: First time'), findsOneWidget);
      expect(find.textContaining('999'), findsNothing);
    },
  );

  testWidgets(
    'pausing freezes both the elapsed clock and an active rest countdown; '
    'resuming continues both from where they left off',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      final plan = _plan();
      var fakeNow = DateTime(2026, 1, 1, 8);

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
          now: () => fakeNow,
        ),
      );
      await _start(tester);

      // Run the clock a bit, then start a rest by logging set 1.
      fakeNow = fakeNow.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pump();
      expect(elapsedText(tester), '0:30');
      expect(restWholeSeconds(tester), closeTo(90, 1)); // the exercise's own plan rest, running

      // Pause — both clocks freeze even as real time keeps passing.
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);

      fakeNow = fakeNow.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 20));
      expect(elapsedText(tester), '0:30'); // unchanged
      expect(restWholeSeconds(tester), closeTo(90, 1)); // unchanged

      // Resume — elapsed continues from 0:30 (the 20 paused seconds are
      // excluded, not just skipped-over), and rest resumes at 1:30 instead
      // of restarting from the full 90s.
      await tester.tap(find.text('Resume'));
      await tester.pump();
      expect(find.text('PAUSED'), findsNothing);

      fakeNow = fakeNow.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(elapsedText(tester), '0:35');
      expect(restWholeSeconds(tester), closeTo(85, 1));
    },
  );

  testWidgets('while paused, the phase content is dimmed and not tappable', (tester) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await _start(tester);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('PAUSED'), findsOneWidget);

    // The Done button is still in the tree (dimmed via Opacity, not removed)
    // but IgnorePointer blocks the tap from reaching it.
    await tester.tap(find.text('Done'), warnIfMissed: false);
    await tester.pump();
    expect(sessions.current.single.completedSetCount, 0); // nothing logged

    // Leave/discard stay reachable — Close is outside the dimmed subtree.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget); // popped normally
  });

  testWidgets('a pause survives leave and resume (persisted model state)', (tester) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();
    var fakeNow = DateTime(2026, 1, 1, 8);

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
        now: () => fakeNow,
      ),
    );
    await _start(tester);

    fakeNow = fakeNow.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    // Log a set first — Close on a zero-progress session silently discards
    // it (Phase 1 behavior), which would defeat this test's premise.
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.tap(find.text('Pause'));
    await tester.pump();

    // Leave while paused — the paused session (with its pausedAt) autosaves.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    final left = sessions.current.single;
    expect(left.isPaused, isTrue);

    // Time passes with the app fully closed, then the session is resumed.
    fakeNow = fakeNow.add(const Duration(minutes: 10));
    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
        resume: left,
        now: () => fakeNow,
      ),
    );
    await _start(tester);

    // Still paused, and frozen at exactly the elapsed time from before —
    // the 10 minutes spent away don't leak into it.
    expect(find.text('PAUSED'), findsOneWidget);
    expect(elapsedText(tester), '0:30');
  });

  testWidgets('an empty day settles straight into the completed view', (tester) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();
    final emptyDay = plan.days.last; // 'Pull', no exercises

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: emptyDay,
        plan: plan,
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle(); // no repeating controllers in the completed view

    expect(find.text('WORKOUT COMPLETE'), findsOneWidget); // _Eyebrow uppercases
    expect(find.text('Finish'), findsOneWidget);
  });

  testWidgets('rapid double-tap on Finish only writes history and advances the cursor once', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await _start(tester);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
    await tester.tap(find.text('Done'));
    await _settle(tester);
    await _dismissUndoSnackbar(tester);
    await tester.tap(find.text('Skip rest'));
    await _settle(tester);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
    await tester.tap(find.text('Done'));
    await _settle(tester);
    await _dismissUndoSnackbar(tester);
    expect(find.text('Finish'), findsOneWidget);

    // Finish now pops synchronously (the write is fire-and-forget), so the
    // first tap's pop transition may already be under way by the second —
    // it's fine if the second doesn't even land on the button any more
    // (warnIfMissed: false); what matters is the `_busy` guard still makes
    // it a no-op rather than a duplicate write.
    await tester.tap(find.text('Finish'));
    await tester.tap(find.text('Finish'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(workouts.added, hasLength(1));
    expect(plans.saved, hasLength(1));
    expect(plans.saved.single.cycleCursor, 1);
  });

  testWidgets('Finish pops immediately without waiting for the write to complete (offline-safe)', (
    tester,
  ) async {
    final workouts = _NeverCompletingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await _start(tester);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
    await tester.tap(find.text('Done'));
    await _settle(tester);
    await _dismissUndoSnackbar(tester);
    await tester.tap(find.text('Skip rest'));
    await _settle(tester);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
    await tester.tap(find.text('Done'));
    await _settle(tester);
    await _dismissUndoSnackbar(tester);
    expect(find.text('Finish'), findsOneWidget);

    // `workouts.add` never resolves — if Finish awaited it, this would hang
    // (and pumpAndSettle would time out). It doesn't: the write is fired
    // unawaited, so the pop is not blocked on a server ack that (as if
    // offline) is never coming.
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(find.text('go'), findsOneWidget); // popped
    expect(plans.saved, hasLength(1));
    expect(plans.saved.single.cycleCursor, 1);
  });

  testWidgets('the system back gesture leaves like the close button (non-destructive)', (
    tester,
  ) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await _start(tester);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
    await tester.tap(find.text('Done'));
    await _settle(tester);

    // Simulate the OS back gesture/button rather than tapping the close icon.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Intercepted like the close button: pops straight through, no discard
    // dialog, and the logged progress survives (Resume-able).
    expect(find.text('Discard this workout?'), findsNothing);
    expect(find.text('go'), findsOneWidget);
    expect(sessions.current.single.status, SessionStatus.active);
  });

  testWidgets(
    'force-kill recovery: a session left active by a killed app never contaminates '
    'previous-performance',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      final plan = _plan();

      // Simulates a force-kill mid-session: autosave captured real progress
      // (a done set with actuals) but the process died before Finish/Discard
      // or even dispose() ran — the doc is still "active", not "completed".
      await sessions.saveSession(
        LiveSession(
          id: 'killed-session',
          planId: 'p1',
          dayId: 'a',
          dayLabel: 'Push',
          startedAt: DateTime(2026, 1, 1, 8),
          status: SessionStatus.active,
          exercises: const [
            SessionExercise(
              id: 'ex1',
              exerciseId: 'ex1',
              name: 'Bench',
              restSeconds: 90,
              sets: [
                LoggedSet(
                  id: 'ex1-s0',
                  target: RepTarget.fixed(5),
                  outcome: SetOutcome.completed,
                  actualReps: 5,
                  actualWeightKg: 999, // deliberately extreme — must never surface
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
        ),
      );
      await _start(tester);

      // lastPerformanceFor only trusts *completed* sessions — a killed,
      // still-"active" session's actuals must never surface as "previous
      // performance" or feed the progression delta.
      expect(find.textContaining('999'), findsNothing);
      expect(find.textContaining('Previous'), findsNothing);

      // No blind orphan cleanup any more (that would delete the very session
      // Resume is meant to bring back) — the killed session is left as-is
      // alongside the fresh one this screen started.
      expect(sessions.current.any((s) => s.id == 'killed-session'), isTrue);
      expect(sessions.current.where((s) => s.status == SessionStatus.active), hasLength(2));
    },
  );

  testWidgets(
    'the Goal card suppresses the redundant "Target:" line for a to-failure set '
    'but keeps it for a fixed/range target',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      final plan = WorkoutPlan(
        id: 'p1',
        name: 'Test Split',
        status: WorkoutPlanStatus.active,
        source: WorkoutPlanSource.manual,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        cycleCursor: 0,
        days: const [
          WorkoutDay(
            id: 'a',
            slot: 'A',
            label: 'Push',
            order: 0,
            exercises: [
              PlannedExercise(
                id: 'ex1',
                name: 'Row',
                order: 0,
                muscleGroup: 'Back',
                defaultRestSeconds: 90,
                sets: [
                  PlannedSet(
                    order: 0,
                    repTarget: RepTarget.range(8, 10),
                    restSeconds: 90,
                    type: SetType.working,
                  ),
                  PlannedSet(
                    order: 1,
                    repTarget: RepTarget.toFailure(),
                    restSeconds: 60,
                    type: SetType.working,
                  ),
                ],
              ),
            ],
          ),
          WorkoutDay(id: 'b', slot: 'B', label: 'Pull', order: 1, exercises: []),
        ],
      );

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
        ),
      );
      await _start(tester);

      // Set 1: a range target — the "Target:" line adds real context, keep it.
      expect(find.text('Set 1 of 2'), findsOneWidget);
      expect(find.text('Target: 8–10 reps'), findsOneWidget);

      // Advance to set 2: to-failure — "Target: To failure" would just
      // restate the AMRAP goal label above it, so it's suppressed.
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await _settle(tester);
      await _dismissUndoSnackbar(tester);
      await tester.tap(find.text('Skip rest'));
      await _settle(tester);

      expect(find.text('Set 2 of 2'), findsOneWidget);
      expect(find.textContaining('Target:'), findsNothing);
    },
  );

  testWidgets(
    'typing without tapping Done autosaves a debounced draft; leaving keeps '
    'the session (never discarded as "empty") and resuming restores it',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      final plan = _plan();

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
        ),
      );
      await _start(tester);

      await tester.enterText(find.byType(TextField).at(1), '62.5');
      await tester.pump();

      // Not yet debounced — nothing written to the session/repo just from
      // the keystroke itself.
      expect(sessions.current.single.exercises.first.sets.first.actualWeightKg, isNull);

      // Past the ~450ms debounce window, it autosaves as a draft — NOT done.
      await tester.pump(const Duration(milliseconds: 500));
      final draftSet = sessions.current.single.exercises.first.sets.first;
      expect(draftSet.actualWeightKg, 62.5);
      expect(draftSet.done, isFalse);

      // Closing (X) on a session with zero *completed* sets would normally
      // silently discard it (see the sibling test above) — but a typed
      // draft must never be treated as "empty".
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('go'), findsOneWidget); // popped
      expect(sessions.current, hasLength(1)); // kept, not deleted
      final left = sessions.current.single;
      expect(left.exercises.first.sets.first.actualWeightKg, 62.5);

      // Resuming shows the draft, not a reset back to a fresh goal.
      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
          resume: left,
        ),
      );
      await _start(tester);
      final weightField = tester.widget<TextField>(find.byType(TextField).at(1));
      expect(weightField.controller!.text, '62.5');
    },
  );

  testWidgets(
    "prefill prefers a not-done set's existing draft actuals over the computed goal",
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      await sessions.saveSession(_previousSession());
      final plan = _plan();

      // A typed-but-not-done draft (6 × 65kg) that differs from what
      // computeGoal would suggest from history (57.5kg × 5, per
      // _previousSession) — proves prefill prefers the draft. This draft
      // also keeps the exercise out of warm-up materialization (it's
      // "in progress" the moment any actual is set, done or not).
      final draftSession = LiveSession(
        id: 'draft1',
        planId: 'p1',
        dayId: 'a',
        dayLabel: 'Push',
        startedAt: DateTime(2026, 1, 2, 9),
        status: SessionStatus.active,
        exercises: const [
          SessionExercise(
            id: 'ex1',
            exerciseId: 'ex1',
            name: 'Bench',
            restSeconds: 90,
            sets: [
              LoggedSet(id: 's0', target: RepTarget.fixed(5), actualReps: 6, actualWeightKg: 65),
              LoggedSet(id: 's1', target: RepTarget.fixed(5)),
            ],
          ),
        ],
      );
      await sessions.saveSession(draftSession);

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
          resume: draftSession,
        ),
      );
      await _start(tester);

      final repsField = tester.widget<TextField>(find.byType(TextField).at(0));
      final weightField = tester.widget<TextField>(find.byType(TextField).at(1));
      expect(repsField.controller!.text, '6'); // the draft, not the goal's '5'
      expect(weightField.controller!.text, '65'); // the draft, not the goal's '57.5'
    },
  );

  testWidgets(
    'a fresh session opens on a pre-workout warm-up phase before the first set',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      final plan = _plan();

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
        ),
      );
      await tester.tap(find.text('go'));
      await _settle(tester);

      expect(find.text('PRE-WORKOUT'), findsOneWidget); // _Eyebrow uppercases
      expect(find.text('Loosen up before your first set'), findsOneWidget);
      expect(find.text('Skip warm-up'), findsOneWidget);
      expect(restWholeSeconds(tester), closeTo(300, 1)); // 5:00 default

      // Not yet on the first set — the per-exercise view hasn't shown at all.
      expect(find.text('Set 1 of 2'), findsNothing);
      expect(find.text('Bench'), findsNothing);
    },
  );

  testWidgets(
    'the warm-up countdown ticks with wall-clock time and supports ±15s adjust',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      final plan = _plan();
      var fakeNow = DateTime(2026, 1, 1, 8);

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
          now: () => fakeNow,
        ),
      );
      await tester.tap(find.text('go'));
      await _settle(tester);
      expect(restWholeSeconds(tester), closeTo(300, 1));

      fakeNow = fakeNow.add(const Duration(seconds: 45));
      await tester.pump(const Duration(seconds: 45));
      expect(restWholeSeconds(tester), closeTo(255, 1));

      await tester.tap(find.text('+15s'));
      await tester.pump();
      expect(restWholeSeconds(tester), closeTo(270, 1));
      await tester.tap(find.text('-15s'));
      await tester.pump();
      expect(restWholeSeconds(tester), closeTo(255, 1));
    },
  );

  testWidgets('Skip warm-up advances straight to the first set', (tester) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
      ),
    );
    await tester.tap(find.text('go'));
    await _settle(tester);
    expect(find.text('Skip warm-up'), findsOneWidget);

    await tester.tap(find.text('Skip warm-up'));
    await _settle(tester);

    expect(find.text('Set 1 of 2'), findsOneWidget);
    expect(find.text('Bench'), findsOneWidget);
    expect(find.text('Skip warm-up'), findsNothing);
    expect(find.text('PRE-WORKOUT'), findsNothing);
  });

  testWidgets(
    'the warm-up countdown auto-advances to the first set when it reaches zero',
    (tester) async {
      final workouts = _RecordingWorkoutRepository();
      final plans = _RecordingWorkoutPlanRepository();
      final sessions = InMemoryWorkoutSessionRepository();
      final plan = _plan();
      var fakeNow = DateTime(2026, 1, 1, 8);

      await tester.pumpWidget(
        _wrap(
          workouts: workouts,
          workoutPlans: plans,
          workoutSessions: sessions,
          day: plan.days.first,
          plan: plan,
          now: () => fakeNow,
        ),
      );
      await tester.tap(find.text('go'));
      await _settle(tester);
      expect(find.text('Skip warm-up'), findsOneWidget);

      // Driven by wall-clock elapsed time, not tick count — same convention
      // as the rest countdown's own auto-advance test.
      fakeNow = fakeNow.add(const Duration(seconds: 301));
      await tester.pump(const Duration(seconds: 301));

      expect(find.text('Set 1 of 2'), findsOneWidget);
    },
  );

  testWidgets('a resumed session skips the warm-up phase', (tester) async {
    final workouts = _RecordingWorkoutRepository();
    final plans = _RecordingWorkoutPlanRepository();
    final sessions = InMemoryWorkoutSessionRepository();
    final plan = _plan();
    final resumeSession = LiveSession.start(
      plan.days.first,
      id: 'resume1',
      planId: plan.id,
      now: DateTime(2026, 1, 1, 8),
    );

    await tester.pumpWidget(
      _wrap(
        workouts: workouts,
        workoutPlans: plans,
        workoutSessions: sessions,
        day: plan.days.first,
        plan: plan,
        resume: resumeSession,
      ),
    );
    await tester.tap(find.text('go'));
    await _settle(tester);

    // Even though nothing's logged yet — a *resume* never re-opens on the
    // "before your first set" phase, unlike a genuinely fresh start.
    expect(find.text('PRE-WORKOUT'), findsNothing);
    expect(find.text('Skip warm-up'), findsNothing);
    expect(find.text('Set 1 of 2'), findsOneWidget);
  });
}
