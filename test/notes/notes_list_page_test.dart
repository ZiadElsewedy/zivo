import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/scope/app_scope.dart';
import 'package:zivo/core/widgets/reactive_state_views.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/diet/data/in_memory_diet_repository.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/moments/data/in_memory_moment_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/notes/domain/note.dart';
import 'package:zivo/features/notes/domain/note_repository.dart';
import 'package:zivo/features/notes/presentation/pages/note_capture_page.dart';
import 'package:zivo/features/notes/presentation/pages/notes_list_page.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';
import 'package:zivo/features/university/data/in_memory_university_repository.dart';
import 'package:zivo/features/workout/data/in_memory_workout_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';

class _PendingNoteRepository implements NoteRepository {
  final StreamController<List<Note>> _controller =
      StreamController<List<Note>>.broadcast();

  @override
  List<Note> get current => const [];

  @override
  Stream<List<Note>> watchAll() => _controller.stream;

  @override
  Future<void> add(Note note) async {}

  @override
  Future<void> update(Note note) async {}

  @override
  Future<void> remove(String id) async {}

  void emit(List<Note> notes) => _controller.add(notes);

  void emitError(Object error) => _controller.addError(error);

  void dispose() => _controller.close();
}

Widget _wrap({required Widget child, required NoteRepository notesOverride}) {
  return AppScope(
    auth: FakeAuthRepository(),
    profiles: FakeProfileRepository(),
    expenses: InMemoryExpenseRepository(),
    tasks: InMemoryTaskRepository(),
    schedule: InMemoryScheduleRepository(),
    notes: notesOverride,
    moments: InMemoryMomentRepository(),
    workouts: InMemoryWorkoutRepository(),
    university: InMemoryUniversityRepository(),
    diet: InMemoryDietRepository(),
    ai: FakeAiRepository(),
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('Notes list renders items from the repository', (tester) async {
    final notes = InMemoryNoteRepository();
    addTearDown(notes.dispose);

    await tester.pumpWidget(
      _wrap(child: const NotesListPage(), notesOverride: notes),
    );
    await tester.pump();

    // Seeded notes render.
    expect(find.text('Project ideas'), findsOneWidget);

    await notes.add(
      Note(id: 'new', title: 'Groceries', body: 'Milk, eggs', updatedAt: DateTime.now()),
    );
    await tester.pump();

    expect(find.text('Groceries'), findsOneWidget);
  });

  testWidgets('the FAB opens the capture page for a new note', (tester) async {
    final notes = InMemoryNoteRepository();
    addTearDown(notes.dispose);

    await tester.pumpWidget(
      _wrap(child: const NotesListPage(), notesOverride: notes),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(NoteCapturePage), findsOneWidget);
    expect(find.text('New note'), findsOneWidget);
  });

  testWidgets('tapping a row opens it for editing, prefilled', (tester) async {
    final notes = InMemoryNoteRepository();
    addTearDown(notes.dispose);

    await tester.pumpWidget(
      _wrap(child: const NotesListPage(), notesOverride: notes),
    );
    await tester.pump();

    await tester.tap(find.text('Project ideas'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteCapturePage), findsOneWidget);
    expect(find.text('Edit note'), findsOneWidget);
    expect(find.text('Project ideas'), findsOneWidget);
    // The icon-only delete control is labelled for screen readers.
    expect(find.byTooltip('Delete note'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('swiping a row deletes it via the repository', (tester) async {
    final notes = InMemoryNoteRepository();
    addTearDown(notes.dispose);
    await notes.add(
      Note(id: 'to-delete', title: 'Temp note', body: 'Delete me', updatedAt: DateTime.now()),
    );

    await tester.pumpWidget(
      _wrap(child: const NotesListPage(), notesOverride: notes),
    );
    await tester.pump();

    expect(notes.current.any((n) => n.id == 'to-delete'), isTrue);

    await tester.drag(find.text('Temp note'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(notes.current.any((n) => n.id == 'to-delete'), isFalse);
  });

  testWidgets('shows a loading spinner before the stream first emits', (
    tester,
  ) async {
    final notes = _PendingNoteRepository();
    addTearDown(notes.dispose);

    await tester.pumpWidget(
      _wrap(child: const NotesListPage(), notesOverride: notes),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No notes yet.'), findsNothing);

    notes.emit([
      Note(
        id: 'n1',
        title: 'Fresh note',
        body: 'Some body text',
        updatedAt: DateTime.now(),
      ),
    ]);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    // Title is distinct from the body so it matches exactly one Text (the row
    // renders both a title and a body preview).
    expect(find.text('Fresh note'), findsOneWidget);
  });

  testWidgets('shows the empty state once the stream settles with no data', (
    tester,
  ) async {
    final notes = _PendingNoteRepository();
    addTearDown(notes.dispose);

    await tester.pumpWidget(
      _wrap(child: const NotesListPage(), notesOverride: notes),
    );

    notes.emit(const []);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No notes yet.'), findsOneWidget);
  });

  testWidgets('shows the error view when the stream errors', (tester) async {
    final notes = _PendingNoteRepository();
    addTearDown(notes.dispose);

    await tester.pumpWidget(
      _wrap(child: const NotesListPage(), notesOverride: notes),
    );

    notes.emitError(Exception('read denied'));
    await tester.pump();

    // Error is distinct from both loading and the calm empty state.
    expect(find.byType(ErrorStateView), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No notes yet.'), findsNothing);
  });
}
