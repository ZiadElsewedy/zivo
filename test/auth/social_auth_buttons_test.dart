import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/presentation/widgets/social_auth_buttons.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  // These exercise the widget's `showApple` gate directly (the platform check
  // that computes it lives in AuthPage and is covered by auth_page_test).
  testWidgets('Apple button is hidden when showApple is false', (tester) async {
    await tester.pumpWidget(
      wrap(
        SocialAuthButtons(
          inFlight: AuthAction.none,
          onApple: () {},
          onGoogle: () {},
          showApple: false,
        ),
      ),
    );

    expect(find.text('Sign in with Apple'), findsNothing);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('Apple and Google buttons both render when showApple is true',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        SocialAuthButtons(
          inFlight: AuthAction.none,
          onApple: () {},
          onGoogle: () {},
        ),
      ),
    );

    expect(find.text('Sign in with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
