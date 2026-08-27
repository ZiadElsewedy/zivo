import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/auth_failure.dart';
import 'package:zivo/features/auth/domain/auth_result.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/auth/presentation/pages/change_password_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/test_app.dart';

void main() {
  Future<FakeAuthRepository> pushChangePassword(WidgetTester tester) async {
    final auth = FakeAuthRepository(
      initial: const Authenticated(
        AuthUser(uid: 'u1', email: 'me@zivo.app', providerIds: ['password']),
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
                  MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        auth: auth,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return auth;
  }

  testWidgets('submitting a valid change calls the repo and pops back',
      (tester) async {
    final auth = await pushChangePassword(tester);

    // [current, new, confirm].
    await tester.enterText(find.byType(TextField).at(0), 'OldPass1');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'NewPass1');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(2), 'NewPass1');
    await tester.pump();

    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(auth.changePasswordCount, 1);
    expect(find.byType(ChangePasswordPage), findsNothing); // popped back
  });

  testWidgets('a wrong current password shows the error and stays put',
      (tester) async {
    final auth = await pushChangePassword(tester);
    auth.changePasswordResult = const AuthFailed(
      AuthFailure(AuthFailureKind.wrongPassword, 'Email or password is incorrect.'),
    );

    await tester.enterText(find.byType(TextField).at(0), 'WrongPass1');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'NewPass1');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(2), 'NewPass1');
    await tester.pump();

    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(find.byType(ChangePasswordPage), findsOneWidget); // still here
  });
}
