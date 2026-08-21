import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/capture/presentation/widgets/capture_widgets.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_repository.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/pages/split_management_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A real (if minimal) multi-split repository — list + active pointer,
/// reactive — so the page's switch/duplicate/delete flows can be exercised
/// end to end rather than just asserting which method got called.
class _FakeSplitsRepository implements WorkoutPlanRepository {
  _FakeSplitsRepository(List<WorkoutPlan> initialSplits)
    : _splits = List.of(initialSplits),
      _activeId = initialSplits.isEmpty ? null : initialSplits.first.id;

  final List<WorkoutPlan> _splits;
  String? _activeId;
  final StreamController<WorkoutPlan?> _activeController = StreamController<WorkoutPlan?>.broadcast();
  final StreamController<List<WorkoutPlan>> _splitsController = StreamController<List<WorkoutPlan>>.broadcast();

  WorkoutPlan? _resolveActive() {
    for (final s in _splits) {
      if (s.id == _activeId) return s;
    }
    return null;
  }

  @override
  WorkoutPlan? get activePlan => _resolveActive();

  @override
  Stream<WorkoutPlan?> watchActivePlan() async* {
    yield _resolveActive();
    yield* _activeController.stream;
  }

  @override
  Future<void> savePlan(WorkoutPlan plan) async {
    _upsert(plan);
    _activeId = plan.id;
    _emit();
  }

  @override
  Future<void> deletePlan(String id) => deleteSplit(id);

  @override
  List<WorkoutPlan> get splits => List.unmodifiable(_splits);

  @override
  Stream<List<WorkoutPlan>> watchSplits() async* {
    yield List.unmodifiable(_splits);
    yield* _splitsController.stream;
  }

  @override
  String? get activeSplitId => _activeId;

  @override
  Future<void> setActiveSplit(String id) async {
    _activeId = id;
    _emit();
  }

  @override
  Future<void> saveSplit(WorkoutPlan plan) async {
    _upsert(plan);
    _activeId ??= plan.id;
    _emit();
  }

  @override
  Future<void> deleteSplit(String id) async {
    _splits.removeWhere((s) => s.id == id);
    if (_activeId == id) _activeId = _splits.isEmpty ? null : _splits.first.id;
    _emit();
  }

  void _upsert(WorkoutPlan plan) {
    final i = _splits.indexWhere((s) => s.id == plan.id);
    if (i >= 0) {
      _splits[i] = plan;
    } else {
      _splits.add(plan);
    }
  }

  void _emit() {
    _activeController.add(_resolveActive());
    _splitsController.add(List.unmodifiable(_splits));
  }

  void dispose() {
    _activeController.close();
    _splitsController.close();
  }
}

WorkoutPlan _split(String id, String name, {DateTime? createdAt}) => WorkoutPlan(
  id: id,
  name: name,
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.manual,
  createdAt: createdAt ?? DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  cycleCursor: 0,
  days: [
    WorkoutDay(
      id: '$id-d1',
      slot: 'A',
      label: 'Push',
      order: 0,
      exercises: [
        PlannedExercise(
          id: '$id-e1',
          name: 'Bench Press',
          order: 0,
          defaultRestSeconds: 90,
          sets: const [PlannedSet(order: 0, repTarget: RepTarget.range(8, 10), restSeconds: 90, type: SetType.working)],
        ),
      ],
    ),
  ],
);

Widget _wrap({required WorkoutPlanRepository plans, InMemoryWorkoutSessionRepository? sessions}) {
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
    workoutSessions: sessions ?? InMemoryWorkoutSessionRepository(),
    university: InMemoryUniversityRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: const MaterialApp(home: SplitManagementPage()),
  );
}

/// Opens split [name]'s action sheet by tapping its tile.
Future<void> _openActions(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists every split and marks the active one', (tester) async {
    final plans = _FakeSplitsRepository([_split('a', 'Push Pull Legs'), _split('b', 'Upper Lower')]);
    addTearDown(plans.dispose);
    await tester.pumpWidget(_wrap(plans: plans));
    await tester.pump();

    expect(find.text('Push Pull Legs'), findsOneWidget);
    expect(find.text('Upper Lower'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget); // only on the first (seeded active)
  });

  testWidgets('Set as active switches the active split without touching the others', (tester) async {
    final plans = _FakeSplitsRepository([_split('a', 'Push Pull Legs'), _split('b', 'Upper Lower')]);
    addTearDown(plans.dispose);
    await tester.pumpWidget(_wrap(plans: plans));
    await tester.pump();
    expect(plans.activeSplitId, 'a');

    await _openActions(tester, 'Upper Lower');
    expect(find.text('Set as active'), findsOneWidget);
    await tester.tap(find.text('Set as active'));
    await tester.pumpAndSettle();

    expect(plans.activeSplitId, 'b');
    expect(plans.splits, hasLength(2)); // switching never adds/removes a split
  });

  testWidgets('Edit reuses the plan editor in split mode and does not steal active', (tester) async {
    final plans = _FakeSplitsRepository([_split('a', 'Push Pull Legs'), _split('b', 'Upper Lower')]);
    addTearDown(plans.dispose);
    await tester.pumpWidget(_wrap(plans: plans));
    await tester.pump();

    await _openActions(tester, 'Upper Lower'); // the non-active split
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit split'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('plan-name-field')), 'Upper Lower v2');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(PillButton, 'Save plan'));
    await tester.tap(find.widgetWithText(PillButton, 'Save plan'));
    await tester.pumpAndSettle();

    expect(find.text('Upper Lower v2'), findsOneWidget);
    expect(find.text('Upper Lower'), findsNothing);
    expect(plans.activeSplitId, 'a'); // still Push Pull Legs — editing 'b' didn't activate it
  });

  testWidgets('Duplicate creates a new, inactive split with a distinct id', (tester) async {
    final plans = _FakeSplitsRepository([_split('a', 'Push Pull Legs')]);
    addTearDown(plans.dispose);
    await tester.pumpWidget(_wrap(plans: plans));
    await tester.pump();

    await _openActions(tester, 'Push Pull Legs');
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(plans.splits, hasLength(2));
    expect(find.text('Push Pull Legs copy'), findsOneWidget);
    // The original stays active; the duplicate is a fresh, non-active id.
    expect(plans.activeSplitId, 'a');
    final duplicate = plans.splits.firstWhere((s) => s.name == 'Push Pull Legs copy');
    expect(duplicate.id, isNot('a'));
  });

  testWidgets('Delete asks for confirmation, then removes the split', (tester) async {
    final plans = _FakeSplitsRepository([_split('a', 'Push Pull Legs'), _split('b', 'Upper Lower')]);
    addTearDown(plans.dispose);
    await tester.pumpWidget(_wrap(plans: plans));
    await tester.pump();

    await _openActions(tester, 'Upper Lower');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete "Upper Lower"?'), findsOneWidget);

    // Cancel first — nothing removed.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(plans.splits, hasLength(2));

    await _openActions(tester, 'Upper Lower');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(plans.splits, hasLength(1));
    expect(find.text('Upper Lower'), findsNothing);
  });

  testWidgets('creating a split via the FAB adds it to the list without activating it', (tester) async {
    final plans = _FakeSplitsRepository([_split('a', 'Push Pull Legs')]);
    addTearDown(plans.dispose);
    await tester.pumpWidget(_wrap(plans: plans));
    await tester.pump();

    await tester.tap(find.byTooltip('New split'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Manually'));
    await tester.pumpAndSettle();
    expect(find.text('New split'), findsOneWidget); // the editor's own title

    await tester.enterText(find.byKey(const Key('plan-name-field')), 'Arnold Split');
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

    expect(find.text('Arnold Split'), findsOneWidget);
    expect(plans.activeSplitId, 'a'); // the pre-existing active split is untouched
  });

  testWidgets('the FAB opens a sheet with exactly Create Manually and Import with AI (no AppBar PDF icon)', (tester) async {
    final plans = _FakeSplitsRepository([_split('a', 'Push Pull Legs')]);
    addTearDown(plans.dispose);
    await tester.pumpWidget(_wrap(plans: plans));
    await tester.pump();

    expect(find.byTooltip('Import PDF'), findsNothing);

    await tester.tap(find.byTooltip('New split'));
    await tester.pumpAndSettle();

    expect(find.text('Create Manually'), findsOneWidget);
    expect(find.text('Import with AI'), findsOneWidget);
  });

  testWidgets('Import with AI from the FAB sheet opens the PDF import flow', (tester) async {
    final plans = _FakeSplitsRepository([_split('a', 'Push Pull Legs')]);
    addTearDown(plans.dispose);
    await tester.pumpWidget(_wrap(plans: plans));
    await tester.pump();

    await tester.tap(find.byTooltip('New split'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import with AI'));
    await tester.pumpAndSettle();

    expect(find.text('Import PDF'), findsOneWidget);
  });

  testWidgets('switching the active split A → B → A never touches either split\'s sessions', (tester) async {
    final plans = _FakeSplitsRepository([_split('a', 'Push Pull Legs'), _split('b', 'Upper Lower')]);
    addTearDown(plans.dispose);
    final sessionA = LiveSession(
      id: 'sa',
      planId: 'a',
      dayId: 'a-d1',
      dayLabel: 'Push',
      startedAt: DateTime(2026, 2, 1),
      completedAt: DateTime(2026, 2, 1, 1),
      status: SessionStatus.completed,
      exercises: const [
        SessionExercise(id: 'a-e1', exerciseId: 'a-e1', name: 'Bench Press', restSeconds: 90, sets: []),
      ],
    );
    final sessionB = LiveSession(
      id: 'sb',
      planId: 'b',
      dayId: 'b-d1',
      dayLabel: 'Push',
      startedAt: DateTime(2026, 2, 2),
      completedAt: DateTime(2026, 2, 2, 1),
      status: SessionStatus.completed,
      exercises: const [
        SessionExercise(id: 'b-e1', exerciseId: 'b-e1', name: 'Bench Press', restSeconds: 90, sets: []),
      ],
    );
    final sessions = InMemoryWorkoutSessionRepository(seed: [sessionA, sessionB]);
    await tester.pumpWidget(_wrap(plans: plans, sessions: sessions));
    await tester.pump();

    await _openActions(tester, 'Upper Lower');
    await tester.tap(find.text('Set as active'));
    await tester.pumpAndSettle();
    expect(plans.activeSplitId, 'b');

    await _openActions(tester, 'Push Pull Legs');
    await tester.tap(find.text('Set as active'));
    await tester.pumpAndSettle();
    expect(plans.activeSplitId, 'a');

    // Both sessions, untouched, still keyed to their own split.
    expect(sessions.current, hasLength(2));
    expect(sessions.current.map((s) => s.planId).toSet(), {'a', 'b'});
  });
}
