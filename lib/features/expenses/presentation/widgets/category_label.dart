import 'package:flutter/widgets.dart';

import '../../../../l10n/l10n.dart';
import '../../domain/expense_category.dart';

/// A category's name in the reader's language.
///
/// Built-in categories carry an English `label` in the domain because their
/// **id** is what expense records store and what the AI's `log_expense` tool
/// accepts — those must not move. This resolves the id to a translated name
/// for display only.
///
/// A category the user created themselves is returned as they typed it: their
/// words are not ZIVO's to translate.
String categoryLabel(BuildContext context, ExpenseCategory category) {
  final s = l(context);
  return switch (category.id) {
    'food' => s.categoryFood,
    'coffee' => s.categoryCoffee,
    'transport' => s.categoryTransport,
    'groceries' => s.categoryGroceries,
    'shopping' => s.categoryShopping,
    'other' => s.categoryOther,
    _ => category.label,
  };
}
