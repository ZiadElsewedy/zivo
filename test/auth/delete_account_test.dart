import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/auth/presentation/pages/settings_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/test_app.dart';

void main() {
  Future<FakeAuthRepository> openSettings(
    WidgetTester tester, {
    required List<String> providerIds,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeAuthRepository(
      initial: Authenticated(
        AuthUser(uid: 'u1', email: 'me@zivo.app', providerIds: providerIds),
      ),
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      wrapWithScope(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
                child: const Text('open settings'),
              ),
            ),
          ),
        ),
        auth: auth,
      ),
    );
    await tester.tap(find.text('open settings'));
    await tester.pumpAndSettle();
    return auth;
  }

  testWidgets('Change password row is hidden for social-only accounts',
      (tester) async {
    await openSettings(tester, providerIds: const ['google.com']);
    expect(find.text('Change password'), findsNothing);
    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets('Change password row is shown for password accounts',
      (tester) async {
    await openSettings(tester, providerIds: const ['password']);
    expect(find.text('Change password'), findsOneWidget);
  });

  testWidgets('deleting a password account confirms, calls the repo, and exits',
      (tester) async {
    final auth = await openSettings(tester, providerIds: const ['password']);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    // The sheet requires the password to reauthenticate.
    await tester.enterText(find.byType(TextField), 'OldPass1');
    await tester.pump();
    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();

    expect(auth.deleteAccountCount, 1);
    // On success the whole stack pops back past Settings to the host route.
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('open settings'), findsOneWidget);
  });
}
