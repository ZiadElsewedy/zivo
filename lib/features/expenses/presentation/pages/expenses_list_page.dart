import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/money.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/reactive_state_views.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/expense.dart';
import '../../domain/expense_category.dart';
import '../../domain/expense_repository.dart';
import '../../domain/wallet.dart';
import '../widgets/category_hue_colors.dart';
import '../widgets/wallet_balance_sheet.dart';
import 'expense_capture_page.dart';

/// The Expenses history — a wallet balance up top (deducted automatically as
/// expenses are logged), a this-week category breakdown, then the full log
/// grouped by day (Today, Yesterday, then dated headers), each day a grouped
/// card in the inset-list style with its subtotal in the header. Newest
/// first. The calm Solar sibling of the sub-5-second capture flow.
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
      floatingActionButton: FloatingActionButton(
        key: const Key('new-expense-fab'),
        backgroundColor: AppColors.solar,
        elevation: 3,
        tooltip: 'New expense',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ExpenseCapturePage())),
        child: const Icon(AppIcons.add, color: Color(0xFF2A2205), size: 26),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.1),
            radius: 1.15,
            colors: [Color(0xFF231B14), AppColors.ground, Color(0xFF0E0B08)],
            stops: [0.0, 0.52, 1.0],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -50,
              right: -70,
              child: _AuraBlob(color: AppColors.solar, size: 210),
            ),
            SafeArea(
              child: StreamBuilder<List<ExpenseCategory>>(
                stream: _categoriesStream,
                initialData: service.allCategories(),
                builder: (context, categorySnapshot) {
                  final categories =
                      categorySnapshot.data ?? kBuiltInCategories;
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
                          final items =
                              expenseSnapshot.data ?? const <Expense>[];
                          if (items.isEmpty &&
                              expenseSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                            return const LoadingStateView();
                          }
                          final now = DateTime.now();
                          final currency = wallet?.currency ?? 'EGP';
                          final todayMinor = todayTotalMinor(items, now);
                          final weekMinor = weekTotalMinor(items, now);
                          final byCategory = _byCategory(
                            items,
                            now,
                            categories,
                          );
                          return ListView(
                            padding: const EdgeInsets.fromLTRB(22, 12, 22, 100),
                            children: [
                              RiseIn(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _BackButton(),
                                    const SizedBox(height: 20),
                                    Text('Expenses', style: AppText.greeting),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                              RiseIn(
                                delay: const Duration(milliseconds: 50),
                                child: _WalletCard(
                                  wallet: wallet,
                                  todayMinor: todayMinor,
                                  currency: currency,
                                ),
                              ),
                              if (byCategory.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                RiseIn(
                                  delay: const Duration(milliseconds: 90),
                                  child: _CategoryBreakdown(
                                    rows: byCategory,
                                    weekMinor: weekMinor,
                                    currency: currency,
                                  ),
                                ),
                              ],
                              if (items.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 40),
                                  child: EmptyStateView(
                                    'Nothing spent yet — a calm start.',
                                  ),
                                )
                              else
                                RiseIn(
                                  delay: const Duration(milliseconds: 130),
                                  child: Column(
                                    children: [
                                      for (final group in _groupByDay(
                                        items,
                                      )) ...[
                                        _DayHeader(
                                          label: _dayLabel(group.day, now),
                                          subtotalMinor: group.subtotalMinor,
                                          currency:
                                              group.expenses.first.currency,
                                        ),
                                        _DayCard(
                                          group: group,
                                          categories: categories,
                                          onTap: (expense) =>
                                              _openEdit(context, expense),
                                          onDelete: (expense) =>
                                              service.removeExpense(expense),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEdit(BuildContext context, Expense expense) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ExpenseCapturePage(initial: expense)),
    );
  }
}

/// One day's expenses as a grouped card — the inset-list pattern, so each
/// day reads as one physical object with its rows separated by inset
/// hairlines. Swipe-to-delete and tap-to-edit live on the rows inside.
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.group,
    required this.categories,
    required this.onTap,
    required this.onDelete,
  });

  final _DayGroup group;
  final List<ExpenseCategory> categories;
  final void Function(Expense expense) onTap;
  final ValueChanged<Expense> onDelete;

  @override
  Widget build(BuildContext context) {
    final expenses = group.expenses;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Column(
          children: [
            for (var i = 0; i < expenses.length; i++)
              _ExpenseRow(
                expenses[i],
                category: resolveCategory(expenses[i].categoryId, categories),
                last: i == expenses.length - 1,
                onTap: () => onTap(expenses[i]),
                onDelete: () => onDelete(expenses[i]),
              ),
          ],
        ),
      ),
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
  final rows =
      totals.entries
          .map(
            (e) => _CategorySpend(resolveCategory(e.key, categories), e.value),
          )
          .toList()
        ..sort((a, b) => b.minor.compareTo(a.minor));
  return rows.take(5).toList();
}

class _DayGroup {
  _DayGroup(this.day, this.expenses);
  final DateTime day;
  final List<Expense> expenses;
  int get subtotalMinor => expenses.fold(0, (sum, e) => sum + e.amountMinor);
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
  return '${weekdays[day.weekday - 1]} ${day.day} ${months[day.month - 1]}';
}

/// A soft, blurred wash of color floating behind the content — the quiet
/// "energy" glow shared across the app's surfaces. Purely decorative.
class _AuraBlob extends StatelessWidget {
  const _AuraBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 46, sigmaY: 46),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.14),
          ),
        ),
      ),
    );
  }
}

/// The pushed-page back affordance — the same 38px chip language as the
/// Settings header.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Tooltip(
        message: 'Back',
        child: InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          customBorder: const CircleBorder(),
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.hairline2),
            ),
            child: const Icon(AppIcons.back, size: 18, color: AppColors.ink2),
          ),
        ),
      ),
    );
  }
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
        color: AppColors.card,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.solar.withValues(alpha: 0.16),
            AppColors.solar.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.solar.withValues(alpha: 0.14)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0FA9760A),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
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
                    Text(
                      'WALLET',
                      style: AppText.sectionLabel.copyWith(
                        color: AppColors.solarText,
                      ),
                    ),
                    const Spacer(),
                    _IconPill(
                      icon: AppIcons.edit,
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
                    fontSize: 42,
                    color: negative ? AppColors.flareText : AppColors.ink,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${formatAmount(todayMinor)} $currency spent today',
                        style: AppText.meta.copyWith(
                          color: AppColors.solarText,
                        ),
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
        Text(
          'SET UP YOUR WALLET',
          style: AppText.sectionLabel.copyWith(color: AppColors.solarText),
        ),
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
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFC933), AppColors.solar],
                ),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.solar.withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: -6,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
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
                      style: AppText.button.copyWith(
                        color: const Color(0xFF2A2205),
                      ),
                    ),
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
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.hairline2),
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
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.add, size: 13, color: AppColors.ink),
            const SizedBox(width: 4),
            Text(
              'Top up',
              style: AppText.button.copyWith(
                fontSize: 12,
                color: AppColors.ink,
              ),
            ),
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
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 2),
          child: Row(
            children: [
              Text('THIS WEEK BY CATEGORY', style: AppText.sectionLabel),
              const Spacer(),
              Text(
                '${formatAmount(weekMinor)} $currency',
                style: AppText.sectionLabel.copyWith(color: AppColors.ink2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final row in rows) ...[
          _CategoryBar(
            row: row,
            currency: currency,
            fraction: row.minor / maxMinor,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.row,
    required this.currency,
    required this.fraction,
  });

  final _CategorySpend row;
  final String currency;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final color = hueColor(row.category.hue);
    return Row(
      children: [
        _CategoryMark(
          category: row.category,
          size: 26,
          radius: 8,
          emojiSize: 12,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            row.category.label,
            style: AppText.meta.copyWith(color: AppColors.ink2, fontSize: 13.5),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(height: 6, color: AppColors.hairline),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction.clamp(0.03, 1.0),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, Color.lerp(color, Colors.black, 0.28)!],
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 78,
          child: Text(
            '${formatAmount(row.minor)} $currency',
            textAlign: TextAlign.right,
            style: AppText.meta.copyWith(color: AppColors.ink, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

/// A category's mark — its emoji inside a rounded chip tinted with the
/// category's own hue. Shared by the breakdown and the log rows so the same
/// category reads identically everywhere on the page.
class _CategoryMark extends StatelessWidget {
  const _CategoryMark({
    required this.category,
    required this.size,
    required this.radius,
    required this.emojiSize,
  });

  final ExpenseCategory category;
  final double size;
  final double radius;
  final double emojiSize;

  @override
  Widget build(BuildContext context) {
    final color = hueColor(category.hue);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.24),
            color.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        category.emoji.isEmpty ? '•' : category.emoji,
        style: TextStyle(fontSize: emojiSize, height: 1),
      ),
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
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 9),
      child: Row(
        children: [
          Text(
            label,
            style: AppText.meta.copyWith(
              color: AppColors.ink3,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          Text(
            '${formatAmount(subtotalMinor)} $currency',
            style: AppText.meta.copyWith(
              color: AppColors.solarText,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
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
    required this.last,
    required this.onTap,
    required this.onDelete,
  });

  final Expense expense;
  final ExpenseCategory category;
  final bool last;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('expense-row-${expense.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.flare.withValues(alpha: 0.14),
        child: const Icon(AppIcons.trash, size: 20, color: AppColors.flareText),
      ),
      onDismissed: (_) => onDelete(),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 11,
                  horizontal: 16,
                ),
                child: Row(
                  children: [
                    _CategoryMark(
                      category: category,
                      size: 32,
                      radius: 10,
                      emojiSize: 15,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.rowTitle.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (expense.note != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              expense.note!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.meta.copyWith(
                                color: AppColors.ink3,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${formatAmount(expense.amountMinor)} ${expense.currency}',
                      style: AppText.amount.copyWith(
                        color: AppColors.solarText,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!last)
            Container(
              margin: const EdgeInsets.only(left: 60),
              height: 1,
              color: AppColors.hairline,
            ),
        ],
      ),
    );
  }
}
