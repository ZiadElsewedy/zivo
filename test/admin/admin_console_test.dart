import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/admin/data/in_memory_admin_repository.dart';
import 'package:zivo/features/admin/domain/admin_models.dart';
import 'package:zivo/features/admin/presentation/admin_shell.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/auth/presentation/auth_gate.dart';
import 'package:zivo/features/shell/presentation/home_shell.dart';

import '../support/fake_auth_repository.dart';
import '../support/test_app.dart';

AdminUserRow _row(
  String uid,
  String name, {
  bool plan = false,
  int workouts = 0,
  AdminAccountStatus status = AdminAccountStatus.active,
}) => AdminUserRow(
  uid: uid,
  displayName: name,
  emailMasked: '${name.substring(0, 2).toLowerCase()}**@example.com',
  createdAt: DateTime.now().subtract(const Duration(days: 40)),
  lastActiveAt: DateTime.now().subtract(const Duration(hours: 2)),
  status: status,
  platform: 'ios',
  appVersion: '1.0.0+1',
  hasWorkoutPlan: plan,
  workoutsCompleted: workouts,
  aiRequests: 3,
  aiTokens: 1200,
  lastEvent: null,
);

FakeAuthRepository _adminAuth() {
  final auth = FakeAuthRepository(
    initial: const Authenticated(
      AuthUser(
        uid: 'admin',
        email: 'admin@zivo.app',
        providerIds: ['password'],
      ),
    ),
  );
  auth.roles = {'admin'};
  return auth;
}

Future<void> _pumpDesktop(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('an admin account is routed to the Admin Console', (
    tester,
  ) async {
    final auth = _adminAuth();
    addTearDown(auth.dispose);
    await _pumpDesktop(
      tester,
      wrapWithScope(
        const AuthGate(),
        auth: auth,
        admin: InMemoryAdminRepository(users: [_row('u1', 'Sara')]),
      ),
    );
    expect(find.byType(AdminShell), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
  });

  testWidgets('a normal account never sees the Admin Console', (tester) async {
    final auth = FakeAuthRepository(
      initial: const Authenticated(AuthUser(uid: 'u1')),
    );
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      wrapWithScope(
        const AuthGate(),
        auth: auth,
        admin: InMemoryAdminRepository(),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AdminShell), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('dashboard shows the headline figures', (tester) async {
    final auth = _adminAuth();
    addTearDown(auth.dispose);
    await _pumpDesktop(
      tester,
      wrapWithScope(
        const AdminShell(),
        auth: auth,
        admin: InMemoryAdminRepository(
          users: [
            _row('u1', 'Sara', plan: true),
            _row('u2', 'Omar'),
            _row('u3', 'Lina', plan: true),
          ],
        ),
      ),
    );
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('active in the last 7 days'), findsOneWidget);
    expect(find.text('Total users'), findsOneWidget);
    expect(find.text('67% of users'), findsOneWidget); // 2 of 3 have a plan
  });

  testWidgets('users table filters, opens a user, and suspends them', (
    tester,
  ) async {
    final auth = _adminAuth();
    addTearDown(auth.dispose);
    final repo = InMemoryAdminRepository(
      users: [_row('u1', 'Sara', plan: true, workouts: 7), _row('u2', 'Omar')],
    );
    await _pumpDesktop(
      tester,
      wrapWithScope(const AdminShell(), auth: auth, admin: repo),
    );

    await tester.tap(find.text('Users').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('Sara'), findsOneWidget);
    expect(find.textContaining('Omar'), findsOneWidget);

    // One filter at a time, applied server-side (here: in memory).
    await tester.tap(find.text('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Has a workout plan').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Sara'), findsOneWidget);
    expect(find.textContaining('Omar'), findsNothing);

    await tester.tap(find.textContaining('Sara'));
    await tester.pumpAndSettle();
    expect(find.text('Manage account'), findsOneWidget);
    expect(find.textContaining('stay private'), findsOneWidget);

    await tester.tap(find.text('Suspend account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspend'));
    await tester.pumpAndSettle();
    final page = await repo.listUsers(const AdminUserQuery());
    expect(
      page.users.firstWhere((u) => u.uid == 'u1').status,
      AdminAccountStatus.disabled,
    );
    expect(find.text('Re-enable account'), findsOneWidget);
  });

  testWidgets('deleting requires the account code and the admin password', (
    tester,
  ) async {
    final auth = _adminAuth();
    addTearDown(auth.dispose);
    final repo = InMemoryAdminRepository(users: [_row('user-abc123', 'Sara')]);
    await _pumpDesktop(
      tester,
      wrapWithScope(const AdminShell(), auth: auth, admin: repo),
    );
    await tester.tap(find.text('Users').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.textContaining('Sara'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't be undone"), findsOneWidget);

    Future<void> tapConfirm() async {
      await tester.tap(find.byKey(const Key('admin-delete-confirm')));
      await tester.pumpAndSettle();
    }

    // Wrong code: the button stays disabled.
    await tester.enterText(find.byKey(const Key('admin-delete-code')), 'nope');
    await tester.enterText(
      find.byKey(const Key('admin-delete-password')),
      'pw',
    );
    await tapConfirm();
    expect(repo.deleted, isEmpty);

    await tester.enterText(
      find.byKey(const Key('admin-delete-code')),
      'abc123',
    );
    await tester.pump();
    await tapConfirm();
    expect(auth.reauthenticateCount, 1); // re-proved before the call
    expect(repo.deleted, ['user-abc123']);
  });

  testWidgets('the console works on a phone-sized screen', (tester) async {
    final auth = _adminAuth();
    addTearDown(auth.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrapWithScope(
        const AdminShell(),
        auth: auth,
        admin: InMemoryAdminRepository(users: [_row('u1', 'Sara')]),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Users'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('Sara'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
