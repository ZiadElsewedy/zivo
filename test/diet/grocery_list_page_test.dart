import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zivo/features/diet/domain/diet_day.dart';
import 'package:zivo/features/diet/domain/diet_plan.dart';
import 'package:zivo/features/diet/domain/diet_plan_status.dart';
import 'package:zivo/features/diet/domain/diet_source.dart';
import 'package:zivo/features/diet/domain/food_item.dart';
import 'package:zivo/features/diet/domain/meal.dart';
import 'package:zivo/features/diet/presentation/pages/grocery_list_page.dart';

DietPlan _plan() => DietPlan(
      id: 'p1',
      name: 'Cut — 2200 kcal',
      status: DietPlanStatus.active,
      source: DietSource.manual,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
      days: [
        const DietDay(label: 'Every day', meals: [
          Meal(id: 'b', label: 'Breakfast', order: 0, items: [
            FoodItem(name: 'Oats', quantity: 60, unit: 'g'),
            FoodItem(name: 'Banana', quantity: 1, unit: 'pcs'),
          ]),
          Meal(id: 'd', label: 'Dinner', order: 1, items: [
            FoodItem(name: 'oats', quantity: 40, unit: 'g'),
          ]),
        ]),
      ],
    );

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(home: GroceryListPage(plan: _plan())),
  );
}

void main() {
  testWidgets('renders the aggregated lines in order', (tester) async {
    await _pump(tester);

    expect(find.text('Banana — 1 pcs'), findsOneWidget);
    expect(find.text('Oats — 100 g'), findsOneWidget);
  });

  testWidgets('ticking a line strikes it through', (tester) async {
    await _pump(tester);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();

    final text = tester.widget<Text>(find.text('Banana — 1 pcs'));
    expect(text.style!.decoration, TextDecoration.lineThrough);
  });

  testWidgets('copy puts the full list on the clipboard', (tester) async {
    // The test binding has no real platform channel — capture the pasteboard
    // through a mock of the framework's own platform channel.
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboard = call.arguments['text'] as String?;
            return null;
          case 'Clipboard.getData':
            return {'text': clipboard};
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _pump(tester);

    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pump();

    expect(clipboard, contains('Groceries — Cut — 2200 kcal'));
    expect(clipboard, contains('• Oats — 100 g'));
    expect(clipboard, contains('• Banana — 1 pcs'));

    // Let the toast's auto-dismiss timer expire so the test ends clean.
    await tester.pumpAndSettle();
  });

  testWidgets('an item-less plan shows the empty state without copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GroceryListPage(
          plan: DietPlan(
            id: 'p2',
            name: 'Empty',
            status: DietPlanStatus.active,
            source: DietSource.manual,
            createdAt: DateTime(2026, 8, 1),
            updatedAt: DateTime(2026, 8, 1),
            days: const [],
          ),
        ),
      ),
    );

    expect(find.text("This plan has no foods to shop for yet."), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
  });
}
