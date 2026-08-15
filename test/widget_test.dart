import 'package:flutter_test/flutter_test.dart';

import 'package:zivo/app/app.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/expenses/data/in_memory_expense_repository.dart';
import 'package:zivo/features/notes/data/in_memory_note_repository.dart';
import 'package:zivo/features/schedule/data/in_memory_schedule_repository.dart';
import 'package:zivo/features/tasks/data/in_memory_task_repository.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_profile_repository.dart';

void main() {
  testWidgets('Today renders the greeting and key sections when authenticated', (
    tester,
  ) async {
    // Boot the app with a pre-authenticated fake so the gate shows the shell
    // (Today) rather than the auth screen, and Firebase is never touched. A
    // fake profile repo (complete by default) keeps Firestore out of the test,
    // and in-memory tasks/expenses/schedule/notes repos override the
    // Firestore-backed defaults so Today's sections render without a live
    // backend.
    await tester.pumpWidget(
      ZivoApp(
        auth: FakeAuthRepository(
          initial: const Authenticated(AuthUser(uid: 'test-uid')),
        ),
        profiles: FakeProfileRepository(),
        tasks: InMemoryTaskRepository(),
        expenses: InMemoryExpenseRepository(),
        schedule: InMemoryScheduleRepository(),
        notes: InMemoryNoteRepository(),
      ),
    );
    await tester.pumpAndSettle(); // profile stream resolves, then RiseIn timers

    expect(find.text('Morning, Ziad'), findsOneWidget);
    expect(find.text('Data Structures'), findsOneWidget);
    expect(find.text('Chest · Shoulders · Triceps'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('TODAY'), findsWidgets); // section label + tab
  });
}
