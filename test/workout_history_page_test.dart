import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/domain/exercise.dart';
import 'package:zivo/features/workout/domain/workout.dart';
import 'package:zivo/features/workout/presentation/pages/workout_history_page.dart';

void main() {
  testWidgets('Workout history renders logged sessions from the repository',
      (tester) async {
    final workouts = InMemoryWorkoutRepository();
    addTearDown(workouts.dispose);

    await tester.pumpWidget(
      AppScope(
        expenses: InMemoryExpenseRepository(),
        tasks: InMemoryTaskRepository(),
        schedule: InMemoryScheduleRepository(),
        notes: InMemoryNoteRepository(),
        moments: InMemoryMomentRepository(),
        workouts: workouts,
        child: const MaterialApp(home: WorkoutHistoryPage()),
      ),
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
}
