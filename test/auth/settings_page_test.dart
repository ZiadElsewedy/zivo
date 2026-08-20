import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/auth/presentation/pages/settings_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/test_app.dart';

void main() {
  testWidgets('signing out pops back past Settings to the first route', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeAuthRepository(
      initial: const Authenticated(AuthUser(uid: 'u1')),
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
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    // Signed out, and popped back off the Settings route to the first route
    // (rather than leaving Settings floating over the sign-in screen).
    expect(auth.signOutCount, 1);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('open settings'), findsOneWidget);
  });
}
