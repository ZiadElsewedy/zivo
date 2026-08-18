import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/core/widgets/reactive_state_views.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/moments/domain/moment.dart';
import 'package:zivo/features/moments/domain/moment_repository.dart';
import 'package:zivo/features/moments/presentation/pages/moment_capture_page.dart';
import 'package:zivo/features/moments/presentation/pages/moments_timeline_page.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_plan_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_session_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

/// A repository whose stream stays open without ever emitting, so the list
/// page sits in its loading state until [emit] is called.
class _PendingMomentRepository implements MomentRepository {
  final StreamController<List<Moment>> _controller =
      StreamController<List<Moment>>.broadcast();

  @override
  List<Moment> get current => const [];

  @override
  Stream<List<Moment>> watchAll() => _controller.stream;

  @override
  Future<void> add(Moment moment) async {}

  @override
  Future<void> update(Moment moment) async {}

  @override
  Future<void> remove(String id) async {}

  void emit(List<Moment> moments) => _controller.add(moments);

  void emitError(Object error) => _controller.addError(error);

  void dispose() => _controller.close();
}

Widget _wrap({
  required Widget child,
  required MomentRepository momentsOverride,
}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: InMemoryNoteRepository(),
    moments: momentsOverride,
    workouts: InMemoryWorkoutRepository(),
    workoutPlans: InMemoryWorkoutPlanRepository(),
    workoutSessions: InMemoryWorkoutSessionRepository(),
    university: InMemoryUniversityRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

/// The capture page stacks a fixed 3:2 photo tile above the caption and button,
/// which is taller than the default 800×600 test surface (it fits on real
/// phones). Give tests that push the capture page room so its controls stay
/// on-screen and hit-testable.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('Moments timeline renders items from the repository', (
    tester,
  ) async {
    final moments = InMemoryMomentRepository();
    addTearDown(moments.dispose);

    await tester.pumpWidget(
      _wrap(child: const MomentsTimelinePage(), momentsOverride: moments),
    );
    await tester.pump();

    // The seeded moment renders.
    expect(find.text('First sketch of the ZIVO home screen.'), findsOneWidget);

    await moments.add(
      Moment(id: 'new', caption: 'Sunset run', takenAt: DateTime.now()),
    );
    await tester.pump();

    expect(find.text('Sunset run'), findsOneWidget);
  });

  testWidgets('the FAB opens the capture page for a new moment', (tester) async {
    _useTallSurface(tester);
    final moments = InMemoryMomentRepository();
    addTearDown(moments.dispose);

    await tester.pumpWidget(
      _wrap(child: const MomentsTimelinePage(), momentsOverride: moments),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(MomentCapturePage), findsOneWidget);
    expect(find.text('New moment'), findsOneWidget);
  });

  testWidgets('tapping a card opens it for editing, prefilled', (tester) async {
    _useTallSurface(tester);
    final moments = InMemoryMomentRepository();
    addTearDown(moments.dispose);

    await tester.pumpWidget(
      _wrap(child: const MomentsTimelinePage(), momentsOverride: moments),
    );
    await tester.pump();

    await tester.tap(find.text('First sketch of the ZIVO home screen.'));
    await tester.pumpAndSettle();

    expect(find.byType(MomentCapturePage), findsOneWidget);
    expect(find.text('Edit moment'), findsOneWidget);
    // The caption is prefilled into the editor.
    expect(find.text('First sketch of the ZIVO home screen.'), findsOneWidget);
  });

  testWidgets('editing a moment preserves its original capture time', (
    tester,
  ) async {
    _useTallSurface(tester);
    final moments = InMemoryMomentRepository();
    addTearDown(moments.dispose);
    final takenAt = DateTime(2026, 1, 2, 9, 30);
    await moments.add(
      Moment(id: 'edit-me', caption: 'Old caption', takenAt: takenAt),
    );

    await tester.pumpWidget(
      _wrap(child: const MomentsTimelinePage(), momentsOverride: moments),
    );
    await tester.pump();

    await tester.tap(find.text('Old caption'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'New caption');
    await tester.tap(find.text('Save moment'));
    await tester.pumpAndSettle();

    final edited = moments.current.firstWhere((m) => m.id == 'edit-me');
    expect(edited.caption, 'New caption');
    expect(edited.takenAt, takenAt);
  });

  testWidgets('swiping a card deletes it via the repository', (tester) async {
    final moments = InMemoryMomentRepository();
    addTearDown(moments.dispose);
    await moments.add(
      Moment(id: 'to-delete', caption: 'Temp moment', takenAt: DateTime.now()),
    );

    await tester.pumpWidget(
      _wrap(child: const MomentsTimelinePage(), momentsOverride: moments),
    );
    await tester.pump();

    expect(moments.current.any((m) => m.id == 'to-delete'), isTrue);

    await tester.drag(find.text('Temp moment'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(moments.current.any((m) => m.id == 'to-delete'), isFalse);
  });

  testWidgets('shows a loading spinner before the stream first emits', (
    tester,
  ) async {
    final moments = _PendingMomentRepository();
    addTearDown(moments.dispose);

    await tester.pumpWidget(
      _wrap(child: const MomentsTimelinePage(), momentsOverride: moments),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No moments yet.'), findsNothing);

    moments.emit([
      Moment(id: 'm1', caption: 'Fresh moment', takenAt: DateTime.now()),
    ]);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Fresh moment'), findsOneWidget);
  });

  testWidgets('shows the empty state once the stream settles with no data', (
    tester,
  ) async {
    final moments = _PendingMomentRepository();
    addTearDown(moments.dispose);

    await tester.pumpWidget(
      _wrap(child: const MomentsTimelinePage(), momentsOverride: moments),
    );

    moments.emit(const []);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No moments yet.'), findsOneWidget);
  });

  testWidgets('shows the error view when the stream errors', (tester) async {
    final moments = _PendingMomentRepository();
    addTearDown(moments.dispose);

    await tester.pumpWidget(
      _wrap(child: const MomentsTimelinePage(), momentsOverride: moments),
    );

    moments.emitError(Exception('read denied'));
    await tester.pump();

    expect(find.byType(ErrorStateView), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No moments yet.'), findsNothing);
  });
}
