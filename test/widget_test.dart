import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zivo/app/app.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
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

import 'support/fake_auth_repository.dart';
import 'support/fake_profile_repository.dart';

void main() {
  testWidgets('Today renders the greeting and key sections when authenticated', (
    tester,
  ) async {
    // Today is a lazy ListView, so give the test a tall viewport to ensure
    // every section (through the Training card near the bottom) is built and
    // findable — the seeded focus list can otherwise push lower sections out
    // of the default 800x600 surface's build region.
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Boot the app with a pre-authenticated fake so the gate shows the shell
    // (Today) rather than the auth screen, and Firebase is never touched. A
    // fake profile repo (complete by default) keeps Firestore out of the test,
    // and in-memory tasks/expenses/schedule/notes/moments/workouts/university
    // repos override the Firestore-backed defaults so Today's sections render
    // without a live backend. The workout repo is seeded with today's session
    // so the reflective Training card has something real to show.
    final workouts = InMemoryWorkoutRepository();
    await workouts.add(
      Workout(
        id: 'today-w1',
        title: 'Push',
        performedAt: DateTime.now(),
        durationMinutes: 50,
        exercises: const [
          Exercise(name: 'Bench Press', sets: 4, reps: 8, weightKg: 60),
        ],
      ),
    );

    await tester.pumpWidget(
      ZivoApp(
        auth: FakeAuthRepository(
          initial: const Authenticated(AuthUser(uid: 'test-uid')),
        ),
        profiles: FakeProfileRepository(),
        tasks: InMemoryTaskRepository(),
        expenses: InMemoryExpenseRepository(),
        schedule: InMemoryScheduleRepository(),
        notes: InMemoryNoteRepository(),
        moments: InMemoryMomentRepository(),
        workouts: workouts,
        workoutPlans: InMemoryWorkoutPlanRepository(),
        university: InMemoryUniversityRepository(),
        diet: InMemoryDietRepository(),
        ai: FakeAiRepository(),
      ),
    );
    await tester.pumpAndSettle(); // profile stream resolves, then RiseIn timers

    expect(find.textContaining('Ziad'), findsOneWidget); // greeting
    expect(find.text('Data Structures'), findsOneWidget);
    expect(find.text('Push'), findsOneWidget); // reflective Training card
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('TODAY'), findsWidgets); // section label + tab
  });
}
