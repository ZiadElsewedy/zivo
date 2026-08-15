import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/money.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/expense.dart';
import '../../domain/expense_category.dart';
import '../widgets/amount_keypad.dart';
import '../widgets/category_chips.dart';

/// Expense capture — the sub-5-second flow. Amount first, keypad up, one tap
/// to categorise, Save. A Solar screen throughout. Pass [initial] to edit an
/// existing expense in place instead of creating a new one; editing preserves
/// the expense's original `spentAt`.
class ExpenseCapturePage extends StatefulWidget {
  const ExpenseCapturePage({super.key, this.initial});

  final Expense? initial;

  @override
  State<ExpenseCapturePage> createState() => _ExpenseCapturePageState();
}

class _ExpenseCapturePageState extends State<ExpenseCapturePage> {
  String _digits = '';
  String _currency = 'EGP';
  ExpenseCategory _category = ExpenseCategory.food;
  String? _note;

  bool get _editing => widget.initial != null;

  int get _amountMinor => parseMinor(_digits);
  bool get _canSave => _amountMinor > 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _digits = formatAmount(initial.amountMinor);
      _currency = initial.currency;
      _category = initial.category;
      _note = initial.note;
    }
  }

  String get _dateLabel {
    final initial = widget.initial;
    if (initial == null) return 'Today';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(
      initial.spentAt.year,
      initial.spentAt.month,
      initial.spentAt.day,
    );
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${day.day} ${months[day.month - 1]}';
  }

  void _onKey(KeypadKey key) {
    setState(() {
      switch (key) {
        case KeypadKey.backspace:
          if (_digits.isNotEmpty) {
            _digits = _digits.substring(0, _digits.length - 1);
          }
        case KeypadKey.dot:
          if (!_digits.contains('.') && _digits.isNotEmpty) _digits += '.';
        case KeypadKey.digit:
          break; // handled by onDigit
      }
    });
  }

  void _onDigit(String d) {
    setState(() {
      // Guard against silly precision: at most 2 decimals.
      if (_digits.contains('.')) {
        final decimals = _digits.split('.')[1];
        if (decimals.length >= 2) return;
      }
      if (_digits == '0') {
        _digits = d; // no leading zeros
      } else {
        _digits += d;
      }
    });
  }

  Future<void> _editNote() async {
    final controller = TextEditingController(text: _note);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Note', style: AppText.cardTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.rowTitle,
          decoration: const InputDecoration(hintText: 'What was it for?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppText.button.copyWith(color: AppColors.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('Done', style: AppText.button.copyWith(color: AppColors.emberText)),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => _note = result.isEmpty ? null : result);
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final expenses = AppScope.of(context).expenses;
    final initial = widget.initial;
    final expense = Expense(
      id: initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      amountMinor: _amountMinor,
      currency: _currency,
      category: _category,
      spentAt: initial?.spentAt ?? DateTime.now(),
      note: _note,
    );
    if (initial == null) {
      await expenses.add(expense);
    } else {
      await expenses.update(expense);
    }
    if (mounted) Navigator.of(context).pop(expense);
  }

  Future<void> _delete() async {
    final initial = widget.initial;
    if (initial == null) return;
    final expenses = AppScope.of(context).expenses;
    await expenses.remove(initial.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: SafeArea(
        child: Column(
          children: [
            CaptureTopBar(
              title: _editing ? 'Edit expense' : 'New expense',
              onClose: () => Navigator.of(context).maybePop(),
              trailing: _editing
                  ? InkWell(
                      key: const Key('expense-delete'),
                      onTap: _delete,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEFEBE3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: AppColors.flareText,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 20),
            _AmountDisplay(digits: _digits, currency: _currency),
            const SizedBox(height: 18),
            CategoryChips(
              selected: _category,
              onSelected: (c) => setState(() => _category = c),
            ),
            const SizedBox(height: 14),
            _MetaRow(note: _note, onEditNote: _editNote, dateLabel: _dateLabel),
            const Spacer(),
            AmountKeypad(onDigit: _onDigit, onKey: _onKey),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _SaveButton(
                enabled: _canSave,
                label: _canSave
                    ? 'Save · ${formatAmount(_amountMinor)} $_currency'
                    : 'Save',
                onTap: _save,
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.digits, required this.currency});

  final String digits;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          currency.toUpperCase(),
          style: AppText.sectionLabel.copyWith(letterSpacing: 1.0),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              digits.isEmpty ? '0' : digits,
              style: AppText.heroNumber.copyWith(
                color: digits.isEmpty ? AppColors.ink3 : AppColors.ink,
              ),
            ),
            Container(
              width: 3,
              height: 52,
              margin: const EdgeInsets.only(left: 5),
              decoration: BoxDecoration(
                color: AppColors.solar,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.note,
    required this.onEditNote,
    required this.dateLabel,
  });

  final String? note;
  final VoidCallback onEditNote;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _MetaChip(
          icon: Icons.sticky_note_2_outlined,
          label: note ?? 'Add note',
          active: note != null,
          onTap: onEditNote,
        ),
        const SizedBox(width: 10),
        _MetaChip(
          icon: Icons.calendar_today_rounded,
          label: dateLabel,
          active: true,
          onTap: null,
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.ink : AppColors.ink3;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? AppColors.hairline2 : AppColors.hairline,
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.enabled,
    required this.label,
    required this.onTap,
  });

  final bool enabled;
  final String label;
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_rounded, size: 17, color: Color(0xFF2A2205)),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppText.button.copyWith(
                    fontSize: 16,
                    color: const Color(0xFF2A2205),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
