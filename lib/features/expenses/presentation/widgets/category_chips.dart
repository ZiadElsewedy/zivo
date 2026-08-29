import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../domain/expense_category.dart';
import 'category_icons.dart';

/// Category chips — frequent-first, one tap. Selected chip fills amber (the
/// money hue; categories differentiate by their stroked glyph, not colour). A
/// trailing dashed chip opens category creation.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    required this.onAddCategory,
    super.key,
  });

  final List<ExpenseCategory> categories;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final VoidCallback onAddCategory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 9,
        runSpacing: 9,
        alignment: WrapAlignment.center,
        children: [
          for (final c in categories)
            _Chip(
              category: c,
              selected: c.id == selectedId,
              onTap: () => onSelected(c.id),
            ),
          _AddChip(onTap: onAddCategory),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final ExpenseCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? TrainColors.amber : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? TrainColors.amber : TrainColors.hairlineStrong,
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Amber, like everything else on a money surface — the category's
            // own hue would spend ember/green/violet on telling categories
            // apart, which is what the stroked glyph is for. On the selected
            // chip the fill IS amber, so the glyph flips to the same dark ink
            // as the label rather than tinting a colour onto a colour.
            Icon(
              categoryIcon(category.icon),
              size: 14,
              color: selected ? const Color(0xFF2A2205) : TrainColors.amber,
            ),
            const SizedBox(width: 6),
            Text(
              category.label,
              style: AppText.button.copyWith(
                fontSize: 13.5,
                color: selected ? const Color(0xFF2A2205) : TrainColors.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('add-category-chip'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: TrainColors.hairlineStrong,
            width: 1.4,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.add, size: 15, color: TrainColors.ink3),
            const SizedBox(width: 5),
            Text(
              'Add',
              style: AppText.button.copyWith(
                fontSize: 13.5,
                color: TrainColors.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
