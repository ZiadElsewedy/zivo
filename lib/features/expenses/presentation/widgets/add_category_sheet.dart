import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/expense_category.dart';
import 'category_hue_colors.dart';
import 'category_icons.dart';

/// Bottom sheet for creating a custom expense category: name, a stroked icon
/// from the app's category vocabulary, and a color from the 5-hue palette.
/// Returns the new category's id on save, or null if cancelled.
class AddCategorySheet extends StatefulWidget {
  const AddCategorySheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AddCategorySheet(),
    );
  }

  @override
  State<AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends State<AddCategorySheet> {
  final _nameController = TextEditingController();
  CategoryIcon _icon = kPickableCategoryIcons.first;
  CategoryHue _hue = CategoryHue.solar;
  bool _saving = false;

  bool get _canSave => _nameController.text.trim().isNotEmpty && !_saving;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final category = ExpenseCategory(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: _nameController.text.trim(),
      icon: _icon,
      hue: _hue,
    );
    await AppScope.of(context).expensesService.addCategory(category);
    if (mounted) Navigator.of(context).pop(category.id);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 22,
        right: 22,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.hairline2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text('New category', style: AppText.cardTitle),
          const SizedBox(height: 18),
          TextField(
            controller: _nameController,
            autofocus: true,
            style: AppText.rowTitle,
            decoration: const InputDecoration(hintText: 'e.g. Subscriptions'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Text('ICON', style: AppText.sectionLabel),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final icon in kPickableCategoryIcons)
                _IconOption(
                  icon: icon,
                  selected: icon == _icon,
                  // Previewed in the hue being chosen below, so the two
                  // pickers read as one decision about how the chip will look.
                  tint: hueColor(_hue),
                  onTap: () => setState(() => _icon = icon),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('COLOR', style: AppText.sectionLabel),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final hue in CategoryHue.values) ...[
                _HueOption(
                  hue: hue,
                  selected: hue == _hue,
                  onTap: () => setState(() => _hue = hue),
                ),
                const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 26),
          _SaveButton(enabled: _canSave, onTap: _save),
        ],
      ),
    );
  }
}

class _IconOption extends StatelessWidget {
  const _IconOption({
    required this.icon,
    required this.selected,
    required this.tint,
    required this.onTap,
  });

  final CategoryIcon icon;
  final bool selected;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.solarWash : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: AppColors.solar, width: 1.6)
              : null,
        ),
        child: Icon(
          categoryIcon(icon),
          size: 19,
          color: selected ? tint : AppColors.ink3,
        ),
      ),
    );
  }
}

class _HueOption extends StatelessWidget {
  const _HueOption({
    required this.hue,
    required this.selected,
    required this.onTap,
  });

  final CategoryHue hue;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = hueColor(hue);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: selected ? Border.all(color: AppColors.ink, width: 2) : null,
        ),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: AppColors.solar,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: Text(
              'Add category',
              style: AppText.button.copyWith(
                fontSize: 16,
                color: const Color(0xFF2A2205),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
