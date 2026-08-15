import 'package:flutter_test/flutter_test.dart';

import 'package:zivo/app/app.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';

import 'support/fake_auth_repository.dart';

void main() {
  testWidgets('Today renders the greeting and key sections when authenticated',
      (tester) async {
    // Boot the app with a pre-authenticated fake so the gate shows the shell
    // (Today) rather than the auth screen, and Firebase is never touched.
    await tester.pumpWidget(
      ZivoApp(
        auth: FakeAuthRepository(
          initial: const Authenticated(AuthUser(uid: 'test-uid')),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Morning, Ziad'), findsOneWidget);
    expect(find.text('Data Structures'), findsOneWidget);
    expect(find.text('Chest · Shoulders · Triceps'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('TODAY'), findsWidgets); // section label + tab
  });
}
