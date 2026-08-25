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

  testWidgets('Sign in with Apple uses the white style', (tester) async {
    // Per Apple's guidelines' white variant: solid white pill, black mark
    // and black label — matching the Google card's light-on-dark treatment.
    await tester.pumpWidget(
      wrap(
        SocialAuthButtons(
          inFlight: AuthAction.none,
          onApple: () {},
          onGoogle: () {},
        ),
      ),
    );

    final appleMaterial = tester.widget<Material>(
      find.ancestor(
        of: find.text('Sign in with Apple'),
        matching: find.byType(Material),
      ).first,
    );
    expect(appleMaterial.color, Colors.white);

    final appleIcon = tester.widget<Icon>(find.byIcon(Icons.apple));
    expect(appleIcon.color, Colors.black);
  });
}
