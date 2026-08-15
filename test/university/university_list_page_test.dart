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
import 'package:zivo/features/university/domain/university_item.dart';
import 'package:zivo/features/university/domain/university_item_type.dart';
import 'package:zivo/features/university/presentation/pages/university_list_page.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

void main() {
  testWidgets(
    'University list renders items grouped by course from the repository',
    (tester) async {
      final university = InMemoryUniversityRepository();
      addTearDown(university.dispose);

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
          university: university,
          diet: InMemoryDietRepository(),
          ai: FakeAiRepository(),
          child: const MaterialApp(home: UniversityListPage()),
        ),
      );
      await tester.pump();

      // Seeded items render.
      expect(find.text('Assignment 2 — Algorithms'), findsOneWidget);
      expect(find.text('Midterm — Data Structures'), findsOneWidget);

      // A newly added item appears reactively.
      await university.add(
        UniversityItem(
          id: 'new',
          title: 'Lab report — Circuits',
          type: UniversityItemType.assignment,
          createdAt: DateTime.now(),
          courseName: 'Circuits',
        ),
      );
      await tester.pump();

      expect(find.text('Lab report — Circuits'), findsOneWidget);

      // Tapping a row toggles it done.
      await tester.tap(find.text('Lab report — Circuits'));
      await tester.pump();
      expect(university.current.firstWhere((i) => i.id == 'new').done, isTrue);
    },
  );
}
