import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/diet/presentation/pages/diet_plan_page.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

void main() {
  testWidgets('Diet plan page renders the seeded plan and marks a meal eaten', (tester) async {
    final diet = InMemoryDietRepository();
    addTearDown(diet.dispose);

    await tester.pumpWidget(
      AppScope(
        auth: FakeAuthRepository(),
        profiles: FakeProfileRepository(),
        expenses: InMemoryExpenseRepository(),
        tasks: InMemoryTaskRepository(),
        schedule: InMemoryScheduleRepository(),
        notes: InMemoryNoteRepository(),
        moments: InMemoryMomentRepository(),
        workouts: InMemoryWorkoutRepository(),
        university: InMemoryUniversityRepository(),
        diet: diet,
        ai: FakeAiRepository(),
        child: const MaterialApp(home: DietPlanPage()),
      ),
    );
    await tester.pump();

    // Seeded meals and items render.
    expect(find.text('Breakfast'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('Chicken breast'), findsOneWidget);

    // Tapping the Lunch card marks it eaten reactively.
    await tester.tap(find.text('Lunch'));
    await tester.pump();

    final consumed = await diet.watchConsumed(DateTime.now()).first;
    expect(consumed, contains('seed-meal-lunch'));
  });
}
