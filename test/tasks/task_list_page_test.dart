import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/firestore_task_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/tasks/domain/task.dart';
import 'package:zivo/features/tasks/presentation/pages/task_capture_page.dart';
import 'package:zivo/features/tasks/presentation/pages/task_list_page.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

Widget _wrap({
  required Widget child,
  required InMemoryTaskRepository tasksOverride,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: tasksOverride,
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    university: InMemoryUniversityRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('Task list renders open tasks from the repository', (
    tester,
  ) async {
    final tasks = InMemoryTaskRepository();
    addTearDown(tasks.dispose);

    await tester.pumpWidget(
      _wrap(child: const TaskListPage(), tasksOverride: tasks),
    );
    await tester.pump();

    // Seeded tasks render.
    expect(find.text('Return library books'), findsOneWidget);
    expect(find.text('Renew gym membership'), findsOneWidget);

    // A newly added task appears reactively.
    await tasks.add(
      Task(
        id: 'new',
        title: 'Water the plants',
        createdAt: DateTime.now(),
      ),
    );
    await tester.pump();

    expect(find.text('Water the plants'), findsOneWidget);
  });

  testWidgets('tapping the checkbox toggles a task done via the repository', (
    tester,
  ) async {
    final tasks = InMemoryTaskRepository();
    addTearDown(tasks.dispose);

    await tester.pumpWidget(
      _wrap(child: const TaskListPage(), tasksOverride: tasks),
    );
    await tester.pump();

    expect(tasks.current.firstWhere((t) => t.id == 'seed-t2').done, isFalse);

    await tester.tap(find.byKey(const Key('task-toggle-seed-t2')));
    await tester.pump();

    expect(tasks.current.firstWhere((t) => t.id == 'seed-t2').done, isTrue);
  });

  testWidgets('the FAB opens the capture page for a new task', (
    tester,
  ) async {
    final tasks = InMemoryTaskRepository();
    addTearDown(tasks.dispose);

    await tester.pumpWidget(
      _wrap(child: const TaskListPage(), tasksOverride: tasks),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(TaskCapturePage), findsOneWidget);
    expect(find.text('New task'), findsOneWidget);
  });

  testWidgets('tapping a row opens it for editing, prefilled', (
    tester,
  ) async {
    final tasks = InMemoryTaskRepository();
    addTearDown(tasks.dispose);

    await tester.pumpWidget(
      _wrap(child: const TaskListPage(), tasksOverride: tasks),
    );
    await tester.pump();

    await tester.tap(find.text('Renew gym membership'));
    await tester.pumpAndSettle();

    expect(find.byType(TaskCapturePage), findsOneWidget);
    expect(find.text('Edit task'), findsOneWidget);
    expect(find.text('Renew gym membership'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no tasks', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final tasks = FirestoreTaskRepository(
      firestore: firestore,
      uidSource: UidSource(
        currentUid: () => 'test-uid',
        uidChanges: Stream.value('test-uid'),
      ),
    );

    await tester.pumpWidget(
      AppScope(
        auth: FakeAuthRepository(),
        profiles: FakeProfileRepository(),
        expenses: InMemoryExpenseRepository(),
        tasks: tasks,
        schedule: InMemoryScheduleRepository(),
        notes: InMemoryNoteRepository(),
        moments: InMemoryMomentRepository(),
        workouts: InMemoryWorkoutRepository(),
        university: InMemoryUniversityRepository(),
        diet: InMemoryDietRepository(),
        ai: FakeAiRepository(),
        child: const MaterialApp(home: TaskListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing to do — enjoy the quiet.'), findsOneWidget);
  });
}
