import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/expense_category.dart';
import 'category_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../l10n/l10n.dart';

/// Bottom sheet for creating a custom expense category: a name and a stroked
/// icon from the app's category vocabulary. Returns the new category's id on
/// save, or null if cancelled.
///
/// There is no colour picker. Categories used to carry one, but a stroked
/// glyph already tells them apart and every money surface is amber, so the
/// swatch you chose was never rendered anywhere — see [ExpenseCategory].
class AddCategorySheet extends StatefulWidget {
  const AddCategorySheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: TrainColors.raised,
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
              color: TrainColors.hairlineStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(l(context).categoryNew, style: AppText.cardTitle),
          const SizedBox(height: 18),
          TextField(
            controller: _nameController,
            autofocus: true,
            style: AppText.rowTitle,
            decoration: InputDecoration(hintText: l(context).categoryNewHint),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Text(l(context).categoryIconCaps, style: AppText.sectionLabel),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final icon in kPickableCategoryIcons)
                _IconOption(
                  icon: icon,
                  selected: icon == _icon,
                  // Amber: the money hue every expense surface wears. The
                  // preview shows exactly how the chip will look, because
                  // there is nothing else left to choose.
                  tint: TrainColors.amber,
                  onTap: () => setState(() => _icon = icon),
                ),
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
          color: selected ? TrainColors.amberWash : TrainColors.raisedStrong,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: TrainColors.amber, width: 1.6)
              : null,
        ),
        child: Icon(
          categoryIcon(icon),
          size: 19,
          color: selected ? tint : TrainColors.ink3,
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
        color: TrainColors.amber,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: Text(
              l(context).categoryAdd,
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
