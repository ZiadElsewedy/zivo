import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/otp_result.dart';
import 'package:zivo/features/auth/domain/auth_failure.dart';
import 'package:zivo/features/auth/presentation/pages/verify_email_page.dart';
import 'package:zivo/features/auth/presentation/widgets/auth_action_button.dart';

import '../support/fake_auth_repository.dart';
import '../support/test_app.dart';

void main() {
  // Tears the page down so its timers/animations don't linger. Flushes the
  // RiseIn entrance delays (Future.delayed timers) first, then disposes.
  Future<void> teardownPage(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('sends a code on open and masks the email', (tester) async {
    final auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    // No cooldown timer for a clean teardown.
    auth.sendOtpResult =
        const OtpSendFailed(AuthFailure(AuthFailureKind.unknown, 'x'));

    await tester.pumpWidget(
      wrapWithScope(const VerifyEmailPage(email: 'ziad@example.com'), auth: auth),
    );
    await tester.pump(); // run the post-frame auto-send

    expect(auth.sendOtpCount, 1);
    expect(find.text('Verify your email'), findsOneWidget);
    // Masked: first two chars visible, domain intact.
    expect(find.textContaining('zi'), findsWidgets);
    expect(find.textContaining('@example.com'), findsOneWidget);

    await teardownPage(tester);
  });

  testWidgets('entering 6 digits auto-submits and passes the code through',
      (tester) async {
    final auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    auth.sendOtpResult =
        const OtpSendFailed(AuthFailure(AuthFailureKind.unknown, 'x'));
    auth.verifyOtpResult = const OtpVerifySuccess();

    await tester.pumpWidget(
      wrapWithScope(const VerifyEmailPage(email: 'ziad@example.com'), auth: auth),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();

    expect(auth.verifiedCodes, ['123456']);

    await teardownPage(tester);
  });

  testWidgets('an invalid code shows an error with remaining attempts',
      (tester) async {
    final auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    auth.sendOtpResult =
        const OtpSendFailed(AuthFailure(AuthFailureKind.unknown, 'x'));
    auth.verifyOtpResult = const OtpVerifyInvalid(attemptsRemaining: 3);

    await tester.pumpWidget(
      wrapWithScope(const VerifyEmailPage(email: 'ziad@example.com'), auth: auth),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump(); // verify call
    await tester.pump(); // setState after result

    expect(find.textContaining('3 tries left'), findsOneWidget);

    await teardownPage(tester);
  });

  testWidgets('Verify button is disabled below 6 digits and enabled at 6',
      (tester) async {
    final auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    auth.sendOtpResult =
        const OtpSendFailed(AuthFailure(AuthFailureKind.unknown, 'x'));

    await tester.pumpWidget(
      wrapWithScope(const VerifyEmailPage(email: 'ziad@example.com'), auth: auth),
    );
    await tester.pump();

    Opacity opacityOf() => tester.widget<Opacity>(
          find.descendant(
            of: find.byType(AuthActionButton),
            matching: find.byType(Opacity),
          ),
        );

    // No digits yet: disabled.
    expect(opacityOf().opacity, 0.5);

    await tester.enterText(find.byType(TextField), '12345');
    await tester.pump();
    expect(opacityOf().opacity, 0.5);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    expect(opacityOf().opacity, 1);

    await teardownPage(tester);
  });

  testWidgets('a backend email-delivery failure shows the generic copy, not the connection copy',
      (tester) async {
    final auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    auth.sendOtpResult = const OtpSendFailed(
      AuthFailure(
        AuthFailureKind.emailDeliveryFailed,
        "We couldn't send your code right now. Please try again in a moment.",
      ),
    );

    await tester.pumpWidget(
      wrapWithScope(const VerifyEmailPage(email: 'ziad@example.com'), auth: auth),
    );
    await tester.pump();

    expect(
      find.text("We couldn't send your code right now. Please try again in a moment."),
      findsOneWidget,
    );
    expect(find.textContaining('Check your connection'), findsNothing);

    await teardownPage(tester);
  });
}
