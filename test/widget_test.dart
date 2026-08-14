import 'package:flutter_test/flutter_test.dart';

import 'package:zivo/app/app.dart';

void main() {
  testWidgets('Today renders the greeting and key sections', (tester) async {
    await tester.pumpWidget(const ZivoApp());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Morning, Ziad'), findsOneWidget);
    expect(find.text('Data Structures'), findsOneWidget);
    expect(find.text('Chest · Shoulders · Triceps'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('TODAY'), findsWidgets); // section label + tab
  });
}
