import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
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
import 'package:zivo/features/university/domain/university_repository.dart';
import 'package:zivo/features/university/presentation/pages/university_capture_page.dart';
import 'package:zivo/features/university/presentation/pages/university_list_page.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

class _PendingUniversityRepository implements UniversityRepository {
  final StreamController<List<UniversityItem>> _controller =
      StreamController<List<UniversityItem>>.broadcast();

  @override
  List<UniversityItem> get current => const [];

  @override
  Stream<List<UniversityItem>> watchAll() => _controller.stream;

  @override
  Future<void> add(UniversityItem item) async {}

  @override
  Future<void> update(UniversityItem item) async {}

  @override
  Future<void> setDone(String id, bool done) async {}

  @override
  Future<void> remove(String id) async {}

  void emit(List<UniversityItem> items) => _controller.add(items);

  void dispose() => _controller.close();
}

Widget _wrap({
  required Widget child,
  required UniversityRepository universityOverride,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: InMemoryWorkoutSessionRepository(),
    university: universityOverride,
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets(
    'University list renders items grouped by course from the repository',
    (tester) async {
      final university = InMemoryUniversityRepository();
      addTearDown(university.dispose);

      await tester.pumpWidget(
        _wrap(
          child: const UniversityListPage(),
          universityOverride: university,
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

      // Tapping the checkbox toggles it done.
      await tester.tap(find.byKey(const Key('university-toggle-new')));
      await tester.pump();
      expect(university.current.firstWhere((i) => i.id == 'new').done, isTrue);
    },
  );

  testWidgets('tapping a row opens it for editing, prefilled', (
    tester,
  ) async {
    final university = InMemoryUniversityRepository();
    addTearDown(university.dispose);

    await tester.pumpWidget(
      _wrap(
        child: const UniversityListPage(),
        universityOverride: university,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Assignment 2 — Algorithms'));
    await tester.pumpAndSettle();

    expect(find.byType(UniversityCapturePage), findsOneWidget);
    expect(find.text('Edit university item'), findsOneWidget);
    expect(find.text('Assignment 2 — Algorithms'), findsOneWidget);
  });

  testWidgets('swiping a row deletes it via the repository', (tester) async {
    final university = InMemoryUniversityRepository();
    addTearDown(university.dispose);
    await university.add(
      UniversityItem(
        id: 'to-delete',
        title: 'Quiz 1',
        type: UniversityItemType.exam,
        createdAt: DateTime.now(),
        courseName: 'Physics',
      ),
    );

    await tester.pumpWidget(
      _wrap(
        child: const UniversityListPage(),
        universityOverride: university,
      ),
    );
    await tester.pump();

    expect(university.current.any((i) => i.id == 'to-delete'), isTrue);

    await tester.drag(find.text('Quiz 1'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(university.current.any((i) => i.id == 'to-delete'), isFalse);
  });

  testWidgets('shows a loading spinner before the stream first emits', (
    tester,
  ) async {
    final university = _PendingUniversityRepository();
    addTearDown(university.dispose);

    await tester.pumpWidget(
      _wrap(
        child: const UniversityListPage(),
        universityOverride: university,
      ),
    );

    expect(find.byType(Lottie), findsOneWidget);
    expect(find.text('Nothing due — enjoy the quiet.'), findsNothing);

    university.emit([
      UniversityItem(
        id: 'u1',
        title: 'Lab report',
        type: UniversityItemType.assignment,
        createdAt: DateTime.now(),
      ),
    ]);
    await tester.pump();

    expect(find.byType(Lottie), findsNothing);
    expect(find.text('Lab report'), findsOneWidget);
  });

  testWidgets('shows the empty state once the stream settles with no data', (
    tester,
  ) async {
    final university = _PendingUniversityRepository();
    addTearDown(university.dispose);

    await tester.pumpWidget(
      _wrap(
        child: const UniversityListPage(),
        universityOverride: university,
      ),
    );

    university.emit(const []);
    await tester.pump();

    expect(find.byType(Lottie), findsNothing);
    expect(find.text('Nothing due — enjoy the quiet.'), findsOneWidget);
  });
}
