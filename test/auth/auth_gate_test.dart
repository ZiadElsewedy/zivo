import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/auth/presentation/auth_gate.dart';
import 'package:zivo/features/auth/presentation/pages/splash_screen.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';
import '../support/test_app.dart';

void main() {
  testWidgets('gate shows Splash → Auth → Home as state changes',
      (tester) async {
    // Force iOS so the Apple button renders — this test asserts the auth
    // screen's social methods; Apple is intentionally iOS-only elsewhere.
    // Reset synchronously in finally (the debug-var invariant is checked at
    // the end of the body, before any addTearDown runs).
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final auth = FakeAuthRepository(); // starts AuthUnknown
    addTearDown(auth.dispose);
    try {
      await tester.pumpWidget(wrapWithScope(const AuthGate(), auth: auth));
      await tester.pump();

      // AuthUnknown → splash (branded loader, no auth screen).
      expect(find.text('Sign in with Apple'), findsNothing);
      expect(find.byType(SplashScreen), findsOneWidget);

      // Unauthenticated → auth screen.
      auth.emit(const Unauthenticated());
      await tester.pump(); // rebuild on the new state
      await tester.pump(const Duration(seconds: 1)); // fire + finish entrance timers
      expect(find.text('Sign in with Apple'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);

      // AwaitingEmailVerification → the OTP verify screen (not the shell).
      auth.emit(const AwaitingEmailVerification('ziad@example.com'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.text('PULL TO ASK'), findsNothing); // home shell not shown yet

      // Authenticated → app shell (Today).
      auth.emit(const Authenticated(AuthUser(uid: 'u1')));
      await tester.pump(); // rebuild on the new state
      await tester.pump(); // profile stream resolves (complete by default)
      // Not pumpAndSettle — Today's up-next Training card carries a
      // continuous, always-on repeating animation (`AliveColorDrift`) once
      // there's an active plan, which never settles on its own.
      await tester.pump(const Duration(seconds: 1)); // fire + finish entrance timers
      expect(find.text('PULL TO ASK'), findsOneWidget); // home shell (Today)
      expect(find.text('Sign in with Apple'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'Authenticated with no complete profile routes to the completion page',
      (tester) async {
    final auth = FakeAuthRepository();
    final profiles = FakeProfileRepository();
    profiles.setProfile(null);
    addTearDown(auth.dispose);
    addTearDown(profiles.dispose);

    await tester.pumpWidget(
      wrapWithScope(const AuthGate(), auth: auth, profiles: profiles),
    );
    await tester.pump();

    auth.emit(const Authenticated(AuthUser(uid: 'u1', displayName: 'Ziad')));
    await tester.pump();
    await tester.pump(); // profile stream resolves (null → incomplete)
    await tester.pumpAndSettle(); // completion page RiseIn entrance timers

    expect(find.text('Complete your profile'), findsOneWidget);
    expect(find.text('PULL TO ASK'), findsNothing); // home shell not shown
  });

  testWidgets('Authenticated with a complete profile routes to the home shell',
      (tester) async {
    final auth = FakeAuthRepository();
    final profiles = FakeProfileRepository();
    addTearDown(auth.dispose);
    addTearDown(profiles.dispose);

    await tester.pumpWidget(
      wrapWithScope(const AuthGate(), auth: auth, profiles: profiles),
    );
    await tester.pump();

    auth.emit(const Authenticated(AuthUser(uid: 'fake-uid', displayName: 'Ziad')));
    await tester.pump();
    await tester.pump(); // profile stream resolves (complete by default)
    // Not pumpAndSettle — see the sibling test above for why (Today's
    // always-on `AliveColorDrift` never settles on its own).
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('PULL TO ASK'), findsOneWidget); // home shell (Today)
    expect(find.text('Complete your profile'), findsNothing);
  });
}
