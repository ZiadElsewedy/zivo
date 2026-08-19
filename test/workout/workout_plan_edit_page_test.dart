import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/capture/presentation/widgets/capture_widgets.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_repository.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/pages/workout_plan_edit_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

class _RecordingWorkoutPlanRepository implements WorkoutPlanRepository {
  final List<WorkoutPlan> saved = [];
  final List<String> deleted = [];

  /// Tracked separately from [saved]/[deleted] so a test can assert exactly
  /// which method [WorkoutPlanEditPage.asSplit] routed through — a real
  /// `saveSplit` doesn't always activate (unlike `savePlan`), which is the
  /// whole reason `asSplit` exists.
  final List<WorkoutPlan> savedAsSplit = [];
  final List<String> deletedAsSplit = [];
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
  Future<void> deletePlan(String id) async {
    deleted.add(id);
    _active = null;
  }

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
  Future<void> saveSplit(WorkoutPlan plan) async {
    savedAsSplit.add(plan);
    _active ??= plan;
  }

  @override
  Future<void> deleteSplit(String id) async {
    deletedAsSplit.add(id);
    if (_active?.id == id) _active = null;
  }
}

WorkoutPlan _existingPlan() => WorkoutPlan(
  id: 'existing',
  name: 'PPL',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  cycleCursor: 1,
  days: const [
    WorkoutDay(
      id: 'd1',
      slot: 'A',
      label: 'Push',
      order: 0,
      exercises: [
        PlannedExercise(
          id: 'e1',
          name: 'Bench Press',
          order: 0,
          defaultRestSeconds: 120,
          sets: [
            PlannedSet(order: 0, repTarget: RepTarget.range(6, 8), restSeconds: 120, type: SetType.working),
          ],
        ),
      ],
    ),
    WorkoutDay(id: 'd2', slot: 'B', label: 'Pull', order: 1, exercises: []),
  ],
);

Widget _wrap({required Widget child, required WorkoutPlanRepository plans}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: plans,
    workoutSessions: InMemoryWorkoutSessionRepository(),
    university: InMemoryUniversityRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

/// Taps a day tile's header (its "Day {slot} · {label}" text, already
/// unique per day) to expand it, and settles the spring. Days start
/// collapsed — most tests that interact with a specific day's exercises
/// need this first.
Future<void> _expandDay(WidgetTester tester, String dayHeaderText) async {
  await tester.tap(find.text(dayHeaderText));
  await tester.pumpAndSettle();
}

/// Simulates the long-press-drag gesture `ReorderableDelayedDragStartListener`
/// listens for: press and hold past the long-press threshold (so it wins the
/// gesture arena over a plain tap), then drag by [offset], then release.
/// Used to exercise real drag-to-reorder rather than calling the reorder
/// callback directly, so this also proves the gesture itself is wired up
/// (long-press starts a drag; a quick tap elsewhere stays a tap).
Future<void> _longPressDragBy(
  WidgetTester tester,
  Finder finder,
  Offset offset,
) async {
  final gesture = await tester.startGesture(tester.getCenter(finder));
  await tester.pump(const Duration(milliseconds: 600)); // past the long-press threshold
  await gesture.moveBy(offset);
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create flow: name + day + exercise (compact set spec) → savePlan', (tester) async {
    final plans = _RecordingWorkoutPlanRepository();

    await tester.pumpWidget(_wrap(child: const WorkoutPlanEditPage(), plans: plans));
    await tester.pump();

    // Name the plan.
    await tester.enterText(find.byKey(const Key('plan-name-field')), 'My Split');
    await tester.pump();

    // Add a day: slot pre-filled "A", enter the label.
    await tester.tap(find.text('Add day'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('day-label-field')), 'Push');
    await tester.pump(); // rebuild so the submit button enables
    await tester.ensureVisible(find.widgetWithText(PillButton, 'Add day'));
    await tester.tap(find.widgetWithText(PillButton, 'Add day')); // sheet submit
    await tester.pumpAndSettle();
    expect(find.text('Day A · Push'), findsOneWidget);

    // Add an exercise with the default set spec (3 sets, range 8–12, rest 90).
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('exercise-name-field')), 'Bench Press');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(PillButton, 'Add exercise'));
    await tester.tap(find.widgetWithText(PillButton, 'Add exercise')); // sheet submit
    await tester.pumpAndSettle();
    expect(find.text('Bench Press'), findsOneWidget);

    // Save.
    await tester.ensureVisible(find.widgetWithText(PillButton, 'Save plan'));
    await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
    await tester.pumpAndSettle();

    expect(plans.saved, hasLength(1));
    final plan = plans.saved.single;
    expect(plan.name, 'My Split');
    expect(plan.days, hasLength(1));
    final day = plan.days.single;
    expect(day.slot, 'A');
    expect(day.label, 'Push');
    expect(day.order, 0);
    expect(day.exercises, hasLength(1));
    final exercise = day.exercises.single;
    expect(exercise.name, 'Bench Press');
    // The compact spec expanded into 3 identical working sets.
    expect(exercise.sets, hasLength(3));
    expect(exercise.sets.every((s) => s.repTarget == const RepTarget.range(8, 12)), isTrue);
    expect(exercise.sets.every((s) => s.type == SetType.working), isTrue);
    expect(exercise.sets.map((s) => s.order), [0, 1, 2]);
  });

  testWidgets('to-failure rep mode generates to-failure sets', (tester) async {
    final plans = _RecordingWorkoutPlanRepository();

    await tester.pumpWidget(_wrap(child: const WorkoutPlanEditPage(), plans: plans));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('plan-name-field')), 'S');

    await tester.tap(find.text('Add day'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('day-label-field')), 'Arms');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(PillButton, 'Add day'));
    await tester.tap(find.widgetWithText(PillButton, 'Add day'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('exercise-name-field')), 'Curl');
    await tester.pump();
    await tester.tap(find.text('To failure')); // switch rep mode
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(PillButton, 'Add exercise'));
    await tester.tap(find.widgetWithText(PillButton, 'Add exercise'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
    await tester.pumpAndSettle();

    final exercise = plans.saved.single.days.single.exercises.single;
    expect(exercise.sets.first.repTarget, const RepTarget.toFailure());
  });

  testWidgets('edit flow: existing plan pre-fills and save preserves id + cursor', (tester) async {
    final plans = _RecordingWorkoutPlanRepository();

    await tester.pumpWidget(
      _wrap(child: WorkoutPlanEditPage(initialPlan: _existingPlan()), plans: plans),
    );
    await tester.pump();

    // Existing content is shown — days start collapsed, so Bench Press
    // isn't visible until its day is expanded (see the day-tiles test
    // below for the collapsed/expanded behavior itself).
    expect(find.text('Day A · Push'), findsOneWidget);
    expect(find.text('Bench Press'), findsNothing);
    await _expandDay(tester, 'Day A · Push');
    expect(find.text('Bench Press'), findsOneWidget);

    await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
    await tester.pumpAndSettle();

    final plan = plans.saved.single;
    expect(plan.id, 'existing'); // reused
    expect(plan.cycleCursor, 1); // rotation preserved
    expect(plan.days, hasLength(2));
    expect(plan.days.first.exercises.single.name, 'Bench Press');
  });

  testWidgets(
    'tap-to-edit: tapping an exercise opens it pre-filled and saving replaces it in place',
    (tester) async {
      final plans = _RecordingWorkoutPlanRepository();

      await tester.pumpWidget(
        _wrap(child: WorkoutPlanEditPage(initialPlan: _existingPlan()), plans: plans),
      );
      await tester.pump();
      await _expandDay(tester, 'Day A · Push');

      await tester.tap(find.text('Bench Press'));
      await tester.pumpAndSettle();

      // Pre-filled from the existing exercise, not blank — and the sheet
      // knows it's editing (title + button label switch).
      expect(find.text('Edit exercise'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(const Key('exercise-name-field'))).controller!.text,
        'Bench Press',
      );
      // The rest wheel opens centered on the exercise's actual rest (120s →
      // item 24 of the 5s-step wheel), not some other/default value.
      expect(
        tester
            .widget<CupertinoPicker>(find.byKey(const Key('rest-picker')))
            .scrollController!
            .initialItem,
        24,
      );

      await tester.enterText(
        find.byKey(const Key('exercise-name-field')),
        'Incline Bench Press',
      );
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(PillButton, 'Save changes'));
      await tester.tap(find.widgetWithText(PillButton, 'Save changes'));
      await tester.pumpAndSettle();

      // Replaced in place — not appended as a second exercise.
      expect(find.text('Incline Bench Press'), findsOneWidget);
      expect(find.text('Bench Press'), findsNothing);

      await tester.ensureVisible(find.widgetWithText(PillButton, 'Save plan'));
      await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
      await tester.pumpAndSettle();

      final day = plans.saved.single.days.first;
      expect(day.exercises, hasLength(1));
      final exercise = day.exercises.single;
      expect(exercise.id, 'e1'); // identity preserved, not regenerated
      expect(exercise.name, 'Incline Bench Press');
    },
  );

  testWidgets(
    'the rest wheel picker updates the saved rest and fires a selection-click haptic per tick',
    (tester) async {
      final plans = _RecordingWorkoutPlanRepository();
      final hapticCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'HapticFeedback.vibrate') hapticCalls.add(call.arguments as String);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(_wrap(child: const WorkoutPlanEditPage(), plans: plans));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('plan-name-field')), 'S');

      await tester.tap(find.text('Add day'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('day-label-field')), 'Push');
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(PillButton, 'Add day'));
      await tester.tap(find.widgetWithText(PillButton, 'Add day'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add exercise'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('exercise-name-field')), 'Bench Press');
      await tester.pump();

      // Default rest is 90s. Drag the wheel up by 3 items (15s each tick's
      // worth of 5s steps) to land on 90 + 3*5 = 105s ("1:45").
      await tester.drag(find.byKey(const Key('rest-picker')), const Offset(0, -34 * 3));
      await tester.pumpAndSettle();

      expect(hapticCalls, isNotEmpty);
      expect(hapticCalls, everyElement('HapticFeedbackType.selectionClick'));

      await tester.ensureVisible(find.widgetWithText(PillButton, 'Add exercise'));
      await tester.tap(find.widgetWithText(PillButton, 'Add exercise'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(PillButton, 'Save plan'));
      await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
      await tester.pumpAndSettle();

      final exercise = plans.saved.single.days.single.exercises.single;
      expect(exercise.sets.first.restSeconds, 105);
      expect(exercise.defaultRestSeconds, 105);
    },
  );

  testWidgets(
    'Default rest bulk-sets every exercise across every day, and a later '
    'per-exercise edit sticks without a re-apply clobbering it',
    (tester) async {
      final plans = _RecordingWorkoutPlanRepository();
      final plan = WorkoutPlan(
        id: 'bulk',
        name: 'Bulk',
        status: WorkoutPlanStatus.active,
        source: WorkoutPlanSource.manual,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        cycleCursor: 0,
        days: const [
          WorkoutDay(
            id: 'd1',
            slot: 'A',
            label: 'Push',
            order: 0,
            exercises: [
              PlannedExercise(
                id: 'e1',
                name: 'Bench Press',
                order: 0,
                defaultRestSeconds: 90,
                sets: [
                  PlannedSet(
                    order: 0,
                    repTarget: RepTarget.range(6, 8),
                    restSeconds: 90,
                    type: SetType.working,
                  ),
                ],
              ),
              PlannedExercise(
                id: 'e2',
                name: 'Overhead Press',
                order: 1,
                defaultRestSeconds: 60,
                sets: [
                  PlannedSet(
                    order: 0,
                    repTarget: RepTarget.range(8, 10),
                    restSeconds: 60,
                    type: SetType.working,
                  ),
                ],
              ),
            ],
          ),
          WorkoutDay(
            id: 'd2',
            slot: 'B',
            label: 'Pull',
            order: 1,
            exercises: [
              PlannedExercise(
                id: 'e3',
                name: 'Lat Pulldown',
                order: 0,
                defaultRestSeconds: 75,
                sets: [
                  PlannedSet(
                    order: 0,
                    repTarget: RepTarget.range(8, 12),
                    restSeconds: 75,
                    type: SetType.working,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(_wrap(child: WorkoutPlanEditPage(initialPlan: plan), plans: plans));
      await tester.pump();
      // Both days expanded — the bulk-rest check below reads exercise rows
      // across both, and "Overhead Press" (in Push) needs to stay
      // tappable throughout.
      await _expandDay(tester, 'Day A · Push');
      await _expandDay(tester, 'Day B · Pull');

      // Open the bulk sheet — seeded from the first exercise's rest (90s,
      // item 18) — and dial it up to 3:00 (item 36): +18 items.
      await tester.tap(find.textContaining('Default rest'));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const Key('rest-picker')), const Offset(0, -34 * 18));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(PillButton, 'Set all'));
      await tester.tap(find.widgetWithText(PillButton, 'Set all'));
      await tester.pumpAndSettle();

      // Every exercise reads the bulk value in the list before any save —
      // the mutation is visible immediately, not just after a round-trip.
      expect(find.textContaining('rest 3:00'), findsNWidgets(3));

      // Now override just "Overhead Press" down to 2:30 (item 30, -6 items
      // from the 3:00 it's currently seeded at) via the existing tap-to-edit
      // flow — without touching Default rest again — then save once.
      await tester.tap(find.text('Overhead Press'));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const Key('rest-picker')), const Offset(0, 34 * 6));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(PillButton, 'Save changes'));
      await tester.tap(find.widgetWithText(PillButton, 'Save changes'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.widgetWithText(PillButton, 'Save plan'));
      await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
      await tester.pumpAndSettle();

      final finalPlan = plans.saved.last;
      final overhead = finalPlan.days.first.exercises.firstWhere((e) => e.id == 'e2');
      expect(overhead.defaultRestSeconds, 150); // overridden
      final bench = finalPlan.days.first.exercises.firstWhere((e) => e.id == 'e1');
      final pulldown = finalPlan.days.last.exercises.single;
      expect(bench.defaultRestSeconds, 180); // untouched, still the bulk value
      expect(pulldown.defaultRestSeconds, 180); // untouched, still the bulk value
    },
  );

  testWidgets(
    'day tiles start collapsed showing the exercise count; tapping the header toggles the '
    'exercise list',
    (tester) async {
      final plans = _RecordingWorkoutPlanRepository();
      await tester.pumpWidget(
        _wrap(child: WorkoutPlanEditPage(initialPlan: _existingPlan()), plans: plans),
      );
      await tester.pump();

      // Collapsed: header + count visible, exercises hidden.
      expect(find.text('Day A · Push'), findsOneWidget);
      expect(find.text('1 exercise'), findsOneWidget);
      expect(find.text('Day B · Pull'), findsOneWidget);
      expect(find.text('0 exercises'), findsOneWidget);
      expect(find.text('Bench Press'), findsNothing);

      // Tapping the header expands it.
      await _expandDay(tester, 'Day A · Push');
      expect(find.text('Bench Press'), findsOneWidget);
      // Pull stays collapsed — its own "Add exercise" isn't shown yet, only
      // Push's (proves this isn't a forced single-open accordion — see the
      // dedicated test below for the fuller case).
      expect(find.text('Add exercise'), findsOneWidget);

      // Tapping it again collapses it back.
      await tester.tap(find.text('Day A · Push'));
      await tester.pumpAndSettle();
      expect(find.text('Bench Press'), findsNothing);
    },
  );

  testWidgets('multiple days can be expanded at once — not a forced accordion', (tester) async {
    final plans = _RecordingWorkoutPlanRepository();
    await tester.pumpWidget(
      _wrap(child: WorkoutPlanEditPage(initialPlan: _existingPlan()), plans: plans),
    );
    await tester.pump();

    await _expandDay(tester, 'Day A · Push');
    await _expandDay(tester, 'Day B · Pull');

    // Push's exercise is still visible after independently expanding Pull —
    // expanding one never collapsed the other.
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Add exercise'), findsNWidgets(2)); // both days' own button
  });

  testWidgets(
    'expanding a day survives an unrelated edit elsewhere on the page (adding a new day)',
    (tester) async {
      final plans = _RecordingWorkoutPlanRepository();
      await tester.pumpWidget(
        _wrap(child: WorkoutPlanEditPage(initialPlan: _existingPlan()), plans: plans),
      );
      await tester.pump();
      await _expandDay(tester, 'Day A · Push');
      expect(find.text('Bench Press'), findsOneWidget);

      // An unrelated change elsewhere on the page (adding a new day)
      // rebuilds the whole day list — Push must stay expanded, not
      // silently re-collapse just because its parent rebuilt.
      await tester.tap(find.text('Add day'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('day-label-field')), 'Legs');
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(PillButton, 'Add day'));
      await tester.tap(find.widgetWithText(PillButton, 'Add day'));
      await tester.pumpAndSettle();

      expect(find.text('Bench Press'), findsOneWidget); // Push still expanded
      // The freshly-added day exists and auto-expands (see
      // _DayCard.initiallyExpanded) — its own "Add exercise" button is
      // visible immediately, no extra tap needed to start adding to it.
      expect(find.text('Day C · Legs'), findsOneWidget);
      expect(find.text('Add exercise'), findsNWidgets(2)); // Push's (expanded) + Legs' (auto-expanded)
    },
  );

  testWidgets(
    'long-press-drag reorders days, Save persists the new order, and the rotation cursor '
    'follows the day it pointed at (not a fixed index)',
    (tester) async {
      final plans = _RecordingWorkoutPlanRepository();
      // _existingPlan(): Push (order 0), Pull (order 1), cycleCursor 1 →
      // points at Pull.
      await tester.pumpWidget(
        _wrap(child: WorkoutPlanEditPage(initialPlan: _existingPlan()), plans: plans),
      );
      await tester.pump();

      expect(find.text('Day A · Push'), findsOneWidget);
      expect(find.text('Day B · Pull'), findsOneWidget);

      // Long-press Push and drag it down past Pull.
      await _longPressDragBy(tester, find.text('Day A · Push'), const Offset(0, 200));

      await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
      await tester.pumpAndSettle();

      final saved = plans.saved.single;
      expect(saved.days.map((d) => d.label), ['Pull', 'Push']); // swapped
      // The cursor followed Pull (what it pointed at before the reorder) to
      // its NEW index (0) — not left at the fixed index 1, which would now
      // silently point at Push instead: exactly the bug being guarded
      // against (Home/the Workout page both read `nextDay` from this).
      expect(saved.cycleCursor, 0);
    },
  );

  testWidgets(
    'long-press-drag reorders exercises within an expanded day, and Save persists it',
    (tester) async {
      final plans = _RecordingWorkoutPlanRepository();
      final plan = WorkoutPlan(
        id: 'reorder-ex',
        name: 'Reorder',
        status: WorkoutPlanStatus.active,
        source: WorkoutPlanSource.manual,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        cycleCursor: 0,
        days: const [
          WorkoutDay(
            id: 'd1',
            slot: 'A',
            label: 'Push',
            order: 0,
            exercises: [
              PlannedExercise(
                id: 'e1',
                name: 'Bench Press',
                order: 0,
                defaultRestSeconds: 90,
                sets: [
                  PlannedSet(
                    order: 0,
                    repTarget: RepTarget.range(6, 8),
                    restSeconds: 90,
                    type: SetType.working,
                  ),
                ],
              ),
              PlannedExercise(
                id: 'e2',
                name: 'Overhead Press',
                order: 1,
                defaultRestSeconds: 60,
                sets: [
                  PlannedSet(
                    order: 0,
                    repTarget: RepTarget.range(8, 10),
                    restSeconds: 60,
                    type: SetType.working,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(_wrap(child: WorkoutPlanEditPage(initialPlan: plan), plans: plans));
      await tester.pump();
      await _expandDay(tester, 'Day A · Push');
      expect(find.text('Bench Press'), findsOneWidget);
      expect(find.text('Overhead Press'), findsOneWidget);

      // Drag Bench Press down past Overhead Press.
      await _longPressDragBy(tester, find.text('Bench Press'), const Offset(0, 45));

      await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
      await tester.pumpAndSettle();

      final exercises = plans.saved.single.days.single.exercises;
      expect(exercises.map((e) => e.name), ['Overhead Press', 'Bench Press']);
    },
  );

  testWidgets("a day's expanded state survives being reordered", (tester) async {
    final plans = _RecordingWorkoutPlanRepository();
    await tester.pumpWidget(
      _wrap(child: WorkoutPlanEditPage(initialPlan: _existingPlan()), plans: plans),
    );
    await tester.pump();
    await _expandDay(tester, 'Day A · Push');
    expect(find.text('Bench Press'), findsOneWidget);

    await _longPressDragBy(tester, find.text('Day A · Push'), const Offset(0, 200));

    // Push (still keyed on its id, just moved) stays expanded even after
    // changing position — expand state isn't reset by a reorder.
    expect(find.text('Bench Press'), findsOneWidget);
  });

  testWidgets('delete flow: confirm removes the plan', (tester) async {
    final plans = _RecordingWorkoutPlanRepository();

    await tester.pumpWidget(
      _wrap(child: WorkoutPlanEditPage(initialPlan: _existingPlan()), plans: plans),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('workout-plan-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this plan?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(plans.deleted, ['existing']);
  });

  testWidgets('asSplit: true routes save through saveSplit (never savePlan, which always activates)', (
    tester,
  ) async {
    final plans = _RecordingWorkoutPlanRepository();
    await tester.pumpWidget(
      _wrap(child: const WorkoutPlanEditPage(asSplit: true), plans: plans),
    );
    await tester.pump();
    expect(find.text('New split'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('plan-name-field')), 'Second Split');
    await tester.pump();
    await tester.tap(find.text('Add day'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('day-label-field')), 'Push');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(PillButton, 'Add day'));
    await tester.tap(find.widgetWithText(PillButton, 'Add day'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(PillButton, 'Save plan'));
    await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
    await tester.pumpAndSettle();

    expect(plans.savedAsSplit.map((p) => p.name), ['Second Split']);
    expect(plans.saved, isEmpty); // never touched the always-activates path
  });

  testWidgets('asSplit: true routes delete through deleteSplit (never deletePlan)', (tester) async {
    final plans = _RecordingWorkoutPlanRepository();
    await tester.pumpWidget(
      _wrap(child: WorkoutPlanEditPage(initialPlan: _existingPlan(), asSplit: true), plans: plans),
    );
    await tester.pump();
    expect(find.text('Edit split'), findsOneWidget);

    await tester.tap(find.byKey(const Key('workout-plan-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this split?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(plans.deletedAsSplit, ['existing']);
    expect(plans.deleted, isEmpty);
  });
}
