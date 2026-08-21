/// A hue from the app's fixed 5-color brand palette (see `AppColors`). Every
/// category — built-in or user-created — picks one instead of an arbitrary
/// color, so custom categories still look native to the design system.
enum CategoryHue { ember, pulse, solar, iris, flare }

/// An expense category: a small, user-extensible tag. Built-ins ship with the
/// app (see [kBuiltInCategories]); the rest are created by the user and
/// persisted via `CategoryRepository`. Money is Solar throughout, but each
/// category still carries its own hue for quick visual scanning.
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.label,
    required this.emoji,
    required this.hue,
  });

  final String id;
  final String label;
  final String emoji;
  final CategoryHue hue;

  @override
  bool operator ==(Object other) => other is ExpenseCategory && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Ships with the app. Ids match the old fixed category set 1:1 so existing
/// expense records (which store a category id string) keep resolving with no
/// migration; `shopping` is the one addition.
const kBuiltInCategories = <ExpenseCategory>[
  ExpenseCategory(id: 'food', label: 'Food', emoji: '🍔', hue: CategoryHue.ember),
  ExpenseCategory(id: 'coffee', label: 'Coffee', emoji: '☕', hue: CategoryHue.solar),
  ExpenseCategory(id: 'transport', label: 'Transport', emoji: '🚕', hue: CategoryHue.iris),
  ExpenseCategory(id: 'groceries', label: 'Groceries', emoji: '🛒', hue: CategoryHue.pulse),
  ExpenseCategory(id: 'shopping', label: 'Shopping', emoji: '🛍️', hue: CategoryHue.flare),
  ExpenseCategory(id: 'other', label: 'Other', emoji: '•', hue: CategoryHue.solar),
];

const _fallback = ExpenseCategory(
  id: 'other',
  label: 'Other',
  emoji: '•',
  hue: CategoryHue.solar,
);

/// Resolves an expense's stored `categoryId` to a displayable [ExpenseCategory]
/// — checking built-ins, then the user's [custom] categories, falling back to
/// the generic "Other" styling for an id that matches neither (e.g. a custom
/// category that was later removed).
ExpenseCategory resolveCategory(String id, List<ExpenseCategory> custom) {
  for (final category in kBuiltInCategories) {
    if (category.id == id) return category;
  }
  for (final category in custom) {
    if (category.id == id) return category;
  }
  return _fallback;
}
