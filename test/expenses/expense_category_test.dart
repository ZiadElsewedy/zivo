import 'package:flutter_test/flutter_test.dart';
import 'package:zivo/features/expenses/domain/expense_category.dart';

void main() {
  group('resolveCategory', () {
    test('resolves a built-in id', () {
      expect(resolveCategory('coffee', const []).label, 'Coffee');
    });

    test('resolves a custom category by id', () {
      const custom = ExpenseCategory(
        id: 'subs',
        label: 'Subscriptions',
        emoji: '📺',
        hue: CategoryHue.iris,
      );
      expect(resolveCategory('subs', [custom]), custom);
    });

    test('falls back to the generic "Other" styling for an unknown id', () {
      final resolved = resolveCategory('ghost', const []);
      expect(resolved.id, 'other');
      expect(resolved.label, 'Other');
    });
  });
}
