import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/money.dart';
import '../../../../core/widgets/reactive_state_views.dart';
import '../../domain/expense.dart';
import '../../domain/expense_category.dart';
import '../../domain/expense_repository.dart';
import '../../domain/wallet.dart';
import '../widgets/category_hue_colors.dart';
import '../widgets/wallet_balance_sheet.dart';
import 'expense_capture_page.dart';

/// The Expenses history — a wallet balance up top (deducted automatically as
/// expenses are logged), a this-week category breakdown, then the full log
/// grouped by day (Today, Yesterday, then dated headers), each day carrying
/// a subtotal. Newest first. The calm Solar sibling of the sub-5-second
/// capture flow.
class ExpensesListPage extends StatefulWidget {
  const ExpensesListPage({super.key});

  @override
  State<ExpensesListPage> createState() => _ExpensesListPageState();
}

class _ExpensesListPageState extends State<ExpensesListPage> {
  // Cached once per page lifetime — each repository's `watch*()` call
  // returns a fresh Stream instance, so recomputing it inside a builder
  // callback on every rebuild would make the nested StreamBuilders below
  // unsubscribe and resubscribe on every emission instead of holding one
  // stable subscription each.
  late final _service = AppScope.of(context).expensesService;
  late final _categoriesStream = _service.watchCategories();
  late final _walletStream = _service.wallet.watch();
  late final _expensesStream = _service.expenses.watchAll();

  @override
  Widget build(BuildContext context) {
    final service = _service;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Expenses', style: AppText.cardTitle),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('new-expense-fab'),
        backgroundColor: AppColors.solar,
        elevation: 2,
        tooltip: 'New expense',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ExpenseCapturePage()),
        ),
        child: const Icon(Icons.add_rounded, color: Color(0xFF2A2205)),
      ),
      body: StreamBuilder<List<ExpenseCategory>>(
        stream: _categoriesStream,
        initialData: service.allCategories(),
        builder: (context, categorySnapshot) {
          final categories = categorySnapshot.data ?? kBuiltInCategories;
          return StreamBuilder<Wallet?>(
            stream: _walletStream,
            initialData: service.wallet.current,
            builder: (context, walletSnapshot) {
              final wallet = walletSnapshot.data;
              return StreamBuilder<List<Expense>>(
                stream: _expensesStream,
                initialData: service.expenses.current,
                builder: (context, expenseSnapshot) {
                  if (expenseSnapshot.hasError) {
                    return const ErrorStateView();
                  }
                  final items = expenseSnapshot.data ?? const <Expense>[];
                  if (items.isEmpty &&
                      expenseSnapshot.connectionState == ConnectionState.waiting) {
                    return const LoadingStateView();
                  }
                  final now = DateTime.now();
                  final currency = wallet?.currency ?? 'EGP';
                  final todayMinor = todayTotalMinor(items, now);
                  final weekMinor = weekTotalMinor(items, now);
                  final byCategory = _byCategory(items, now, categories);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 100),
                    children: [
                      _WalletCard(
                        wallet: wallet,
                        todayMinor: todayMinor,
                        currency: currency,
                      ),
                      if (byCategory.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _CategoryBreakdown(
                          rows: byCategory,
                          weekMinor: weekMinor,
                          currency: currency,
                        ),
                      ],
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: EmptyStateView('Nothing spent yet — a calm start.'),
                        )
                      else ...[
                        for (final group in _groupByDay(items)) ...[
                          _DayHeader(
                            label: _dayLabel(group.day, now),
                            subtotalMinor: group.subtotalMinor,
                            currency: group.expenses.first.currency,
                          ),
                          for (final expense in group.expenses)
                            _ExpenseRow(
                              expense,
                              category: resolveCategory(expense.categoryId, categories),
                              onTap: () => _openEdit(context, expense),
                              onDelete: () => service.removeExpense(expense),
                            ),
                        ],
                      ],
                    ],
                  );
                },
              );
            },
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

class _CategorySpend {
  _CategorySpend(this.category, this.minor);
  final ExpenseCategory category;
  final int minor;
}

List<_CategorySpend> _byCategory(
  List<Expense> items,
  DateTime now,
  List<ExpenseCategory> categories,
) {
  final from = now.subtract(const Duration(days: 7));
  final totals = <String, int>{};
  for (final e in items) {
    if (!e.spentAt.isAfter(from)) continue;
    totals[e.categoryId] = (totals[e.categoryId] ?? 0) + e.amountMinor;
  }
  final rows = totals.entries
      .map((e) => _CategorySpend(resolveCategory(e.key, categories), e.value))
      .toList()
    ..sort((a, b) => b.minor.compareTo(a.minor));
  return rows.take(5).toList();
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

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.wallet,
    required this.todayMinor,
    required this.currency,
  });

  final Wallet? wallet;
  final int todayMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final balance = wallet?.balanceMinor;
    final negative = balance != null && balance < 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
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
      child: balance == null
          ? _WalletSetupPrompt(currency: currency)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('WALLET', style: AppText.sectionLabel.copyWith(color: AppColors.solarText)),
                    const Spacer(),
                    _IconPill(
                      icon: Icons.edit_rounded,
                      onTap: () => WalletBalanceSheet.show(
                        context,
                        mode: WalletSheetMode.setBalance,
                        prefillMinor: balance,
                        currency: currency,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${formatAmount(balance)} $currency',
                  style: AppText.heroNumber.copyWith(
                    fontSize: 40,
                    color: negative ? AppColors.flareText : AppColors.ink,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${formatAmount(todayMinor)} $currency spent today',
                        style: AppText.meta.copyWith(color: AppColors.solarText),
                      ),
                    ),
                    _TopUpButton(
                      onTap: () => WalletBalanceSheet.show(
                        context,
                        mode: WalletSheetMode.topUp,
                        currency: currency,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _WalletSetupPrompt extends StatelessWidget {
  const _WalletSetupPrompt({required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SET UP YOUR WALLET', style: AppText.sectionLabel.copyWith(color: AppColors.solarText)),
        const SizedBox(height: 8),
        Text(
          'How much money do you have right now?',
          style: AppText.cardTitle.copyWith(fontSize: 19),
        ),
        const SizedBox(height: 4),
        Text(
          'Every expense you log will deduct from it automatically.',
          style: AppText.body,
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: Material(
            color: AppColors.solar,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => WalletBalanceSheet.show(
                context,
                mode: WalletSheetMode.setBalance,
                currency: currency,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Center(
                  child: Text(
                    'Set starting balance',
                    style: AppText.button.copyWith(color: const Color(0xFF2A2205)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 14, color: AppColors.ink2),
      ),
    );
  }
}

class _TopUpButton extends StatelessWidget {
  const _TopUpButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, size: 13, color: AppColors.ink),
            const SizedBox(width: 3),
            Text('Top up', style: AppText.button.copyWith(fontSize: 12, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({
    required this.rows,
    required this.weekMinor,
    required this.currency,
  });

  final List<_CategorySpend> rows;
  final int weekMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final maxMinor = rows.map((r) => r.minor).fold(1, (a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('THIS WEEK BY CATEGORY', style: AppText.sectionLabel),
            const Spacer(),
            Text(
              '${formatAmount(weekMinor)} $currency',
              style: AppText.sectionLabel.copyWith(color: AppColors.ink2),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final row in rows) ...[
          _CategoryBar(row: row, currency: currency, fraction: row.minor / maxMinor),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.row, required this.currency, required this.fraction});

  final _CategorySpend row;
  final String currency;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final color = hueColor(row.category.hue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (row.category.emoji.isNotEmpty) ...[
              Text(row.category.emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
            ],
            Text(row.category.label, style: AppText.meta.copyWith(color: AppColors.ink2)),
            const Spacer(),
            Text(
              '${formatAmount(row.minor)} $currency',
              style: AppText.meta.copyWith(color: AppColors.ink),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(height: 6, color: AppColors.hairline),
                  Container(
                    height: 6,
                    width: constraints.maxWidth * fraction.clamp(0.03, 1.0),
                    color: color,
                  ),
                ],
              );
            },
          ),
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
    required this.category,
    required this.onTap,
    required this.onDelete,
  });

  final Expense expense;
  final ExpenseCategory category;
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
                    category.emoji.isEmpty ? '•' : category.emoji,
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.label,
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
