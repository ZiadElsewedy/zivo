import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zivo/app/app.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_category_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_wallet_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_body_weight_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/exercise.dart';
import 'package:zivo/features/workout/domain/workout.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_profile_repository.dart';
import 'support/test_app.dart';

void main() {
  testWidgets('Today renders the greeting and key sections when authenticated', (
    tester,
  ) async {
    // Today is a lazy ListView, so give the test a tall viewport to ensure
    // every section (through the Training card near the bottom) is built and
    // findable within the default 800x600 surface's build region.
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Boot the app with a pre-authenticated fake so the gate shows the shell
    // (Today) rather than the auth screen, and Firebase is never touched. A
    // fake profile repo (complete by default) keeps Firestore out of the test,
    // and in-memory expenses/moments/workouts repos override the
    // Firestore-backed defaults so Today's sections render without a live
    // backend. A workout is logged today too ("Pull") — the
    // Training card must show the active plan's up-next day ("Push", from
    // the default `InMemoryWorkoutPlanRepository` seed, cycleCursor 0) NOT
    // roll back to reflect what was just logged, so the workout repo here
    // deliberately exercises that it doesn't leak through.
    final workouts = InMemoryWorkoutRepository();
    await workouts.add(
      Workout(
        id: 'today-w1',
        title: 'Pull',
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
        expenses: InMemoryExpenseRepository(),
        wallet: InMemoryWalletRepository(),
        expenseCategories: InMemoryCategoryRepository(),
        moments: InMemoryMomentRepository(),
        workouts: workouts,
        workoutPlans: InMemoryWorkoutPlanRepository(),
        workoutSessions: InMemoryWorkoutSessionRepository(),
        bodyWeight: InMemoryBodyWeightRepository(),
        diet: InMemoryDietRepository(),
        ai: FakeAiRepository(),
        media: testMediaService(),
      ),
    );
    // Not pumpAndSettle — the up-next Training card carries a continuous,
    // always-on repeating animation (`AliveColorDrift`, in
    // `up_next_workout_card.dart`) that never settles on its own now that
    // an active plan is always seeded here. Bounded pumps instead: one to
    // let the profile stream resolve, then a generous fixed duration for
    // the RiseIn entrance timers.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.textContaining('Ziad'), findsOneWidget); // greeting
    // The plan's up-next day ("Push", order 0) — not "Pull", the workout
    // logged today (see the seeding comment above for why that matters).
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Start Workout'), findsOneWidget);
    expect(find.text('Pull'), findsNothing);
    expect(find.text('Bench Press'), findsNothing);
    expect(find.text('TODAY'), findsWidgets); // bottom tab label
  });
}
