import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/firebase/uid_source.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/diet/data/firestore_diet_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/domain/diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/home/presentation/header_builder.dart';
import 'package:zivo/features/home/presentation/pages/today_page.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/domain/exercise.dart';
import 'package:zivo/features/workout/domain/workout.dart';
import 'package:zivo/features/workout/domain/workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

Widget _wrap({
  required Widget child,
  required DietRepository diet,
  WorkoutRepository? workouts,
}) {
  return AppScope(
    auth: FakeAuthRepository(
      initial: const Authenticated(AuthUser(uid: 'test-uid')),
    ),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: workouts ?? InMemoryWorkoutRepository(),
    university: InMemoryUniversityRepository(),
    diet: diet,
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

void main() {
  Future<void> tallView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('header shows the profile name and a real date', (
    tester,
  ) async {
    await tallView(tester);

    await tester.pumpWidget(
      _wrap(child: const TodayPage(), diet: InMemoryDietRepository()),
    );
    await tester.pumpAndSettle();

    // FakeProfileRepository defaults to the name 'Ziad'.
    expect(find.textContaining('Ziad'), findsOneWidget);
    expect(
      find.text(formatTodayDate(DateTime.now()).toUpperCase()),
      findsOneWidget,
    );
  });

  testWidgets('Training reflects an injected workout logged today', (
    tester,
  ) async {
    await tallView(tester);

    final workouts = InMemoryWorkoutRepository();
    await workouts.add(
      Workout(
        id: 'today-w1',
        title: 'Pull',
        performedAt: DateTime.now(),
        durationMinutes: 45,
        exercises: const [
          Exercise(name: 'Lat Pulldown', sets: 4, reps: 10),
        ],
      ),
    );

    await tester.pumpWidget(
      _wrap(
        child: const TodayPage(),
        diet: InMemoryDietRepository(),
        workouts: workouts,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pull'), findsOneWidget);
    expect(find.text('Lat Pulldown'), findsOneWidget);
    expect(find.text('No training logged yet today.'), findsNothing);
  });

  testWidgets('Training shows the empty state when nothing was logged today', (
    tester,
  ) async {
    await tallView(tester);

    // The default InMemoryWorkoutRepository seeds a workout from yesterday.
    await tester.pumpWidget(
      _wrap(child: const TodayPage(), diet: InMemoryDietRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text('No training logged yet today.'), findsOneWidget);
  });

  testWidgets('Diet glance shows the summary when an active plan exists', (
    tester,
  ) async {
    await tallView(tester);

    await tester.pumpWidget(
      _wrap(child: const TodayPage(), diet: InMemoryDietRepository()),
    );
    await tester.pumpAndSettle();

    // Seeded plan: 3 meals (Breakfast/Lunch/Dinner), none eaten yet.
    expect(find.textContaining('of 3 meals eaten'), findsOneWidget);
  });

  testWidgets('Diet glance is hidden when there is no active plan', (
    tester,
  ) async {
    await tallView(tester);

    final diet = FirestoreDietRepository(
      firestore: FakeFirebaseFirestore(),
      uidSource: UidSource(
        currentUid: () => 'test-uid',
        uidChanges: Stream.value('test-uid'),
      ),
    );

    await tester.pumpWidget(_wrap(child: const TodayPage(), diet: diet));
    await tester.pumpAndSettle();

    expect(find.text('DIET'), findsNothing);
    expect(find.textContaining('meals eaten'), findsNothing);
  });
}
