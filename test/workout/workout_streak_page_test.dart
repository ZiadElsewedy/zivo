import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/data/in_memory_training_day_mark_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/training_day_mark.dart';
import 'package:zivo/features/workout/presentation/pages/workout_stats_pages.dart';

import '../support/test_app.dart';
import '../support/workout_fixtures.dart';

/// The streak drill-down: what it shows, and — the part that matters — that a
/// broken streak is not a dead end.
Future<void> _pump(
  WidgetTester tester, {
  required List<LiveSession> sessions,
  List<TrainingDayMark> marks = const [],
}) async {
  await tester.pumpWidget(
    wrapWithScope(
      const WorkoutStreakPage(),
      workoutSessions: InMemoryWorkoutSessionRepository(seed: sessions),
      trainingDayMarks: InMemoryTrainingDayMarkRepository(seed: marks),
    ),
  );
  await tester.pump();
}

DateTime _daysAgo(int n) =>
    DateTime.now().subtract(Duration(days: n)).copyWith(hour: 12, minute: 0);

void main() {
  testWidgets('a live run lists its trained days and the rest days between', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      sessions: [
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(2)),
      ],
    );

    // Two trained days with one rest day between them — the run reads as a
    // continuous stretch rather than two entries with a hole where a rest day
    // should be.
    expect(find.text('REST DAY'), findsOneWidget);
    expect(find.text('Train at least every 3 days'), findsOneWidget);
  });

  testWidgets(
    'a BROKEN streak still lists recent days, so a restore is reachable',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Trained six days ago and not since: the run is gone. This is exactly
      // when a restore is wanted, so the page must not be an empty card.
      await _pump(tester, sessions: [session(id: 'a', startedAt: _daysAgo(6))]);

      expect(find.text('No active streak'), findsOneWidget);
      expect(
        find.text('REST DAY'),
        findsWidgets,
        reason: 'days to act on, not a dead end',
      );
    },
  );

  testWidgets('a restored day is labelled as restored, not as a workout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      sessions: [
        session(id: 'a', startedAt: _daysAgo(0)),
        session(id: 'b', startedAt: _daysAgo(5)),
      ],
      marks: [
        TrainingDayMark(
          day: DateTime(
            _daysAgo(3).year,
            _daysAgo(3).month,
            _daysAgo(3).day,
          ),
          createdAt: DateTime.now(),
          restored: true,
        ),
      ],
    );

    expect(find.text('RESTORED'), findsOneWidget);
    // Two real sessions bridged by a restore — the headline counts the two,
    // never three.
    expect(find.text('2'), findsWidgets);
  });
}
