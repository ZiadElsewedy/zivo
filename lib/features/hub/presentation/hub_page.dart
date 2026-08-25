
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/scope/app_scope.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/util/money.dart';
import '../../../core/util/time_ago.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/rise_in.dart';
import '../../diet/domain/diet_plan.dart';
import '../../diet/domain/diet_summary.dart';
import '../../diet/presentation/pages/diet_plan_page.dart';
import '../../diet/presentation/today_diet.dart';
import '../../expenses/domain/expense.dart';
import '../../expenses/domain/expense_category.dart';
import '../../expenses/domain/expense_repository.dart';
import '../../expenses/domain/wallet.dart';
import '../../expenses/presentation/pages/expenses_list_page.dart';
import '../../home/presentation/header_builder.dart';
import '../../moments/domain/moment.dart';
import '../../moments/presentation/pages/moments_timeline_page.dart';
import '../../shell/presentation/widgets/zivo_bottom_bar.dart';
import '../../workout/domain/live_session.dart';
import '../../workout/domain/session_status.dart';
import '../../workout/domain/up_next_selection.dart';
import '../../workout/domain/workout_plan.dart';
import '../../workout/presentation/pages/workout_dashboard_page.dart';
import '../../workout/presentation/widgets/up_next_workout_card.dart';

/// The Hub — a light dashboard into each module's depth. A two-column grid
/// of premium module cards, each with a glowing gradient icon chip in its
/// module colour, a barely-there hue wash bleeding into the card's corner,
/// and a live stat line reading straight from that module's own repository
/// (see each `_XTile`) — a snapshot of "what's happening in each area of my
/// life right now", not just a launcher.
///
/// Shares Today's atmospheric backdrop (radial ground gradient + soft aura
/// blobs) so the two dashboard surfaces read as one material world.
class HubPage extends StatelessWidget {
  const HubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return DecoratedBox(
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
          // Ambient depth — one warm glow near the title, one cool counterweight
          // lower-left. Purely decorative (and pointer-transparent).
          const Positioned(
            top: -30,
            right: -70,
            child: _AuraBlob(color: AppColors.ember, size: 210),
          ),
          const Positioned(
            top: 320,
            left: -90,
            child: _AuraBlob(color: AppColors.iris, size: 200),
          ),
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
          Positioned.fill(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screen,
                media.padding.top + 24,
                AppSpacing.screen,
                ZivoBottomBarMetrics.height(context),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Header(),
                  const SizedBox(height: 24),
                  const _TrainingSection(),
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
                  const _RecentSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Date eyebrow over the display title — the same editorial cadence Today's
/// header uses, so every dashboard opens with the same voice.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return RiseIn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatTodayDate(DateTime.now()).toUpperCase(),
            style: AppText.dateLabel,
          ),
          const SizedBox(height: 7),
          Text('Hub', style: AppText.greeting),
          const SizedBox(height: 5),
          Text(
            'Everything, one tap away.',
            style: AppText.aside.copyWith(
              fontSize: 16.5,
              color: AppColors.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's training, front and center on the Hub — the SAME [UpNextWorkoutCard]
/// the Today page and the Workout dashboard render, driven by the same
/// `resolveUpNext`, so the user can start (or resume) a workout directly from
/// Home without detouring through the Workout tab. Silently absent when there's
/// no plan/day to offer — the Workout tile below still covers that case.
class _TrainingSection extends StatelessWidget {
  const _TrainingSection();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<WorkoutPlan?>(
      stream: scope.workoutPlans.watchActivePlan(),
      initialData: scope.workoutPlans.activePlan,
      builder: (context, planSnapshot) {
        final plan = planSnapshot.data;
        if (plan == null) return const SizedBox.shrink();
        return StreamBuilder<LiveSession?>(
          stream: scope.workoutSessions.watchActiveSession(),
          initialData: scope.workoutSessions.activeSession,
          builder: (context, sessionSnapshot) {
            final selection = resolveUpNext(plan, sessionSnapshot.data);
            final day = selection.day;
            if (day == null) return const SizedBox.shrink();
            return RiseIn(
              delay: const Duration(milliseconds: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 12),
                    child: Text('TRAINING', style: AppText.sectionLabel),
                  ),
                  UpNextWorkoutCard(
                    plan: plan,
                    day: day,
                    resumable: selection.resumable,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// A soft, blurred wash of color for atmosphere behind the header — the
/// quiet "energy" glow behind a premium dashboard. Purely decorative.
class _AuraBlob extends StatelessWidget {
  const _AuraBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // A radial gradient, not an ImageFiltered blur — visually the
          // same soft glow at a fraction of the GPU cost, which matters
          // during page transitions (blur layers repaint per frame).
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.14),
              color.withValues(alpha: 0.0),
            ],
          ),
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
    return RiseIn(
      delay: const Duration(milliseconds: 40),
      child: StreamBuilder<WorkoutPlan?>(
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
      ),
    );
  }

  Widget _shell(BuildContext context, {required String stat}) {
    return _ModuleTileShell(
      icon: AppIcons.workout,
      color: AppColors.pulse,
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
    return RiseIn(
      delay: const Duration(milliseconds: 90),
      child: StreamBuilder<DietPlan?>(
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
      ),
    );
  }

  Widget _shell(BuildContext context, {required String stat}) {
    return _ModuleTileShell(
      icon: AppIcons.diet,
      color: AppColors.pulse,
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
    return RiseIn(
      delay: const Duration(milliseconds: 140),
      child: StreamBuilder<List<Expense>>(
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
      ),
    );
  }

  Widget _shell(BuildContext context, {required String stat}) {
    return _ModuleTileShell(
      icon: AppIcons.expenses,
      color: AppColors.solar,
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
    return RiseIn(
      delay: const Duration(milliseconds: 190),
      child: StreamBuilder<List<Moment>>(
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
            label: 'Moments',
            stat: stat,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MomentsTimelinePage()),
            ),
          );
        },
      ),
    );
  }
}

/// The shared visual shell for a Hub tile: a gradient-glowing icon chip, the
/// module label, and a live stat line underneath, on a card whose top corner
/// carries a whisper of the module hue. Data-fetching lives entirely in each
/// concrete `_XTile` above — this is presentation only, reused so every tile
/// shares one exact card language.
///
/// The decoration lives on `Ink` (not an inner `Container`) so the InkWell's
/// splash composites over the gradient rather than beneath it.
class _ModuleTileShell extends StatelessWidget {
  const _ModuleTileShell({
    required this.icon,
    required this.color,
    required this.label,
    required this.stat,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.card,
            // A whisper of the module hue pooled into the top-left corner —
            // identity without noise.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.065),
                color.withValues(alpha: 0.0),
              ],
            ),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
            boxShadow: AppShadows.card,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _GlowingIconChip(icon: icon, color: color),
                      Icon(
                        AppIcons.chevron,
                        size: 15,
                        color: AppColors.ink3.withValues(alpha: 0.65),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppText.rowTitle.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: 1.3),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stat,
                        style: AppText.meta.copyWith(
                          color: AppColors.ink3,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
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
      ),
    );
  }
}

/// The tile's icon mark — a rounded square filled with a diagonal gradient of
/// the module hue, edged with a faint tinted border and lifted on a soft
/// colored glow. The single strongest identity carrier on each tile.
class _GlowingIconChip extends StatelessWidget {
  const _GlowingIconChip({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.30),
            color.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.30),
            blurRadius: 22,
            spreadRadius: -6,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, size: 23, color: color),
    );
  }
}

/// One thing that happened, from any module — the shared shape [_mergeRecent]
/// folds Workout/Expenses/Moments into before sorting.
class _RecentItem {
  const _RecentItem({
    required this.at,
    required this.icon,
    required this.color,
    required this.text,
    required this.onTap,
  });

  final DateTime at;
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onTap;
}

/// "Recent" — the last few things that happened across Workout, Expenses,
/// and Moments, newest first. Diet is deliberately excluded: `watchConsumed`
/// carries no order/timestamp, and a real cross-day "recently eaten" query
/// would need a new Firestore composite index — real infra, not a
/// client-only add, so it waits for whenever Diet next touches the backend
/// rather than being faked here.
///
/// Three streams the tiles above already pay for, merged client-side (same
/// nested-`StreamBuilder` idiom used everywhere else in this codebase) —
/// nothing renders at all when every source is empty, matching how the rest
/// of the app degrades (Today's own "Get started" card already carries that
/// message; Hub doesn't need to repeat it).
class _RecentSection extends StatelessWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<LiveSession>>(
      stream: scope.workoutSessions.watchAll(),
      initialData: scope.workoutSessions.current,
      builder: (context, sessionsSnapshot) {
        return StreamBuilder<List<Expense>>(
          stream: scope.expenses.watchAll(),
          initialData: scope.expenses.current,
          builder: (context, expensesSnapshot) {
            return StreamBuilder<List<Moment>>(
              stream: scope.moments.watchAll(),
              initialData: scope.moments.current,
              builder: (context, momentsSnapshot) {
                final items = _mergeRecent(
                  context,
                  sessions: sessionsSnapshot.data ?? const <LiveSession>[],
                  expenses: expensesSnapshot.data ?? const <Expense>[],
                  moments: momentsSnapshot.data ?? const <Moment>[],
                );
                if (items.isEmpty) return const SizedBox.shrink();
                return RiseIn(
                  delay: const Duration(milliseconds: 240),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 12),
                        child: Text('RECENT', style: AppText.sectionLabel),
                      ),
                      Material(
                        // The rows' own InkWell needs a Material ancestor —
                        // Hub has no Scaffold of its own (only HomeShell's,
                        // in production), same reasoning as `_ModuleTileShell`
                        // above.
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            border: Border.all(color: AppColors.hairline),
                            boxShadow: AppShadows.card,
                          ),
                          child: Column(
                            children: [
                              for (var i = 0; i < items.length; i++)
                                _RecentRow(
                                  item: items[i],
                                  last: i == items.length - 1,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Folds the three modules' already-loaded lists into one time-sorted,
/// capped list. Pure function of the snapshots (no I/O) so it's cheap to
/// recompute on every rebuild.
List<_RecentItem> _mergeRecent(
  BuildContext context, {
  required List<LiveSession> sessions,
  required List<Expense> expenses,
  required List<Moment> moments,
}) {
  final items = <_RecentItem>[];

  for (final s in sessions) {
    // Only completed sessions read as "activity" — an abandoned one wasn't
    // really a workout, and an active one is already the Workout tile's job.
    final completedAt = s.completedAt;
    if (s.status != SessionStatus.completed || completedAt == null) continue;
    items.add(
      _RecentItem(
        at: completedAt,
        icon: AppIcons.workout,
        color: AppColors.pulse,
        text: 'Completed ${s.dayLabel}',
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const WorkoutDashboardPage())),
      ),
    );
  }

  for (final e in expenses) {
    items.add(
      _RecentItem(
        at: e.spentAt,
        icon: AppIcons.expenses,
        color: AppColors.solar,
        text:
            '${formatAmount(e.amountMinor)} ${e.currency} on '
            '${_expenseCategoryLabel(e.categoryId)}',
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ExpensesListPage())),
      ),
    );
  }

  for (final m in moments) {
    final caption = m.caption.trim();
    items.add(
      _RecentItem(
        at: m.takenAt,
        icon: AppIcons.moments,
        color: AppColors.ember,
        text: caption.isEmpty
            ? 'Added a moment'
            : (caption.length > 40 ? '${caption.substring(0, 40)}…' : caption),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MomentsTimelinePage())),
      ),
    );
  }

  items.sort((a, b) => b.at.compareTo(a.at));
  return items.take(5).toList(growable: false);
}

/// Maps a stored expense `categoryId` to a display label — built-ins only.
/// A custom category's id is an opaque `microsecondsSinceEpoch` string (see
/// `add_category_sheet.dart`), never a readable slug, so anything not in
/// [kBuiltInCategories] degrades to a generic label rather than leaking a
/// raw id into the row. Deliberately skips `resolveCategory` (which would
/// need the nullable `CategoryRepository` as a 4th stream just to prettify
/// one label in a small activity row).
String _expenseCategoryLabel(String categoryId) {
  for (final category in kBuiltInCategories) {
    if (category.id == categoryId) return category.label;
  }
  return 'Expense';
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.item, required this.last});

  final _RecentItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        item.onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: AppColors.hairline)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    item.color.withValues(alpha: 0.22),
                    item.color.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: item.color.withValues(alpha: 0.14)),
              ),
              child: Icon(item.icon, size: 16, color: item.color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                item.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              timeAgo(item.at, DateTime.now()),
              style: AppText.meta.copyWith(
                color: AppColors.ink3,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
