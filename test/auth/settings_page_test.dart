import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/ai/presentation/pages/ask_settings_page.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/features/auth/presentation/pages/settings_page.dart';

import '../support/fake_auth_repository.dart';
import '../support/test_app.dart';

void main() {
  testWidgets('signing out pops back past Settings to the first route', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = FakeAuthRepository(
      initial: const Authenticated(AuthUser(uid: 'u1')),
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      wrapWithScope(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
                child: const Text('open settings'),
              ),
            ),
          ),
        ),
        auth: auth,
      ),
    );

    await tester.tap(find.text('open settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    // Signed out, and popped back off the Settings route to the first route
    // (rather than leaving Settings floating over the sign-in screen).
    expect(auth.signOutCount, 1);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('open settings'), findsOneWidget);
  });

  testWidgets(
    'the AI Model row shows the active model and opens the same picker Ask uses',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final ai = FakeAiRepository();

      await tester.pumpWidget(
        wrapWithScope(const SettingsPage(), ai: ai),
      );
      await tester.pumpAndSettle();

      // Defaults to Claude Sonnet — the row surfaces it without opening Ask.
      // ONE row shows the one selected model; the automatic fallback is never
      // presented as a second active model.
      expect(find.byKey(const Key('settings-ai-model')), findsOneWidget);
      expect(find.text('Claude Sonnet'), findsOneWidget);
      expect(find.text('Gemini Flash'), findsNothing);
      expect(find.textContaining('Haiku'), findsNothing);

      await tester.tap(find.byKey(const Key('settings-ai-model')));
      await tester.pumpAndSettle();

      // Same page the Ask header pushes — not a second implementation.
      expect(find.byType(AskSettingsPage), findsOneWidget);
      // The picker offers exactly the two models, one of them active.
      expect(find.byKey(const Key('model-claude-sonnet')), findsOneWidget);
      expect(find.byKey(const Key('model-gemini-flash')), findsOneWidget);
      expect(find.byKey(const Key('model-claude-haiku')), findsNothing);
      expect(find.textContaining('Haiku'), findsNothing);
      expect(find.text('Active'), findsOneWidget);

      await tester.tap(find.text('Gemini Flash'));
      await tester.pumpAndSettle();
      expect(await ai.getModelSelection(), 'gemini-flash');

      await tester.pageBack();
      await tester.pumpAndSettle();

      // Back on Settings, the row's value reflects the switch made inside.
      expect(find.text('Gemini Flash'), findsOneWidget);
    },
  );
}
