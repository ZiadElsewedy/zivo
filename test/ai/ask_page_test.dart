import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/presentation/pages/ask_page.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

void main() {
  testWidgets('Ask page sends a message and renders the honest canned reply', (tester) async {
    final ai = FakeAiRepository();
    addTearDown(ai.dispose);

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
        workoutPlans: InMemoryWorkoutPlanRepository(),
        university: InMemoryUniversityRepository(),
        diet: InMemoryDietRepository(),
        ai: ai,
        child: const MaterialApp(home: AskPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ask about your day.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'What is due this week?');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(find.text('What is due this week?'), findsOneWidget);
    expect(find.text(kFakeAiReply), findsOneWidget);
  });

  testWidgets('Ask composer clears the bottom nav bar / safe-area inset', (tester) async {
    final ai = FakeAiRepository();
    addTearDown(ai.dispose);

    const bottomInset = 80.0;
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
        workoutPlans: InMemoryWorkoutPlanRepository(),
        university: InMemoryUniversityRepository(),
        diet: InMemoryDietRepository(),
        ai: ai,
        child: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: bottomInset)),
          child: const MaterialApp(home: AskPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final screenHeight = tester.getSize(find.byType(MaterialApp)).height;
    final fieldBottom = tester.getBottomLeft(find.byType(TextField)).dy;

    expect(screenHeight - fieldBottom, greaterThanOrEqualTo(bottomInset));
  });
}
