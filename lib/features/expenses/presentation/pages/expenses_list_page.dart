import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/money.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/reactive_state_views.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../domain/expense.dart';
import '../../domain/expense_category.dart';
import '../../domain/expense_repository.dart';
import '../../domain/wallet.dart';
import '../widgets/category_hue_colors.dart';
import '../widgets/wallet_balance_sheet.dart';
import 'expense_capture_page.dart';

/// The Expenses history, built to the design handoff's **Expenses** screen
/// (4c): the amber screen wash, a wallet card up top (deducted automatically
/// as expenses are logged), a this-week category breakdown, then the full log
/// grouped by day — Today, Yesterday, then dated headers — each day a hairline
/// card with its subtotal beside the header. Newest first.
///
/// Amber is money and only money here (identity §2), which is why this is the
/// one amber-lit screen in the app and the one amber FAB.
///
/// The handoff is explicit that per-row saturated icon tiles go: a column of
/// them turns the log into a colour chart and pulls the eye off the amounts.
/// Each row carries a 4px spine in its category's hue instead, and the
/// amounts line up in a single right-hand mono column you can read straight
/// down. That also retires the emoji chips — identity §8 rules emoji out.
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
    return TrainScreen(
      tint: TrainColors.expensesTint,
      floatingActionButton: TrainFab(
        key: const Key('new-expense-fab'),
        icon: AppIcons.add,
        semanticLabel: 'New expense',
        // Amber, not ember: on this screen the committing action is a money
        // action, and money is the one thing amber marks.
        color: TrainColors.amber,
        iconColor: const Color(0xFF1A1505),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ExpenseCapturePage())),
      ),
      child: StreamBuilder<List<ExpenseCategory>>(
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
                      expenseSnapshot.connectionState ==
                          ConnectionState.waiting) {
                    return const LoadingStateView();
                  }
                  final now = DateTime.now();
                  final currency = wallet?.currency ?? 'EGP';
                  final todayMinor = todayTotalMinor(items, now);
                  final weekMinor = weekTotalMinor(items, now);
                  final byCategory = _byCategory(items, now, categories);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 100),
                    children: [
                      const RiseIn(child: TrainPageHeader(title: 'Expenses')),
                      const SizedBox(height: 18),
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
                              for (final group in _groupByDay(items)) ...[
                                _DayHeader(
                                  label: _dayLabel(group.day, now),
                                  subtotalMinor: group.subtotalMinor,
                                  currency: group.expenses.first.currency,
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
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
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

/// The wallet slab — the one saturated amber surface on the page, and the
/// only place a balance is stated. Before a starting balance is set it
/// carries the setup prompt instead; the "Set starting balance" pill is the
/// solid-amber committing action the handoff draws.
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-0.7, -1),
          end: const Alignment(0.7, 1),
          colors: [
            TrainColors.amber.withValues(alpha: 0.16),
            TrainColors.amber.withValues(alpha: 0.05),
            const Color(0x05FFFFFF),
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: TrainColors.amber.withValues(alpha: 0.28)),
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
                      style: TrainType.caption(
                        size: 9,
                        tracking: 0.2,
                        weight: FontWeight.w600,
                        color: TrainColors.amber,
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
                const SizedBox(height: 14),
                // The screen's one hero number, with its currency smaller and
                // dimmer beside it.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        formatAmount(balance),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TrainType.mono(
                          size: 40,
                          weight: FontWeight.w300,
                          tracking: -0.05,
                          color: negative
                              ? TrainColors.ember
                              : const Color(0xFFF9F9F5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      currency,
                      style: TrainType.mono(
                        size: 11,
                        weight: FontWeight.w500,
                        tracking: 0.14,
                        color: const Color(0x59F4F4F0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${formatAmount(todayMinor)} $currency SPENT TODAY',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TrainType.mono(
                          size: 10,
                          tracking: 0.08,
                          color: TrainColors.amber.withValues(alpha: 0.8),
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
          style: TrainType.caption(
            size: 9,
            tracking: 0.2,
            weight: FontWeight.w600,
            color: TrainColors.amber,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'How much do you have right now?',
          style: TrainType.ui(
            size: 20,
            weight: FontWeight.w800,
            tracking: -0.02,
            color: const Color(0xFFF9F9F5),
            height: 1.25,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Every expense you log deducts from it automatically.',
          style: TrainType.ui(
            size: 12.5,
            weight: FontWeight.w400,
            color: TrainColors.ink2,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        PressableScale(
          scale: 0.985,
          child: Material(
            color: TrainColors.amber,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => WalletBalanceSheet.show(
                context,
                mode: WalletSheetMode.setBalance,
                currency: currency,
              ),
              child: SizedBox(
                height: 52,
                width: double.infinity,
                child: Center(
                  child: Text(
                    'Set starting balance',
                    style: TrainType.ui(
                      size: 15,
                      weight: FontWeight.w800,
                      tracking: -0.01,
                      // A dark label on a light fill — amber is too bright to
                      // carry white text at this weight.
                      color: const Color(0xFF1A1505),
                      height: 1,
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
          color: TrainColors.glassStrong,
          shape: BoxShape.circle,
          border: Border.all(color: TrainColors.hairline),
        ),
        child: Icon(icon, size: 13, color: TrainColors.ink2),
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
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: TrainColors.glassStrong,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: TrainColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.add, size: 12, color: TrainColors.inkPlain),
            const SizedBox(width: 5),
            Text(
              'Top up',
              style: TrainType.ui(
                size: 11.5,
                weight: FontWeight.w700,
                color: TrainColors.inkPlain,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// This week's spend, split by category: the section caption with the week's
/// total right-aligned, then one hairline card of label + mono amount rows,
/// each over a 4px bar in that category's hue.
///
/// Every amount sits in the same right-hand mono column, so the card is read
/// down the numbers rather than across four different marks. The emoji chips
/// that used to lead each row are gone with them (identity §8).
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
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'THIS WEEK',
              style: TrainType.caption(
                size: 9.5,
                tracking: 0.2,
                color: const Color(0x4DF4F4F0),
              ),
            ),
            const Spacer(),
            Text(
              formatAmount(weekMinor),
              style: TrainType.mono(size: 17, color: TrainColors.ink),
            ),
            const SizedBox(width: 5),
            Text(
              currency,
              style: TrainType.caption(
                size: 9,
                tracking: 0.12,
                color: const Color(0x59F4F4F0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            gradient: TrainColors.cardGradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: TrainColors.hairline),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 13),
                  child: TrainBarRow(
                    label: rows[i].category.label,
                    value: formatAmount(rows[i].minor),
                    progress: rows[i].minor / maxMinor,
                    color: trainHueColor(rows[i].category.hue),
                    labelStyle: TrainType.ui(
                      size: 12,
                      weight: FontWeight.w600,
                      color: TrainColors.inkPlain,
                      height: 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A day group's caption: `TODAY` / `YESTERDAY` / a date on the left, that
/// day's subtotal in amber on the right.
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
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
      child: TrainSectionLabel(
        label,
        trailing: '${formatAmount(subtotalMinor)} $currency',
        trailingColor: TrainColors.amber,
      ),
    );
  }
}

/// One logged expense: a 4px spine in the category's hue, the category (or
/// its note) as the title, the time and method as a mono caption, and the
/// amount in the day card's single right-hand mono column.
///
/// The spine replaces the saturated emoji chip this row used to lead with —
/// it still says which category at a glance, in a shape that doesn't compete
/// with the amount (identity §8, and the handoff's note on this screen).
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
    final note = expense.note?.trim();
    final hasNote = note != null && note.isNotEmpty;
    return Dismissible(
      key: Key('expense-row-${expense.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: TrainColors.ember.withValues(alpha: 0.14),
        child: const Icon(AppIcons.trash, size: 19, color: TrainColors.ember),
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
                  vertical: 14,
                  horizontal: 16,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 22,
                      decoration: BoxDecoration(
                        color: trainHueColor(category.hue),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The note is the specific thing bought; the
                          // category is the bucket. Lead with whichever is
                          // more informative, and let the other demote.
                          Text(
                            hasNote ? note : category.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TrainType.ui(
                              size: 13.5,
                              weight: FontWeight.w700,
                              color: TrainColors.inkPlain,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _rowCaption(expense, category, hasNote: hasNote),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TrainType.mono(
                              size: 9.5,
                              tracking: 0.08,
                              color: const Color(0x59F4F4F0),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatAmount(expense.amountMinor),
                      style: TrainType.mono(size: 14, color: TrainColors.ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!last)
            const Padding(
              padding: EdgeInsets.only(left: 32),
              child: Divider(
                height: 1,
                thickness: 1,
                color: TrainColors.hairline,
              ),
            ),
        ],
      ),
    );
  }
}

/// `08:40 · FOOD` — when the row's title is the note, the caption carries the
/// category; when the title is already the category, the caption is just the
/// time. Never a caption that restates the line above it.
String _rowCaption(
  Expense expense,
  ExpenseCategory category, {
  required bool hasNote,
}) {
  final at = expense.spentAt;
  final time =
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
  return hasNote ? '$time · ${category.label.toUpperCase()}' : time;
}
