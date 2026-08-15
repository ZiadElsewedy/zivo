import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/auth_failure.dart';
import 'package:zivo/features/auth/domain/auth_result.dart';
import 'package:zivo/features/auth/presentation/pages/auth_page.dart';
import 'package:zivo/features/auth/presentation/widgets/auth_action_button.dart';

import '../support/fake_auth_repository.dart';
import '../support/test_app.dart';

void main() {
  Future<FakeAuthRepository> pumpAuthPage(WidgetTester tester) async {
    final auth = FakeAuthRepository();
    addTearDown(auth.dispose);
    await tester.pumpWidget(wrapWithScope(const AuthPage(), auth: auth));
    await tester.pumpAndSettle(); // drain RiseIn entrance timers
    return auth;
  }

  testWidgets('renders all three sign-in methods', (tester) async {
    await pumpAuthPage(tester);
    expect(find.text('Sign in with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget); // email submit
    expect(find.byType(TextField), findsNWidgets(2)); // email + password
  });

  testWidgets('toggling to create-account reveals the name field', (tester) async {
    await pumpAuthPage(tester);
    await tester.tap(find.byType(TextButton)); // "New to ZIVO? Create account"
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
    // name + email + password + confirm password
    expect(find.byType(TextField), findsNWidgets(4));
  });

  testWidgets('email sign-in failure surfaces the error message',
      (tester) async {
    final auth = await pumpAuthPage(tester);
    auth.emailSignInResult = const AuthFailed(
      AuthFailure(AuthFailureKind.wrongPassword, 'Email or password is incorrect.'),
    );

    await tester.enterText(find.byType(TextField).at(0), 'a@b.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret123');
    await tester.pump();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
  });

  testWidgets('provider cancellation shows no error', (tester) async {
    final auth = await pumpAuthPage(tester);
    auth.googleResult = const AuthCancelled();

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });

  testWidgets('AuthActionButton shows a spinner and blocks taps while loading',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthActionButton(
            label: 'Busy',
            icon: const Icon(Icons.apple),
            loading: true,
            onTap: () => taps++,
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(AuthActionButton));
    expect(taps, 0);
  });
}
