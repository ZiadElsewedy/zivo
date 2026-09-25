import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/util/calendar.dart';
import 'package:zivo/features/workout/data/in_memory_training_day_mark_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/planned_exercise.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/set_type.dart';
import 'package:zivo/features/workout/domain/training_day_mark.dart';
import 'package:zivo/features/workout/domain/workout_day.dart';
import 'package:zivo/features/workout/domain/workout_plan.dart';
import 'package:zivo/features/workout/domain/workout_plan_source.dart';
import 'package:zivo/features/workout/domain/workout_plan_status.dart';
import 'package:zivo/features/workout/domain/workout_set.dart';
import 'package:zivo/features/workout/presentation/widgets/training_day_card.dart';

import '../support/test_app.dart';
import '../support/workout_fixtures.dart';

final _now = DateTime(2026, 9, 10, 12);
DateTime _daysAgo(int n) => addCalendarDays(_now, -n);

const _bench = PlannedExercise(
  id: 'bench',
  name: 'Bench Press',
  order: 0,
  defaultRestSeconds: 90,
  sets: [
    PlannedSet(
      order: 0,
      repTarget: RepTarget.fixed(8),
      restSeconds: 90,
      type: SetType.working,
    ),
  ],
);

/// Upper → Lower → Rest.
final _plan = WorkoutPlan(
  id: 'p1',
  name: 'Upper/Lower',
  status: WorkoutPlanStatus.active,
  source: WorkoutPlanSource.pdf,
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 1),
  cycleCursor: 0,
  days: const [
    WorkoutDay(
      id: 'up',
      slot: 'A',
      label: 'Upper',
      order: 0,
      exercises: [_bench],
    ),
    WorkoutDay(
      id: 'lo',
      slot: 'B',
      label: 'Lower',
      order: 1,
      exercises: [_bench],
    ),
    WorkoutDay(
      id: 'r',
      slot: 'C',
      label: 'Rest',
      order: 2,
      type: TrainingDayType.rest,
      exercises: [],
    ),
  ],
);

Future<InMemoryTrainingDayMarkRepository> _pump(
  WidgetTester tester, {
  required List<LiveSession> sessions,
  List<TrainingDayMark> marks = const [],
}) async {
  final repo = InMemoryTrainingDayMarkRepository(seed: marks);
  await tester.pumpWidget(
    wrapWithScope(
      Scaffold(
        body: SingleChildScrollView(
          child: TrainingDayCard(
            plan: _plan,
            day: _plan.nextDay!,
            resumable: null,
            now: () => _now,
          ),
        ),
      ),
      workoutSessions: InMemoryWorkoutSessionRepository(seed: sessions),
      trainingDayMarks: repo,
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('a planned rest day shows as rest — no empty workout, no Start', (
    tester,
  ) async {
    // Lower yesterday; the split's rest slot follows Lower.
    await _pump(
      tester,
      sessions: [
        session(id: 'a', startedAt: _daysAgo(2), dayId: 'up'),
        session(id: 'b', startedAt: _daysAgo(1), dayId: 'lo'),
      ],
    );
    expect(find.byKey(const Key('rest-day-planned')), findsOneWidget);
    expect(find.text("Today's rest day"), findsOneWidget);
    expect(find.text('Recovery is part of your training.'), findsOneWidget);
    expect(find.byKey(const Key('training-start')), findsNothing);
    expect(find.text('0'), findsNothing, reason: 'no "0 exercises" stat');
    expect(find.textContaining('Upper'), findsOneWidget, reason: 'next up');
    expect(find.byKey(const Key('rest-train-anyway')), findsOneWidget);
  });

  testWidgets('a due workout offers Start and "Take a rest day"', (
    tester,
  ) async {
    await _pump(
      tester,
      sessions: [session(id: 'a', startedAt: _daysAgo(1), dayId: 'up')],
    );
    expect(find.byKey(const Key('training-start')), findsOneWidget);
    expect(find.byKey(const Key('training-take-rest')), findsOneWidget);
  });

  testWidgets(
    'taking a rest day records it and flips the card; resuming undoes it',
    (tester) async {
      final repo = await _pump(
        tester,
        sessions: [session(id: 'a', startedAt: _daysAgo(1), dayId: 'up')],
      );
      await tester.tap(find.byKey(const Key('training-take-rest')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rest-day-chosen')), findsOneWidget);
      expect(find.text('You chose to rest today'), findsOneWidget);
      expect(find.byKey(const Key('training-start')), findsNothing);
      final mark = repo.current.single;
      expect(mark.reason, MissedDayReason.rest);
      expect(startOfDay(mark.day), startOfDay(_now));
      // The plan itself is untouched: the same workout is still what's next.
      expect(_plan.nextDay!.id, 'up');
      expect(find.textContaining('Upper'), findsOneWidget);

      await tester.tap(find.byKey(const Key('rest-resume-workout')));
      await tester.pumpAndSettle();
      expect(repo.current, isEmpty, reason: 'an empty mark is deleted');
      expect(find.byKey(const Key('training-start')), findsOneWidget);
    },
  );

  testWidgets('withdrawing rest keeps a restore already spent on the day', (
    tester,
  ) async {
    final repo = await _pump(
      tester,
      sessions: [session(id: 'a', startedAt: _daysAgo(1), dayId: 'up')],
      marks: [
        TrainingDayMark(
          day: startOfDay(_now),
          createdAt: _now,
          reason: MissedDayReason.rest,
          restored: true,
        ),
      ],
    );
    await tester.tap(find.byKey(const Key('rest-resume-workout')));
    await tester.pumpAndSettle();
    expect(repo.current.single.restored, isTrue);
    expect(repo.current.single.reason, isNull);
  });

  testWidgets('no "Take a rest day" once today is already trained', (
    tester,
  ) async {
    await _pump(
      tester,
      sessions: [
        session(id: 'a', startedAt: DateTime(2026, 9, 10, 8), dayId: 'up'),
      ],
    );
    expect(find.byKey(const Key('training-take-rest')), findsNothing);
  });
}
