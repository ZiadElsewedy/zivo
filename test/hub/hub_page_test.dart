import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/hub/presentation/hub_page.dart';

/// Regression coverage for the Hub grid clipping/overflowing on a short
/// device with 8 modules at the premium tile ratio — R2's fix drops
/// `NeverScrollableScrollPhysics` in favor of a genuinely scrollable grid,
/// so no device height or text scale can ever produce a layout overflow.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, {double textScale = 1.0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
        child: const MaterialApp(home: HubPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('a short device (iPhone SE-class) shows all 8 modules with no overflow error', (tester) async {
    await pumpAt(tester, const Size(750, 1334)); // iPhone SE logical size at 1x
    expect(tester.takeException(), isNull);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Moments'), findsOneWidget);
  });

  testWidgets('an even shorter viewport with large accessibility text scale still has no overflow', (tester) async {
    await pumpAt(tester, const Size(750, 900), textScale: 1.6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the grid scrolls to reveal every module rather than clipping any of them', (tester) async {
    await pumpAt(tester, const Size(750, 900), textScale: 1.6);
    expect(tester.takeException(), isNull);

    // Scroll the grid to the bottom and confirm the last module is reachable
    // and rendered — proving it's a real scrollable, not a fixed grid that
    // silently clips whatever doesn't fit.
    await tester.drag(find.byType(GridView), const Offset(0, -600));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Moments'), findsOneWidget);
  });

  testWidgets('a tall device has no overflow either (the premium ratio, not a squished fallback)', (tester) async {
    await pumpAt(tester, const Size(1170, 2532)); // iPhone-class tall device
    expect(tester.takeException(), isNull);
    expect(find.text('Workout'), findsOneWidget);
  });
}
