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
        icon: CategoryIcon.entertainment,
      );
      expect(resolveCategory('subs', [custom]), custom);
    });

    test('falls back to the generic "Other" styling for an unknown id', () {
      final resolved = resolveCategory('ghost', const []);
      expect(resolved.id, 'other');
      expect(resolved.label, 'Other');
    });
  });

  group('categoryIconFromName', () {
    test('round-trips every icon through its persisted name', () {
      for (final icon in CategoryIcon.values) {
        expect(categoryIconFromName(icon.name), icon);
      }
    });

    test('falls back to other for an unknown or non-string value', () {
      expect(categoryIconFromName('teleporter'), CategoryIcon.other);
      expect(categoryIconFromName(null), CategoryIcon.other);
      expect(categoryIconFromName(7), CategoryIcon.other);
    });
  });

  group('categoryIconFromLegacyEmoji', () {
    // Categories saved before the emoji-to-stroked-icon change store an emoji
    // and no icon name; they must keep their mark rather than all collapsing
    // onto the neutral one.
    test('maps a legacy emoji the picker used to offer', () {
      expect(categoryIconFromLegacyEmoji('🍔'), CategoryIcon.food);
      expect(categoryIconFromLegacyEmoji('🧾'), CategoryIcon.bills);
      expect(categoryIconFromLegacyEmoji('🅿️'), CategoryIcon.parking);
    });

    test('maps every built-in category emoji it shipped with', () {
      expect(categoryIconFromLegacyEmoji('☕'), CategoryIcon.coffee);
      expect(categoryIconFromLegacyEmoji('🚕'), CategoryIcon.transport);
      expect(categoryIconFromLegacyEmoji('🛒'), CategoryIcon.groceries);
      expect(categoryIconFromLegacyEmoji('🛍️'), CategoryIcon.shopping);
    });

    test('falls back to other for a hand-typed, empty or absent emoji', () {
      expect(categoryIconFromLegacyEmoji('🦄'), CategoryIcon.other);
      expect(categoryIconFromLegacyEmoji(''), CategoryIcon.other);
      expect(categoryIconFromLegacyEmoji(null), CategoryIcon.other);
    });
  });
}
