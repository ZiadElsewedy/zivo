import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/sleep/presentation/widgets/sleep_axis.dart';

/// The axis is the frame both sleep charts are read against, so a label that
/// collides with its neighbour makes the chart unreadable rather than untidy.
void main() {
  /// The narrowest chart the app draws: a small phone's page width, less the
  /// screen padding and the day-name column the weekly raster reserves.
  const narrowest = 210.0;

  Future<List<Rect>> labelRects(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: const SleepAxisLabels()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => tester.getRect(find.text(t.data!)))
        .toList();
  }

  testWidgets('its labels do not collide at the narrowest width the app '
      'draws', (tester) async {
    // They used to: seven clock times at ~54pt each want 378pt of width on a
    // chart that has ~235, and the axis rendered as one run —
    // "6:00 PM9:00 P1M2:00 A3M:00 AM…".
    final rects = await labelRects(tester, narrowest);
    expect(rects.length, SleepAxis.labelHours.length);

    for (var i = 1; i < rects.length; i++) {
      expect(
        rects[i].left,
        greaterThanOrEqualTo(rects[i - 1].right),
        reason:
            'label $i overlaps the one before it: ${rects[i - 1]} / '
            '${rects[i]}',
      );
    }
  });

  testWidgets('it labels every six hours and rules every three', (
    tester,
  ) async {
    // The rhythm survives the thinning — the grid still carries the 3-hour
    // beat that the labels can no longer afford to name.
    expect(SleepAxis.gridHours, [18, 21, 0, 3, 6, 9, 12]);
    expect(SleepAxis.labelHours, [18, 0, 6, 12]);
    for (final hour in SleepAxis.labelHours) {
      expect(SleepAxis.gridHours, contains(hour));
    }
  });

  testWidgets('the end labels stay inside the frame', (tester) async {
    final rects = await labelRects(tester, narrowest);
    final frame = tester.getRect(find.byType(SleepAxisLabels));
    expect(rects.first.left, greaterThanOrEqualTo(frame.left - 0.5));
    expect(rects.last.right, lessThanOrEqualTo(frame.right + 0.5));
  });
}
