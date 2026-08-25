import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/auth/presentation/pages/privacy_page.dart';
import 'package:zivo/features/auth/presentation/pages/settings_page.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('PrivacyPage renders every policy section', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PrivacyPage()));
    await tester.pumpAndSettle(); // drain RiseIn entrance timers

    expect(find.text('Privacy'), findsOneWidget);
    // Spot-check the section labels, including the newer ones.
    expect(find.text('THE SHORT VERSION'), findsOneWidget);
    expect(find.text('AI ASSISTANT (“ASK”)'), findsOneWidget);
    expect(find.text('ACCOUNT & SECURITY METADATA'), findsOneWidget);
    expect(find.text('GOOGLE DRIVE BACKUP'), findsOneWidget);
    expect(find.text('CONTACT'), findsOneWidget);

    // The short-version bullets render as content.
    expect(find.textContaining('never sold or shared'), findsOneWidget);
  });

  testWidgets('Settings About links to the privacy page', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrapWithScope(const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Privacy policy'), findsOneWidget);

    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPage), findsOneWidget);
    expect(find.text('OVERVIEW'), findsOneWidget);
  });
}
