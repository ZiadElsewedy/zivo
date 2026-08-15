import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/money.dart';
import '../../domain/expense.dart';
import '../../domain/expense_category.dart';
import '../../domain/expense_repository.dart';
import 'expense_capture_page.dart';

/// The Expenses history — a summary of today/this-week spend followed by the
/// full log, grouped by day (Today, Yesterday, then dated headers), each day
/// carrying a subtotal. Newest first. The calm Solar sibling of the
/// sub-5-second capture flow.
class ExpensesListPage extends StatelessWidget {
  const ExpensesListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final expenses = AppScope.of(context).expenses;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Expenses', style: AppText.cardTitle),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.solar,
        elevation: 2,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ExpenseCapturePage()),
        ),
        child: const Icon(Icons.add_rounded, color: Color(0xFF2A2205)),
      ),
      body: StreamBuilder<List<Expense>>(
        stream: expenses.watchAll(),
        initialData: expenses.current,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <Expense>[];
          if (items.isEmpty &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.ink3),
            );
          }
          if (items.isEmpty) {
            return Center(
              child: Text(
                'Nothing spent yet — a calm start.',
                style: AppText.aside,
                textAlign: TextAlign.center,
              ),
            );
          }
          final now = DateTime.now();
          final groups = _groupByDay(items);
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 100),
            children: [
              _SummaryHeader(
                todayMinor: todayTotalMinor(items, now),
                weekMinor: weekTotalMinor(items, now),
                currency: items.first.currency,
              ),
              for (final group in groups) ...[
                _DayHeader(
                  label: _dayLabel(group.day, now),
                  subtotalMinor: group.subtotalMinor,
                  currency: group.expenses.first.currency,
                ),
                for (final expense in group.expenses)
                  _ExpenseRow(
                    expense,
                    onTap: () => _openEdit(context, expense),
                    onDelete: () => expenses.remove(expense.id),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _openEdit(BuildContext context, Expense expense) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ExpenseCapturePage(initial: expense)),
    );
  }
}

class _DayGroup {
  _DayGroup(this.day, this.expenses);
  final DateTime day;
  final List<Expense> expenses;
  int get subtotalMinor =>
      expenses.fold(0, (sum, e) => sum + e.amountMinor);
}

List<_DayGroup> _groupByDay(List<Expense> items) {
  final sorted = [...items]..sort((a, b) => b.spentAt.compareTo(a.spentAt));
  final groups = <_DayGroup>[];
  for (final expense in sorted) {
    final day = DateTime(
      expense.spentAt.year,
      expense.spentAt.month,
      expense.spentAt.day,
    );
    if (groups.isNotEmpty && groups.last.day == day) {
      groups.last.expenses.add(expense);
    } else {
      groups.add(_DayGroup(day, [expense]));
    }
  }
  return groups;
}

String _dayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${weekdays[day.weekday - 1]} ${day.day} ${months[day.month - 1]}';
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.todayMinor,
    required this.weekMinor,
    required this.currency,
  });

  final int todayMinor;
  final int weekMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.solarWash,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: const [
          BoxShadow(color: Color(0x0FA9760A), blurRadius: 4, offset: Offset(0, 2)),
          BoxShadow(
            color: Color(0x1FA9760A),
            blurRadius: 30,
            spreadRadius: -18,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _Stat(label: 'Today', minor: todayMinor, currency: currency)),
          Container(width: 1, height: 36, color: AppColors.hairline2),
          const SizedBox(width: 18),
          Expanded(
            child: _Stat(label: 'This week', minor: weekMinor, currency: currency),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.minor, required this.currency});

  final String label;
  final int minor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppText.sectionLabel.copyWith(color: AppColors.solarText),
        ),
        const SizedBox(height: 6),
        Text(
          '${formatAmount(minor)} $currency',
          style: AppText.cardTitle.copyWith(fontSize: 22),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.label,
    required this.subtotalMinor,
    required this.currency,
  });

  final String label;
  final int subtotalMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(
        children: [
          Text(
            label,
            style: AppText.meta.copyWith(
              color: AppColors.ink3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '${formatAmount(subtotalMinor)} $currency',
            style: AppText.meta.copyWith(
              color: AppColors.solarText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow(
    this.expense, {
    required this.onTap,
    required this.onDelete,
  });

  final Expense expense;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('expense-row-${expense.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 14),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: AppColors.flareText,
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    expense.category.emoji.isEmpty ? '•' : expense.category.emoji,
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expense.category.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (expense.note != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          expense.note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.meta.copyWith(color: AppColors.ink3),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  '${formatAmount(expense.amountMinor)} ${expense.currency}',
                  style: AppText.amount.copyWith(color: AppColors.solarText),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
