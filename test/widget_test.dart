import 'package:flutter_test/flutter_test.dart';

import 'package:zivo/app/app.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';

import 'support/fake_auth_repository.dart';
import 'support/fake_profile_repository.dart';

void main() {
  testWidgets('Today renders the greeting and key sections when authenticated',
      (tester) async {
    // Boot the app with a pre-authenticated fake so the gate shows the shell
    // (Today) rather than the auth screen, and Firebase is never touched. A
    // fake profile repo (complete by default) keeps Firestore out of the test.
    await tester.pumpWidget(
      ZivoApp(
        auth: FakeAuthRepository(
          initial: const Authenticated(AuthUser(uid: 'test-uid')),
        ),
        profiles: FakeProfileRepository(),
      ),
    );
    await tester.pumpAndSettle(); // profile stream resolves, then RiseIn timers

    expect(find.text('Morning, Ziad'), findsOneWidget);
    expect(find.text('Data Structures'), findsOneWidget);
    expect(find.text('Chest · Shoulders · Triceps'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('TODAY'), findsWidgets); // section label + tab
  });
}
