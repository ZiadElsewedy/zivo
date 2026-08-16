import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/capture/presentation/widgets/capture_widgets.dart';

void main() {
  testWidgets(
    'CaptureIconButton is labelled, meets the 44px target, and fires onTap',
    (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CaptureIconButton(
                icon: Icons.delete_outline_rounded,
                onTap: () => tapped = true,
                semanticLabel: 'Delete note',
              ),
            ),
          ),
        ),
      );

      // The icon-only control carries a screen-reader label (also a tooltip).
      expect(find.byTooltip('Delete note'), findsOneWidget);

      // The tap target meets the accessible minimum even though the visible
      // chip stays 34px.
      final size = tester.getSize(find.byType(CaptureIconButton));
      expect(size.width, CaptureIconButton.targetSize);
      expect(size.height, CaptureIconButton.targetSize);

      await tester.tap(find.byType(CaptureIconButton));
      expect(tapped, isTrue);
    },
  );
}
