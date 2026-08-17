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
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/domain/exercise.dart';
import 'package:zivo/features/workout/domain/workout.dart';
import 'package:zivo/features/workout/domain/workout_repository.dart';
import 'package:zivo/features/workout/presentation/pages/workout_capture_page.dart';
import 'package:zivo/features/workout/presentation/pages/workout_history_page.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_profile_repository.dart';

/// A repository whose stream only emits when [emit] is called, so tests can
/// assert on the in-between "waiting" state deterministically.
class _PendingWorkoutRepository implements WorkoutRepository {
  final StreamController<List<Workout>> _controller =
      StreamController<List<Workout>>.broadcast();

  @override
  List<Workout> get current => const [];

  @override
  Stream<List<Workout>> watchAll() => _controller.stream;

  @override
  Future<void> add(Workout workout) async {}

  @override
  Future<void> update(Workout workout) async {}

  @override
  Future<void> remove(String id) async {}

  void emit(List<Workout> workouts) => _controller.add(workouts);

  void dispose() => _controller.close();
}

Widget _wrap({
  required Widget child,
  required WorkoutRepository workoutsOverride,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: workoutsOverride,
    workoutPlans: InMemoryWorkoutPlanRepository(),
    university: InMemoryUniversityRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('Workout history renders logged sessions from the repository', (
    tester,
  ) async {
    final workouts = InMemoryWorkoutRepository();
    addTearDown(workouts.dispose);

    await tester.pumpWidget(
      _wrap(child: const WorkoutHistoryPage(), workoutsOverride: workouts),
    );
    await tester.pump();

    // Seeded session and its computed meta line render.
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('4 exercises · ~50 min'), findsOneWidget);

    // A newly logged workout appears at the top reactively.
    await workouts.add(
      Workout(
        id: 'new',
        title: 'Legs',
        performedAt: DateTime.now(),
        exercises: const [Exercise(name: 'Squat', sets: 5, reps: 5)],
      ),
    );
    await tester.pump();

    expect(find.text('Legs'), findsOneWidget);
  });

  testWidgets('shows a spinner while the stream is waiting, then the list', (
    tester,
  ) async {
    final workouts = _PendingWorkoutRepository();
    addTearDown(workouts.dispose);

    await tester.pumpWidget(
      _wrap(child: const WorkoutHistoryPage(), workoutsOverride: workouts),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No workouts yet.'), findsNothing);

    workouts.emit([
      Workout(
        id: 'w1',
        title: 'Push',
        performedAt: DateTime.now(),
        exercises: const [Exercise(name: 'Bench', sets: 3, reps: 10)],
      ),
    ]);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Push'), findsOneWidget);
  });

  testWidgets('shows the empty state once the stream settles with no data', (
    tester,
  ) async {
    final workouts = _PendingWorkoutRepository();
    addTearDown(workouts.dispose);

    await tester.pumpWidget(
      _wrap(child: const WorkoutHistoryPage(), workoutsOverride: workouts),
    );

    workouts.emit(const []);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No workouts yet.'), findsOneWidget);
  });

  testWidgets('tapping a card opens it for editing, prefilled', (
    tester,
  ) async {
    final workouts = InMemoryWorkoutRepository();
    addTearDown(workouts.dispose);

    await tester.pumpWidget(
      _wrap(child: const WorkoutHistoryPage(), workoutsOverride: workouts),
    );
    await tester.pump();

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();

    expect(find.byType(WorkoutCapturePage), findsOneWidget);
    expect(find.text('Edit workout'), findsOneWidget);
    expect(find.text('Push'), findsOneWidget);
  });

  testWidgets('swiping a card deletes it via the repository', (tester) async {
    final workouts = InMemoryWorkoutRepository();
    addTearDown(workouts.dispose);
    await workouts.add(
      Workout(
        id: 'to-delete',
        title: 'Legs',
        performedAt: DateTime.now(),
        exercises: const [Exercise(name: 'Squat', sets: 5, reps: 5)],
      ),
    );

    await tester.pumpWidget(
      _wrap(child: const WorkoutHistoryPage(), workoutsOverride: workouts),
    );
    await tester.pump();

    expect(workouts.current.any((w) => w.id == 'to-delete'), isTrue);

    await tester.drag(find.text('Legs'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(workouts.current.any((w) => w.id == 'to-delete'), isFalse);
  });
}
