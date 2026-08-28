/// A hue from the app's fixed 5-color brand palette (see `AppColors`). Every
/// category — built-in or user-created — picks one instead of an arbitrary
/// color, so custom categories still look native to the design system.
enum CategoryHue { ember, pulse, solar, iris, flare }

/// The mark a category is shown with, from a fixed vocabulary.
///
/// A *semantic* name rather than a glyph, for two reasons. It persists as a
/// stable string (`.name`, the same convention [CategoryHue] already uses), so
/// the stored value survives an icon being re-drawn or swapped for a better
/// one. And it keeps the domain free of Flutter types — the actual stroked
/// glyph is resolved in the presentation layer by `categoryIcon()`, next to
/// where `hueColor()` resolves the colour.
///
/// This replaced a free-text `emoji` field. The identity spec rules emoji out
/// twice (§4 "icons are stroked SVG… never emoji", §8 "Never: emoji"): they
/// render differently on every OS and break the app's otherwise-custom feel.
enum CategoryIcon {
  food,
  coffee,
  transport,
  groceries,
  shopping,
  entertainment,
  home,
  health,
  education,
  travel,
  pets,
  gifts,
  utilities,
  phone,
  games,
  drinks,
  car,
  fitness,
  books,
  grooming,
  music,
  parking,
  bills,
  personalCare,

  /// The neutral mark — the "Other" built-in, and the fallback for a stored
  /// value this build doesn't recognise.
  other,
}

/// An expense category: a small, user-extensible tag. Built-ins ship with the
/// app (see [kBuiltInCategories]); the rest are created by the user and
/// persisted via `CategoryRepository`. Money is Solar throughout, but each
/// category still carries its own hue for quick visual scanning.
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.hue,
  });

  final String id;
  final String label;
  final CategoryIcon icon;
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
  ExpenseCategory(
    id: 'food',
    label: 'Food',
    icon: CategoryIcon.food,
    hue: CategoryHue.ember,
  ),
  ExpenseCategory(
    id: 'coffee',
    label: 'Coffee',
    icon: CategoryIcon.coffee,
    hue: CategoryHue.solar,
  ),
  ExpenseCategory(
    id: 'transport',
    label: 'Transport',
    icon: CategoryIcon.transport,
    hue: CategoryHue.iris,
  ),
  ExpenseCategory(
    id: 'groceries',
    label: 'Groceries',
    icon: CategoryIcon.groceries,
    hue: CategoryHue.pulse,
  ),
  ExpenseCategory(
    id: 'shopping',
    label: 'Shopping',
    icon: CategoryIcon.shopping,
    hue: CategoryHue.flare,
  ),
  ExpenseCategory(
    id: 'other',
    label: 'Other',
    icon: CategoryIcon.other,
    hue: CategoryHue.solar,
  ),
];

const _fallback = ExpenseCategory(
  id: 'other',
  label: 'Other',
  icon: CategoryIcon.other,
  hue: CategoryHue.solar,
);

/// Resolves a stored icon name back to a [CategoryIcon], falling back to
/// [CategoryIcon.other] for anything this build doesn't know — a value written
/// by a newer build, or a corrupted field.
CategoryIcon categoryIconFromName(Object? name) {
  for (final icon in CategoryIcon.values) {
    if (icon.name == name) return icon;
  }
  return CategoryIcon.other;
}

/// Reads a **legacy** category document's `emoji` field as a [CategoryIcon].
///
/// Categories created before the emoji-to-stroked-icon change stored a literal
/// emoji and no icon name. Rather than showing every one of them as the
/// neutral mark, the emoji the picker actually offered are mapped back to the
/// icon that replaced them; anything else (an emoji typed by hand, an empty
/// field) lands on [CategoryIcon.other].
///
/// Read-only and additive: nothing writes `emoji` any more, so this exists
/// purely so already-saved categories keep their identity. It can be deleted
/// once no live account holds a pre-migration category.
CategoryIcon categoryIconFromLegacyEmoji(Object? emoji) =>
    switch (emoji) {
      '🍔' => CategoryIcon.food,
      '☕' => CategoryIcon.coffee,
      '🚕' => CategoryIcon.transport,
      '🛒' => CategoryIcon.groceries,
      '🛍️' => CategoryIcon.shopping,
      '🎬' => CategoryIcon.entertainment,
      '🏠' => CategoryIcon.home,
      '💊' => CategoryIcon.health,
      '🎓' => CategoryIcon.education,
      '✈️' => CategoryIcon.travel,
      '🐾' => CategoryIcon.pets,
      '🎁' => CategoryIcon.gifts,
      '💡' => CategoryIcon.utilities,
      '📱' => CategoryIcon.phone,
      '🎮' => CategoryIcon.games,
      '🍺' => CategoryIcon.drinks,
      '🚗' => CategoryIcon.car,
      '🏋️' => CategoryIcon.fitness,
      '📚' => CategoryIcon.books,
      '💇' => CategoryIcon.grooming,
      '🎵' => CategoryIcon.music,
      '🅿️' => CategoryIcon.parking,
      '🧾' => CategoryIcon.bills,
      '🧴' => CategoryIcon.personalCare,
      _ => CategoryIcon.other,
    };

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
