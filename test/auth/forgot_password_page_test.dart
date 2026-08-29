import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/auth_failure.dart';
import 'package:zivo/features/auth/domain/otp_result.dart';
import 'package:zivo/features/auth/presentation/pages/forgot_password_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/test_app.dart';

void main() {
  // A tall viewport so the (fairly long) code step fits without scrolling, and
  // a real clock: the resend cooldown uses Timer.periodic, so tests advance
  // with fixed `pump` durations rather than `pumpAndSettle` (which would hang
  // on the never-settling periodic timer).
  Future<FakeAuthRepository> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      wrapWithScope(const ForgotPasswordPage(), auth: auth),
    );
    await tester.pump(const Duration(milliseconds: 350)); // flush RiseIn
    return auth;
  }

  // Advance past an async action + its setState + the next step's RiseIn,
  // without waiting on the cooldown's periodic timer.
  Future<void> step(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  // Dispose the page so its cooldown timer is cancelled before the test ends.
  Future<void> teardownPage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('email step sends a code and advances to the code step',
      (tester) async {
    final auth = await pumpPage(tester);

    await tester.enterText(find.byType(TextField), 'me@zivo.app');
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await step(tester);

    expect(auth.sendResetOtpCount, 1);
    expect(auth.resetEmails.single, 'me@zivo.app');
    expect(find.text('Enter the code'), findsOneWidget);

    await teardownPage(tester);
  });

  testWidgets('a valid code + new password resets without signing in',
      (tester) async {
    final auth = await pumpPage(tester);

    await tester.enterText(find.byType(TextField), 'me@zivo.app');
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await step(tester);

    // Code step: [OTP field, new password, confirm password].
    await tester.enterText(find.byType(TextField).at(0), '123456');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'Password1');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(2), 'Password1');
    await tester.pump();

    await tester.tap(find.text('Reset password'));
    await step(tester);

    expect(auth.verifiedCodes.last, '123456');
    // A reset sets the credential only — the user goes back to sign in with it.
    expect(auth.currentUser, isNull);

    await teardownPage(tester);
  });

  testWidgets('a wrong code surfaces the remaining-attempts message',
      (tester) async {
    final auth = await pumpPage(tester);
    auth.resetPasswordResult = const OtpVerifyInvalid(attemptsRemaining: 3);

    await tester.enterText(find.byType(TextField), 'me@zivo.app');
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await step(tester);

    await tester.enterText(find.byType(TextField).at(0), '000000');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'Password1');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(2), 'Password1');
    await tester.pump();
    await tester.tap(find.text('Reset password'));
    await step(tester);

    expect(find.textContaining('3 tries left'), findsOneWidget);
    expect(auth.currentUser, isNull); // not signed in on failure

    await teardownPage(tester);
  });

  testWidgets('a send failure keeps the user on the email step', (tester) async {
    final auth = await pumpPage(tester);
    auth.sendResetOtpResult = const OtpSendFailed(
      AuthFailure(AuthFailureKind.networkError, 'Network error.'),
    );

    await tester.enterText(find.byType(TextField), 'me@zivo.app');
    await tester.pump();
    await tester.tap(find.text('Send code'));
    await step(tester);

    expect(find.text('Network error.'), findsOneWidget);
    expect(find.text('Enter the code'), findsNothing);

    await teardownPage(tester);
  });
}
