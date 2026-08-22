import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/rep_target.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/logged_set.dart';
import 'package:zivo/features/workout/domain/set_outcome.dart';
import 'package:zivo/features/workout/presentation/pages/session_details_page.dart';

Widget _wrap(LiveSession session) => MaterialApp(home: SessionDetailsPage(session: session));

void main() {
  testWidgets('shows the hero header: day label, status, duration, exercise/set counts', (tester) async {
    final session = LiveSession(
      id: 's1',
      planId: 'p1',
      dayId: 'd1',
      dayLabel: 'Push',
      startedAt: DateTime(2026, 8, 20, 6, 0),
      completedAt: DateTime(2026, 8, 20, 6, 45),
      status: SessionStatus.completed,
      exercises: const [
        SessionExercise(
          id: 'e1',
          exerciseId: 'e1',
          name: 'Bench Press',
          muscleGroup: 'Chest',
          restSeconds: 90,
          sets: [
            LoggedSet(
              id: 'set1',
              target: RepTarget.range(8, 10),
              targetWeightKg: 60,
              actualReps: 8,
              actualWeightKg: 60,
              outcome: SetOutcome.completed,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(_wrap(session));

    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('45m'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // exercise count
    expect(find.text('1/1'), findsOneWidget); // sets done
    expect(find.textContaining('6:00'), findsOneWidget);
  });

  testWidgets('renders each set with weight/reps, a skipped marker, and RPE when present', (tester) async {
    final session = LiveSession(
      id: 's1',
      planId: 'p1',
      dayId: 'd1',
      dayLabel: 'Pull',
      startedAt: DateTime(2026, 8, 20, 6, 0),
      completedAt: DateTime(2026, 8, 20, 6, 30),
      status: SessionStatus.completed,
      exercises: const [
        SessionExercise(
          id: 'e1',
          exerciseId: 'e1',
          name: 'Lat Pulldown',
          restSeconds: 60,
          sets: [
            LoggedSet(
              id: 'set1',
              target: RepTarget.fixed(8),
              targetWeightKg: 80,
              actualReps: 8,
              actualWeightKg: 80,
              rpe: 8,
              outcome: SetOutcome.completed,
            ),
            LoggedSet(
              id: 'set2',
              target: RepTarget.fixed(8),
              targetWeightKg: 80,
              outcome: SetOutcome.skipped,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(_wrap(session));

    expect(find.text('80kg × 8'), findsNWidgets(2)); // set1 actuals + set2 falls back to target
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.text('RPE 8'), findsOneWidget);
  });

  testWidgets('an in-progress session shows a live-elapsed duration instead of zero', (tester) async {
    final session = LiveSession(
      id: 's1',
      planId: 'p1',
      dayId: 'd1',
      dayLabel: 'Legs',
      startedAt: DateTime.now().subtract(const Duration(minutes: 20)),
      status: SessionStatus.active,
      exercises: const [],
    );

    await tester.pumpWidget(_wrap(session));

    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('0m'), findsNothing);
  });
}
