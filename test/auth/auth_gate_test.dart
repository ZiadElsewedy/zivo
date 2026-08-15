import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/auth/presentation/auth_gate.dart';

import '../support/fake_auth_repository.dart';
import '../support/test_app.dart';

void main() {
  testWidgets('gate shows Splash → Auth → Home as state changes',
      (tester) async {
    final auth = FakeAuthRepository(); // starts AuthUnknown
    addTearDown(auth.dispose);

    await tester.pumpWidget(wrapWithScope(const AuthGate(), auth: auth));
    await tester.pump();

    // AuthUnknown → splash (branded loader, no auth screen).
    expect(find.text('Sign in with Apple'), findsNothing);
    expect(find.text('ZIVO'), findsOneWidget);

    // Unauthenticated → auth screen.
    auth.emit(const Unauthenticated());
    await tester.pump(); // rebuild on the new state
    await tester.pump(const Duration(seconds: 1)); // fire + finish entrance timers
    expect(find.text('Sign in with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);

    // Authenticated → app shell (Today).
    auth.emit(const Authenticated(AuthUser(uid: 'u1')));
    await tester.pump(); // rebuild on the new state
    await tester.pump(const Duration(seconds: 1)); // fire + finish entrance timers
    expect(find.text('Morning, Ziad'), findsOneWidget);
    expect(find.text('Sign in with Apple'), findsNothing);
  });
}
