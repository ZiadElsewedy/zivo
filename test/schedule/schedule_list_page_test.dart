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
import 'package:zivo/features/schedule/data/firestore_schedule_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/schedule/domain/schedule_event.dart';
import 'package:zivo/features/schedule/presentation/pages/event_capture_page.dart';
import 'package:zivo/features/schedule/presentation/pages/schedule_list_page.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

Widget _wrap({
  required Widget child,
  required InMemoryScheduleRepository scheduleOverride,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: scheduleOverride,
    notes: InMemoryNoteRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: InMemoryWorkoutSessionRepository(),
    university: InMemoryUniversityRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets(
    'events render grouped by day, upcoming ordered ascending, past under '
    'Earlier',
    (tester) async {
      final schedule = InMemoryScheduleRepository();
      addTearDown(schedule.dispose);

      final now = DateTime.now();
      await schedule.add(
        ScheduleEvent(
          id: 'standup',
          title: 'Standup',
          start: now.add(const Duration(minutes: 30)),
        ),
      );
      await schedule.add(
        ScheduleEvent(
          id: 'trip',
          title: 'Airport trip',
          start: now.add(const Duration(days: 1)),
        ),
      );
      await schedule.add(
        ScheduleEvent(
          id: 'old-meeting',
          title: 'Old meeting',
          start: now.subtract(const Duration(days: 2)),
          end: now.subtract(const Duration(days: 2)).add(const Duration(hours: 1)),
        ),
      );

      await tester.pumpWidget(
        _wrap(child: const ScheduleListPage(), scheduleOverride: schedule),
      );
      await tester.pump();

      // Seeded event + all three added events render.
      expect(find.text('Data Structures'), findsOneWidget);
      expect(find.text('Standup'), findsOneWidget);
      expect(find.text('Airport trip'), findsOneWidget);
      expect(find.text('Old meeting'), findsOneWidget);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('Earlier'), findsOneWidget);

      // Group order: Today -> Tomorrow -> Earlier.
      final todayY = tester.getTopLeft(find.text('Today')).dy;
      final tomorrowY = tester.getTopLeft(find.text('Tomorrow')).dy;
      final earlierY = tester.getTopLeft(find.text('Earlier')).dy;
      expect(todayY, lessThan(tomorrowY));
      expect(tomorrowY, lessThan(earlierY));

      // Within Today, Standup (in 30m) is before Data Structures (in 2h).
      final standupY = tester.getTopLeft(find.text('Standup')).dy;
      final dataStructuresY = tester.getTopLeft(find.text('Data Structures')).dy;
      expect(standupY, lessThan(dataStructuresY));
    },
  );

  testWidgets('the FAB opens the capture page for a new event', (
    tester,
  ) async {
    final schedule = InMemoryScheduleRepository();
    addTearDown(schedule.dispose);

    await tester.pumpWidget(
      _wrap(child: const ScheduleListPage(), scheduleOverride: schedule),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(EventCapturePage), findsOneWidget);
    expect(find.text('New event'), findsOneWidget);
  });

  testWidgets('tapping a row opens it for editing, prefilled', (
    tester,
  ) async {
    final schedule = InMemoryScheduleRepository();
    addTearDown(schedule.dispose);

    await tester.pumpWidget(
      _wrap(child: const ScheduleListPage(), scheduleOverride: schedule),
    );
    await tester.pump();

    await tester.tap(find.text('Data Structures'));
    await tester.pumpAndSettle();

    expect(find.byType(EventCapturePage), findsOneWidget);
    expect(find.text('Edit event'), findsOneWidget);
    expect(find.text('Data Structures'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no events', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final schedule = FirestoreScheduleRepository(
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
        tasks: InMemoryTaskRepository(),
        schedule: schedule,
        notes: InMemoryNoteRepository(),
        moments: InMemoryMomentRepository(),
        workouts: InMemoryWorkoutRepository(),
        workoutPlans: InMemoryWorkoutPlanRepository(),
        workoutSessions: InMemoryWorkoutSessionRepository(),
        university: InMemoryUniversityRepository(),
        diet: InMemoryDietRepository(),
        ai: FakeAiRepository(),
        child: const MaterialApp(home: ScheduleListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing on the calendar — enjoy the quiet.'), findsOneWidget);
  });
}
