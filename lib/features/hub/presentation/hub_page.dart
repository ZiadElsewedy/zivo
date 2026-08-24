import 'package:flutter/material.dart';

import '../../../core/scope/app_scope.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/util/money.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../diet/domain/diet_plan.dart';
import '../../diet/domain/diet_summary.dart';
import '../../diet/presentation/pages/diet_plan_page.dart';
import '../../diet/presentation/today_diet.dart';
import '../../expenses/domain/expense.dart';
import '../../expenses/domain/expense_repository.dart';
import '../../expenses/domain/wallet.dart';
import '../../expenses/presentation/pages/expenses_list_page.dart';
import '../../moments/domain/moment.dart';
import '../../moments/presentation/pages/moments_timeline_page.dart';
import '../../shell/presentation/widgets/zivo_bottom_bar.dart';
import '../../workout/domain/live_session.dart';
import '../../workout/domain/up_next_selection.dart';
import '../../workout/domain/workout_plan.dart';
import '../../workout/presentation/pages/workout_dashboard_page.dart';

/// The Hub — a light dashboard into each module's depth. A two-column grid
/// of premium module cards, each with a tinted icon chip in its module
/// colour and a live stat line reading straight from that module's own
/// repository (see each `_XTile`) — a snapshot of "what's happening in each
/// area of my life right now", not just a launcher.
class HubPage extends StatelessWidget {
  const HubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Container(
      color: AppColors.ground,
      // The page is a single top-aligned scroll view: header, then the grid
      // directly beneath it. The grid is shrink-wrapped (`shrinkWrap: true`
      // + `NeverScrollableScrollPhysics`) so it sizes to its own content —
      // GridView.count derives row height from tile width alone, so left in
      // an `Expanded` its scroll viewport stretched taller than its content
      // and left a large dead band above the nav; shrink-wrapping removes
      // that. The outer `SingleChildScrollView` is the only scroller, so on
      // a short device (or a large text scale) the whole thing scrolls
      // naturally with nothing clipped. The bottom nav lives in
      // `HomeShell`'s Scaffold, independent of this content; because
      // `extendBody: true` draws the page behind it, the bottom scroll
      // padding reserves the nav bar's own exact rendered height
      // (`ZivoBottomBarMetrics.height`, safe-area inset included) so the
      // last row always clears it with a small, consistent breathing room.
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen,
          media.padding.top + 20,
          AppSpacing.screen,
          ZivoBottomBarMetrics.height(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hub', style: AppText.greeting),
            const SizedBox(height: 4),
            Text('Everything, one tap away.', style: AppText.aside),
            const SizedBox(height: 26),
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              // Taller than the icon+label-only ratio (was 1.32) — the extra
              // height is what carries each tile's live stat line without
              // cramping it against the label.
              childAspectRatio: 1.05,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                _WorkoutTile(),
                _DietTile(),
                _ExpensesTile(),
                _MomentsTile(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Workout's tile: the same up-next day + resume/start signal as Today's own
/// Training card (`resolveUpNext`), so Hub can't drift from it.
class _WorkoutTile extends StatelessWidget {
  const _WorkoutTile();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<WorkoutPlan?>(
      stream: scope.workoutPlans.watchActivePlan(),
      initialData: scope.workoutPlans.activePlan,
      builder: (context, planSnapshot) {
        final plan = planSnapshot.data;
        if (plan == null) return _shell(context, stat: 'No plan yet');
        return StreamBuilder<LiveSession?>(
          stream: scope.workoutSessions.watchActiveSession(),
          initialData: scope.workoutSessions.activeSession,
          builder: (context, sessionSnapshot) {
            final selection = resolveUpNext(plan, sessionSnapshot.data);
            final day = selection.day;
            final stat = day == null
                ? 'No plan yet'
                : selection.resumable != null
                ? '${day.label} · resume'
                : '${day.label} · up next';
            return _shell(context, stat: stat);
          },
        );
      },
    );
  }

  Widget _shell(BuildContext context, {required String stat}) {
    return _ModuleTileShell(
      icon: AppIcons.workout,
      color: AppColors.pulse,
      wash: AppColors.pulseWash,
      label: 'Workout',
      stat: stat,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const WorkoutDashboardPage())),
    );
  }
}

/// Diet's tile: today's eaten/kcal-left summary, same `dietDaySummary` the
/// Diet page's own hero and Today's glance row read.
class _DietTile extends StatelessWidget {
  const _DietTile();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<DietPlan?>(
      stream: scope.diet.watchActivePlan(),
      initialData: scope.diet.activePlan,
      builder: (context, planSnapshot) {
        final now = DateTime.now();
        final day = dayForDate(planSnapshot.data, now);
        if (day == null) return _shell(context, stat: 'No plan yet');
        return StreamBuilder<Set<String>>(
          stream: scope.diet.watchConsumed(now),
          initialData: const <String>{},
          builder: (context, consumedSnapshot) {
            final summary = dietDaySummary(
              day,
              consumedSnapshot.data ?? const <String>{},
            );
            return _shell(
              context,
              stat:
                  // "meals" and "left" dropped — the tile is already
                  // labelled "Diet", so "X of Y" reads unambiguously
                  // without the former, and the latter is what actually
                  // pushed this to a 3rd line at a standard phone width
                  // (measured in hub_page_test.dart) — "of 3" vs "3/3"
                  // barely moved the needle, "left" alone was the
                  // difference between fitting in 2 lines and not.
                  '${summary.eaten} of ${summary.total} · ${summary.kcalLeft} kcal',
            );
          },
        );
      },
    );
  }

  Widget _shell(BuildContext context, {required String stat}) {
    return _ModuleTileShell(
      icon: AppIcons.diet,
      color: AppColors.pulse,
      wash: AppColors.pulseWash,
      label: 'Diet',
      stat: stat,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const DietPlanPage())),
    );
  }
}

/// Expenses' tile: this week's spend, same `weekTotalMinor` + wallet
/// currency Today's Spending glance reads. Always shows a real number — a
/// week with nothing spent is still a fact, not a "no data yet" case.
class _ExpensesTile extends StatelessWidget {
  const _ExpensesTile();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final expenses = scope.expenses;
    final wallet = scope.wallet;
    return StreamBuilder<List<Expense>>(
      stream: expenses.watchAll(),
      initialData: expenses.current,
      builder: (context, snapshot) {
        final weekMinor = weekTotalMinor(
          snapshot.data ?? const <Expense>[],
          DateTime.now(),
        );
        if (wallet == null) {
          return _shell(
            context,
            stat: 'EGP ${formatAmount(weekMinor)} this week',
          );
        }
        return StreamBuilder<Wallet?>(
          stream: wallet.watch(),
          initialData: wallet.current,
          builder: (context, walletSnapshot) {
            final currency = walletSnapshot.data?.currency ?? 'EGP';
            return _shell(
              context,
              stat: '$currency ${formatAmount(weekMinor)} this week',
            );
          },
        );
      },
    );
  }

  Widget _shell(BuildContext context, {required String stat}) {
    return _ModuleTileShell(
      icon: AppIcons.expenses,
      color: AppColors.solar,
      wash: AppColors.solarWash,
      label: 'Expenses',
      stat: stat,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ExpensesListPage())),
    );
  }
}

/// Moments' tile: a simple honest count — no fabricated "last added X ago"
/// beyond what's actually there.
class _MomentsTile extends StatelessWidget {
  const _MomentsTile();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<Moment>>(
      stream: scope.moments.watchAll(),
      initialData: scope.moments.current,
      builder: (context, snapshot) {
        final count = (snapshot.data ?? const <Moment>[]).length;
        final stat = count == 0
            ? 'No moments yet'
            : '$count moment${count == 1 ? '' : 's'}';
        return _ModuleTileShell(
          icon: AppIcons.moments,
          color: AppColors.ember,
          wash: AppColors.emberWash,
          label: 'Moments',
          stat: stat,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MomentsTimelinePage()),
          ),
        );
      },
    );
  }
}

/// The shared visual shell for a Hub tile: a tinted icon chip, the module
/// label, and a live stat line underneath. Data-fetching lives entirely in
/// each concrete `_XTile` above — this is presentation only, reused so every
/// tile shares one exact card language.
class _ModuleTileShell extends StatelessWidget {
  const _ModuleTileShell({
    required this.icon,
    required this.color,
    required this.wash,
    required this.label,
    required this.stat,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color wash;
  final String label;
  final String stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.hairline),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: wash,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, size: 23, color: color),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppText.rowTitle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: MediaQuery.textScalerOf(
                        context,
                      ).clamp(maxScaleFactor: 1.3),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      stat,
                      style: AppText.meta.copyWith(color: AppColors.ink3),
                      // 2 lines, not 1 — a couple of stats (Diet's "X of Y
                      // meals · N kcal left") run long enough to ellipsize
                      // the unit off the end at default text scale on a
                      // standard phone width. The taller 1.05-ratio tile has
                      // the headroom, and the other tiles' shorter stats
                      // just naturally sit on one line.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textScaler: MediaQuery.textScalerOf(
                        context,
                      ).clamp(maxScaleFactor: 1.3),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
