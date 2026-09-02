import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/deferred_write.dart';
import '../../../../core/util/money.dart';
import '../../../../core/widgets/async_action.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/expense.dart';
import '../../domain/expense_category.dart';
import '../widgets/add_category_sheet.dart';
import '../widgets/amount_keypad.dart';
import '../widgets/category_chips.dart';
import '../../../../l10n/l10n.dart';

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

class _ExpenseCapturePageState extends State<ExpenseCapturePage>
    with AsyncAction<ExpenseCapturePage> {
  String _digits = '';
  String _currency = 'EGP';
  String _categoryId = 'food';
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
      _categoryId = initial.categoryId;
      _note = initial.note;
    }
  }

  String get _dateLabel {
    final initial = widget.initial;
    if (initial == null) return l(context).dateToday;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(
      initial.spentAt.year,
      initial.spentAt.month,
      initial.spentAt.day,
    );
    if (day == today) return l(context).dateToday;
    if (day == today.subtract(const Duration(days: 1))) return l(context).dateYesterday;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
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
        backgroundColor: TrainColors.raised,
        title: Text(l(context).expenseNote, style: AppText.cardTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.rowTitle,
          decoration: InputDecoration(hintText: l(context).expenseNoteHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l(context).actionCancel,
              style: AppText.button.copyWith(color: TrainColors.ink3),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(
              l(context).actionDone,
              style: AppText.button.copyWith(color: TrainColors.ember),
            ),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => _note = result.isEmpty ? null : result);
    }
  }

  /// Local-first, and this is the flow that needed it most: `addExpense`
  /// writes the log row AND adjusts the wallet, and the wallet adjustment is
  /// a Firestore `runTransaction` — which does not use the offline cache at
  /// all, so awaiting it froze the sub-5-second capture flow for a whole
  /// round trip (indefinitely, on a bad connection). The list and the balance
  /// behind this screen update off the cached write; the durable half
  /// finishes on its own.
  void _save() {
    if (!_canSave) return;
    runAction(#save, once: true, () async {
      final service = AppScope.of(context).expensesService;
      final initial = widget.initial;
      final expense = Expense(
        id: initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        amountMinor: _amountMinor,
        currency: _currency,
        categoryId: _categoryId,
        spentAt: initial?.spentAt ?? DateTime.now(),
        note: _note,
      );
      deferWrite(
        initial == null
            ? service.addExpense(expense)
            : service.updateExpense(initial, expense),
        failureMessage: l(context).expenseSaveFailed,
      );
      Navigator.of(context).pop(expense);
    });
  }

  void _delete() {
    final initial = widget.initial;
    if (initial == null) return;
    runAction(#delete, once: true, () async {
      final service = AppScope.of(context).expensesService;
      deferWrite(
        service.removeExpense(initial),
        failureMessage: l(context).expenseDeleteFailed,
      );
      Navigator.of(context).pop();
    });
  }

  Future<void> _addCategory() async {
    final newId = await AddCategorySheet.show(context);
    if (newId != null && mounted) setState(() => _categoryId = newId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TrainColors.base,
      body: SafeArea(
        child: Column(
          children: [
            CaptureTopBar(
              title: _editing ? l(context).expenseEdit : l(context).expenseNew,
              onClose: () => Navigator.of(context).maybePop(),
              trailing: _editing
                  ? CaptureIconButton(
                      key: const Key('expense-delete'),
                      icon: Icons.delete_outline_rounded,
                      onTap: _delete,
                      semanticLabel: l(context).expenseDelete,
                      iconColor: TrainColors.ember,
                    )
                  : null,
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _AmountDisplay(digits: _digits, currency: _currency),
                    const SizedBox(height: 18),
                    StreamBuilder<List<ExpenseCategory>>(
                      stream: AppScope.of(
                        context,
                      ).expensesService.watchCategories(),
                      initialData: AppScope.of(
                        context,
                      ).expensesService.allCategories(),
                      builder: (context, snapshot) {
                        return CategoryChips(
                          categories: snapshot.data ?? kBuiltInCategories,
                          selectedId: _categoryId,
                          onSelected: (id) => setState(() => _categoryId = id),
                          onAddCategory: _addCategory,
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    _MetaRow(
                      note: _note,
                      onEditNote: _editNote,
                      dateLabel: _dateLabel,
                    ),
                  ],
                ),
              ),
            ),
            AmountKeypad(onDigit: _onDigit, onKey: _onKey),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _SaveButton(
                // `_canSave` alone drives the LABEL so it doesn't flip back to
                // a bare "Save" the instant the button is tapped; the
                // in-flight guard only disables.
                enabled: _canSave && !actionInFlight,
                busy: isRunning(#save),
                label: _canSave
                    ? l(context).expenseSaveAmount(
                        '${formatAmount(_amountMinor)} $_currency',
                      )
                    : l(context).actionSave,
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
                color: digits.isEmpty ? TrainColors.ink3 : TrainColors.ink,
              ),
            ),
            Container(
              width: 3,
              height: 52,
              margin: const EdgeInsets.only(left: 5),
              decoration: BoxDecoration(
                color: TrainColors.amber,
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
          label: note ?? l(context).expenseAddNote,
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
    final color = active ? TrainColors.ink : TrainColors.ink3;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? TrainColors.hairlineStrong : TrainColors.hairline,
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
    this.busy = false,
  });

  final bool enabled;
  final String label;
  final VoidCallback onTap;
  final bool busy;

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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 17,
                  height: 17,
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(1.5),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF2A2205),
                          ),
                        )
                      : const Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: Color(0xFF2A2205),
                        ),
                ),
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
