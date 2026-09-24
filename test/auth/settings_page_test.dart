import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/ai/data/fake_ai_repository.dart';
import 'package:zivo/features/auth/domain/auth_state.dart';
import 'package:zivo/features/auth/domain/auth_user.dart';
import 'package:zivo/core/widgets/settings_row.dart';
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

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'AI lives in Settings as normal rows — Model, Reply style, Usage — with '
    'no separate Ask settings screen',
    (tester) async {
      tall(tester);
      final ai = FakeAiRepository();
      await tester.pumpWidget(wrapWithScope(const SettingsPage(), ai: ai));
      await tester.pumpAndSettle();

      for (final key in const [
        'settings-ai-model',
        'settings-ai-style',
        'settings-ai-usage',
      ]) {
        final row = find.byKey(Key(key));
        expect(row, findsOneWidget);
        expect(tester.widget(row), isA<SettingsRow>());
      }
      // ONE row shows the one selected model; the fallback is never
      // presented as a second active model.
      expect(find.text('Claude Sonnet'), findsOneWidget);
      expect(find.text('Gemini Flash'), findsNothing);
      expect(find.textContaining('Haiku'), findsNothing);
      // The short note, and no usage figures on the main page.
      expect(
        find.text(
          'ZIVO uses your selected model for AI features. If it becomes '
          'temporarily unavailable, ZIVO can continue with the other provider.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('tokens'), findsNothing);
      expect(find.text('Ask settings'), findsNothing);
    },
  );

  testWidgets(
    'the Model row opens the one picker: exactly two models, exactly one '
    'active, and a pick shows back on the row',
    (tester) async {
      tall(tester);
      final ai = FakeAiRepository();
      await tester.pumpWidget(wrapWithScope(const SettingsPage(), ai: ai));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settings-ai-model')));
      await tester.pumpAndSettle();

      // A sheet over Settings — not a pushed settings screen.
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.byKey(const Key('sheet-model-claude-sonnet')), findsOneWidget);
      expect(find.byKey(const Key('sheet-model-gemini-flash')), findsOneWidget);
      expect(find.byKey(const Key('sheet-model-claude-haiku')), findsNothing);
      expect(find.textContaining('Haiku'), findsNothing);
      expect(find.text('Active'), findsOneWidget);

      await tester.tap(find.byKey(const Key('sheet-model-gemini-flash')));
      await tester.pumpAndSettle();
      expect(await ai.getModelSelection(), 'gemini-flash');
      await tester.pumpAndSettle();

      // Sheet closed; the row's value reflects the switch.
      expect(find.byKey(const Key('sheet-model-gemini-flash')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('settings-ai-model')),
          matching: find.text('Gemini Flash'),
        ),
        findsOneWidget,
      );
      expect(find.text('Claude Sonnet'), findsNothing);
    },
  );

  testWidgets('the Reply style row picks and shows the style', (tester) async {
    tall(tester);
    final ai = FakeAiRepository();
    await tester.pumpWidget(wrapWithScope(const SettingsPage(), ai: ai));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-ai-style')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-style-concise')));
    await tester.pumpAndSettle();

    expect(await ai.getResponseStyle(), 'concise');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-ai-style')),
        matching: find.text('Concise'),
      ),
      findsOneWidget,
    );
  });
}
