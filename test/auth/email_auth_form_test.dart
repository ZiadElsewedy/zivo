import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/presentation/widgets/auth_action_button.dart';
import 'package:zivo/features/auth/presentation/widgets/email_auth_form.dart';

import '../support/test_app.dart';

void main() {
  bool isEnabled(WidgetTester tester) =>
      tester.widget<AuthActionButton>(find.byType(AuthActionButton)).enabled;

  group('sign-up mode', () {
    Future<void> pumpSignUp(WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithScope(
          Scaffold(
            body: EmailAuthForm(
              isSignUp: true,
              submitting: false,
              enabled: true,
              onSubmit: ({required email, required password, name}) {},
            ),
          ),
        ),
      );
    }

    testWidgets('renders a confirm-password field', (tester) async {
      await pumpSignUp(tester);
      // name + email + password + confirm password
      expect(find.byType(TextField), findsNWidgets(4));
    });

    testWidgets('disabled with a weak password', (tester) async {
      await pumpSignUp(tester);
      await tester.enterText(find.byType(TextField).at(1), 'a@b.com');
      await tester.enterText(find.byType(TextField).at(2), 'abc');
      await tester.enterText(find.byType(TextField).at(3), 'abc');
      await tester.pump();

      expect(isEnabled(tester), isFalse);
    });

    testWidgets('disabled when confirm does not match a strong password',
        (tester) async {
      await pumpSignUp(tester);
      await tester.enterText(find.byType(TextField).at(1), 'a@b.com');
      await tester.enterText(find.byType(TextField).at(2), 'Passw0rd');
      await tester.enterText(find.byType(TextField).at(3), 'Passw0rx');
      await tester.pump();

      expect(isEnabled(tester), isFalse);
      expect(find.text("Passwords don't match"), findsOneWidget);
    });

    testWidgets('enabled with a valid email, strong password, and matching confirm',
        (tester) async {
      await pumpSignUp(tester);
      await tester.enterText(find.byType(TextField).at(1), 'a@b.com');
      await tester.enterText(find.byType(TextField).at(2), 'Passw0rd');
      await tester.enterText(find.byType(TextField).at(3), 'Passw0rd');
      await tester.pump();

      expect(isEnabled(tester), isTrue);
      expect(find.text('Passwords match'), findsOneWidget);
    });
  });

  group('sign-in mode', () {
    Future<void> pumpSignIn(WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithScope(
          Scaffold(
            body: EmailAuthForm(
              isSignUp: false,
              submitting: false,
              enabled: true,
              onSubmit: ({required email, required password, name}) {},
            ),
          ),
        ),
      );
    }

    testWidgets('has no confirm-password field or checklist', (tester) async {
      await pumpSignIn(tester);
      expect(find.byType(TextField), findsNWidgets(2)); // email + password
      expect(find.text('Confirm password'), findsNothing);
    });

    testWidgets('enables with email + 6-char password (unchanged behaviour)',
        (tester) async {
      await pumpSignIn(tester);
      await tester.enterText(find.byType(TextField).at(0), 'a@b.com');
      await tester.enterText(find.byType(TextField).at(1), 'abc123');
      await tester.pump();

      expect(isEnabled(tester), isTrue);
    });
  });
}
