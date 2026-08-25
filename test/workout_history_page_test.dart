import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/domain/live_session.dart';
import 'package:zivo/features/workout/domain/session_exercise.dart';
import 'package:zivo/features/workout/domain/session_status.dart';
import 'package:zivo/features/workout/domain/workout_session_repository.dart';
import 'package:zivo/features/workout/presentation/pages/session_details_page.dart';
import 'package:zivo/features/workout/presentation/pages/workout_history_page.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_profile_repository.dart';

/// A repository whose stream only emits when [emit] is called, so tests can
/// assert on the in-between "waiting" state deterministically.
class _PendingSessionRepository implements WorkoutSessionRepository {
  final StreamController<List<LiveSession>> _controller = StreamController<List<LiveSession>>.broadcast();

  @override
  List<LiveSession> get current => const [];

  @override
  Stream<List<LiveSession>> watchAll() => _controller.stream;

  @override
  LiveSession? get activeSession => null;

  @override
  Stream<LiveSession?> watchActiveSession() => const Stream.empty();

  @override
  Future<void> saveSession(LiveSession session) async {}

  @override
  Future<void> deleteSession(String id) async {}

  void emit(List<LiveSession> sessions) => _controller.add(sessions);

  void dispose() => _controller.close();
}

Widget _wrap({required Widget child, required WorkoutSessionRepository sessionsOverride}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: sessionsOverride,
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

LiveSession _session({
  required String id,
  required String dayLabel,
  DateTime? startedAt,
  Duration duration = const Duration(minutes: 50),
  SessionStatus status = SessionStatus.completed,
  List<SessionExercise> exercises = const [],
}) {
  final start = startedAt ?? DateTime(2026, 3, 1, 6);
  return LiveSession(
    id: id,
    planId: 'p1',
    dayId: 'day-a',
    dayLabel: dayLabel,
    startedAt: start,
    completedAt: status == SessionStatus.active ? null : start.add(duration),
    status: status,
    exercises: exercises,
  );
}

void main() {
  testWidgets('renders logged sessions from the repository, richest fields first', (tester) async {
    final sessions = InMemoryWorkoutSessionRepository(
      seed: [
        _session(
          id: 's1',
          dayLabel: 'Push',
          exercises: const [
            SessionExercise(id: 'e1', exerciseId: 'e1', name: 'Bench', restSeconds: 90, sets: []),
          ],
        ),
      ],
    );

    await tester.pumpWidget(_wrap(child: const WorkoutHistoryPage(), sessionsOverride: sessions));
    await tester.pump();

    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    // The duration appears on the session row AND rolled up in the summary
    // strip's total-time stat — so at least one, not exactly one.
    expect(find.text('50m'), findsWidgets);
    expect(find.text('1 exercise'), findsOneWidget);

    // A newly logged session appears at the top reactively.
    await sessions.saveSession(_session(id: 'new', dayLabel: 'Legs', startedAt: DateTime(2026, 3, 2, 6)));
    await tester.pump();

    expect(find.text('Legs'), findsOneWidget);
  });

  testWidgets('shows a spinner while the stream is waiting, then the list', (tester) async {
    final sessions = _PendingSessionRepository();
    addTearDown(sessions.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutHistoryPage(), sessionsOverride: sessions));

    expect(find.byType(Lottie), findsOneWidget);
    expect(find.text('No sessions logged yet.'), findsNothing);

    sessions.emit([_session(id: 's1', dayLabel: 'Push')]);
    await tester.pump();

    expect(find.byType(Lottie), findsNothing);
    expect(find.text('Push'), findsOneWidget);
  });

  testWidgets('shows the empty state once the stream settles with no data', (tester) async {
    final sessions = _PendingSessionRepository();
    addTearDown(sessions.dispose);

    await tester.pumpWidget(_wrap(child: const WorkoutHistoryPage(), sessionsOverride: sessions));

    sessions.emit(const []);
    await tester.pump();

    expect(find.byType(Lottie), findsNothing);
    expect(find.text('No sessions logged yet.'), findsOneWidget);
  });

  testWidgets('tapping a row opens SessionDetailsPage for that session', (tester) async {
    final sessions = InMemoryWorkoutSessionRepository(seed: [_session(id: 's1', dayLabel: 'Push')]);

    await tester.pumpWidget(_wrap(child: const WorkoutHistoryPage(), sessionsOverride: sessions));
    await tester.pump();

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();

    expect(find.byType(SessionDetailsPage), findsOneWidget);
    expect(find.text('Session details'), findsOneWidget);
  });

  testWidgets('an in-progress session shows "In progress" status, not "Completed"', (tester) async {
    final sessions = InMemoryWorkoutSessionRepository(
      seed: [
        _session(id: 's1', dayLabel: 'Pull', status: SessionStatus.active, startedAt: DateTime.now()),
      ],
    );

    await tester.pumpWidget(_wrap(child: const WorkoutHistoryPage(), sessionsOverride: sessions));
    await tester.pump();

    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);
  });
}
