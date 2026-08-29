import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/core/theme/app_icons.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/auth/domain/user_profile.dart';
import 'package:zivo/features/auth/presentation/pages/profile_page.dart';
import 'package:zivo/features/auth/presentation/pages/settings_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_profile_repository.dart';
import '../support/test_app.dart';

void main() {
  const user = AuthUser(
    uid: 'u1',
    email: 'ziad@zivo.app',
    displayName: 'Ziad',
    isEmailVerified: true,
  );
  final profile = UserProfile(
    uid: 'u1',
    name: 'Ziad',
    dateOfBirth: DateTime(2000, 5, 4),
  );

  Widget buildPage({UserProfile? initialProfile}) {
    return wrapWithScope(
      const ProfilePage(),
      auth: FakeAuthRepository(initial: Authenticated(user)),
      profiles: FakeProfileRepository(initial: initialProfile ?? profile),
    );
  }

  testWidgets('tapping the settings icon opens SettingsPage', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(AppIcons.settings));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets(
    'About shows a prompt when no bio is set, and the saved bio once one is',
    (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();
      expect(find.text('Add a few words about yourself.'), findsOneWidget);

      await tester.pumpWidget(
        buildPage(
          initialProfile: UserProfile(
            uid: 'u1',
            name: 'Ziad',
            dateOfBirth: profile.dateOfBirth,
            bio: 'Building ZIVO.',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Building ZIVO.'), findsOneWidget);
    },
  );

  testWidgets('editing the bio saves it through the profile repository', (
    tester,
  ) async {
    final profiles = FakeProfileRepository(initial: profile);
    await tester.pumpWidget(
      wrapWithScope(
        const ProfilePage(),
        auth: FakeAuthRepository(initial: Authenticated(user)),
        profiles: profiles,
      ),
    );
    await tester.pumpAndSettle();

    // The prompt itself is the affordance — the ABOUT label sits outside the
    // card now, as a section header like ACCOUNT and SIGN-IN.
    await tester.tap(find.text('Add a few words about yourself.'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Personal OS builder.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(profiles.lastSaved?.bio, 'Personal OS builder.');
    expect(profiles.lastSaved?.name, profile.name);
    expect(find.text('Personal OS builder.'), findsOneWidget);
  });

  testWidgets('sign out is not on the profile page anymore', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Sign out'), findsNothing);
  });
}
