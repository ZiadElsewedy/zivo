import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/auth/presentation/pages/profile_completion_page.dart';
import 'package:zivo/features/auth/presentation/widgets/auth_action_button.dart';

import '../support/fake_profile_repository.dart';
import '../support/test_app.dart';

void main() {
  const user = AuthUser(uid: 'u1', displayName: 'Fallback Name');

  Opacity submitOpacity(WidgetTester tester) => tester.widget<Opacity>(
        find.descendant(
          of: find.byType(AuthActionButton),
          matching: find.byType(Opacity),
        ),
      );

  bool submitEnabled(WidgetTester tester) => submitOpacity(tester).opacity == 1;

  /// Opens the shared DOB wheel and confirms its default selection via the
  /// sheet's 'Save' action — deterministic without scrolling a wheel. With no
  /// prior date the wheel opens at 1 January of (now − 25y) (the shared DOB
  /// sheet's mid-range default), so that's what a straight Save commits.
  Future<DateTime> pickDob(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.cake_outlined));
    await tester.pumpAndSettle();
    final expected = DateTime(DateTime.now().year - 25, 1, 1);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    return expected;
  }

  testWidgets('name is prefilled from suggestedName', (tester) async {
    await tester.pumpWidget(
      wrapWithScope(
        const ProfileCompletionPage(user: user, suggestedName: 'Ziad'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ziad'), findsOneWidget);
  });

  testWidgets('name falls back to displayName when suggestedName is null or empty',
      (tester) async {
    await tester.pumpWidget(
      wrapWithScope(const ProfileCompletionPage(user: user)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fallback Name'), findsOneWidget);

    await tester.pumpWidget(
      wrapWithScope(
        const ProfileCompletionPage(user: user, suggestedName: ''),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fallback Name'), findsOneWidget);
  });

  testWidgets('submit is disabled without a DOB, even with a name',
      (tester) async {
    await tester.pumpWidget(
      wrapWithScope(
        const ProfileCompletionPage(user: user, suggestedName: 'Ziad'),
      ),
    );
    await tester.pumpAndSettle();

    expect(submitEnabled(tester), isFalse);
  });

  testWidgets('submit is disabled with a DOB but a blank name', (tester) async {
    await tester.pumpWidget(
      wrapWithScope(
        const ProfileCompletionPage(user: AuthUser(uid: 'u1')),
      ),
    );
    await tester.pump();

    await pickDob(tester);

    expect(submitEnabled(tester), isFalse);
  });

  testWidgets(
      'submit enables once name + DOB are set, and saves them on tap',
      (tester) async {
    final profiles = FakeProfileRepository();
    addTearDown(profiles.dispose);

    await tester.pumpWidget(
      wrapWithScope(
        const ProfileCompletionPage(user: user, suggestedName: 'Ziad'),
        profiles: profiles,
      ),
    );
    await tester.pump();

    final expectedDob = await pickDob(tester);
    expect(submitEnabled(tester), isTrue);

    await tester.tap(find.byType(AuthActionButton));
    await tester.pump();
    await tester.pump();

    expect(profiles.lastSaved?.uid, 'u1');
    expect(profiles.lastSaved?.name, 'Ziad');
    expect(profiles.lastSaved?.dateOfBirth, expectedDob);
  });

  testWidgets('a save failure shows an inline error and does not crash',
      (tester) async {
    final profiles = FakeProfileRepository()..saveProfileError = Exception('boom');
    addTearDown(profiles.dispose);

    await tester.pumpWidget(
      wrapWithScope(
        const ProfileCompletionPage(user: user, suggestedName: 'Ziad'),
        profiles: profiles,
      ),
    );
    await tester.pump();

    await pickDob(tester);
    await tester.tap(find.byType(AuthActionButton));
    await tester.pump();
    await tester.pump();

    expect(
      find.text("We couldn't save your profile. Please try again."),
      findsOneWidget,
    );
  });
}
