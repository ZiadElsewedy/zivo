import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/expense_category.dart';

/// Category chips — frequent-first, one tap. Selected chip fills Solar.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final ExpenseCategory selected;
  final ValueChanged<ExpenseCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 9,
        runSpacing: 9,
        alignment: WrapAlignment.center,
        children: [
          for (final c in ExpenseCategory.values)
            _Chip(
              category: c,
              selected: c == selected,
              onTap: () => onSelected(c),
            ),
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
          color: selected ? AppColors.solar : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.solar : AppColors.hairline2,
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (category.emoji.isNotEmpty) ...[
              Text(category.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
            ],
            Text(
              category.label,
              style: AppText.button.copyWith(
                fontSize: 13.5,
                color: selected ? const Color(0xFF2A2205) : AppColors.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
