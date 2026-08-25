import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/util/time_ago.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../domain/day_progress_analysis.dart';
import '../../domain/live_session.dart';
import '../../domain/progress_comparison.dart';
import '../../domain/session_status.dart';
import '../../domain/training_dashboard_stats.dart';
import '../../domain/up_next_selection.dart';
import '../../domain/workout_plan.dart';
import '../widgets/animated_stat_value.dart';
import '../widgets/staggered_reveal.dart';
import '../widgets/verdict_style.dart';
import '../widgets/workout_section_label.dart';
import 'session_details_page.dart';
import 'split_management_page.dart';
import 'workout_analysis_page.dart';
import 'workout_dashboard_page.dart' show formatDurationShort;
import 'workout_history_page.dart';
import 'workout_plan_page.dart';

/// The Workout tab's second screen — everything that used to crowd the
/// dashboard landing. The landing answers "what am I doing now"; this
/// answers "how is it going", read top-to-bottom as three questions, each
/// with its own visual identity:
///
/// 1. **How much** — an overview strip of four instruments, each in its own
///    hue (this week pulse, streak ember, total iris, avg length solar).
/// 2. **How well** — the active up-next day's verdict, then the current
///    split with its per-day session distribution as proportional bars
///    (replacing the old cramped pill wrap).
/// 3. **What happened** — recent activity, then the deeper destinations.
///
/// Reads the same live [LiveSession] stream the dashboard does, so the two
/// screens can never disagree.
class WorkoutProgressPage extends StatelessWidget {
  const WorkoutProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.1),
            radius: 1.15,
            colors: [Color(0xFF182016), AppColors.ground, Color(0xFF0E0B08)],
            stops: [0.0, 0.52, 1.0],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -60,
              right: -70,
              child: _AuraBlob(color: AppColors.pulse, size: 200),
            ),
            SafeArea(
              child: StreamBuilder<WorkoutPlan?>(
                stream: scope.workoutPlans.watchActivePlan(),
                initialData: scope.workoutPlans.activePlan,
                builder: (context, planSnap) {
                  final plan = planSnap.data;
                  return StreamBuilder<List<LiveSession>>(
                    stream: scope.workoutSessions.watchAll(),
                    initialData: scope.workoutSessions.current,
                    builder: (context, sessionsSnap) {
                      final sessions =
                          sessionsSnap.data ?? const <LiveSession>[];
                      final now = DateTime.now();
                      final stats = computeTrainingDashboardStats(
                        sessions: sessions,
                        now: now,
                      );
                      final selection = plan == null
                          ? null
                          : resolveUpNext(plan, _firstActive(sessions));
                      final analysis = (plan == null || selection?.day == null)
                          ? null
                          : analyzeDayProgress(
                              day: selection!.day!,
                              planId: plan.id,
                              allSessions: sessions,
                            );

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(22, 12, 22, 110),
                        children: [
                          StaggeredReveal(
                            index: 0,
                            child: const _ProgressHeader(),
                          ),
                          const SizedBox(height: 24),
                          // ---- HOW MUCH ---------------------------------
                          StaggeredReveal(
                            index: 0,
                            child: _OverviewStrip(stats: stats),
                          ),
                          const SizedBox(height: 32),
                          // ---- HOW WELL ---------------------------------
                          if (analysis != null) ...[
                            StaggeredReveal(
                              index: 1,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const WorkoutSectionLabel('Progress'),
                                  const SizedBox(height: 10),
                                  ProgressSummaryCard(analysis: analysis),
                                ],
                              ),
                            ),
                            const SizedBox(height: 30),
                          ],
                          if (plan != null) ...[
                            StaggeredReveal(
                              index: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const WorkoutSectionLabel('Current split'),
                                  const SizedBox(height: 10),
                                  SplitBreakdownCard(plan: plan, stats: stats),
                                ],
                              ),
                            ),
                            const SizedBox(height: 30),
                          ],
                          // ---- WHAT HAPPENED ----------------------------
                          StaggeredReveal(
                            index: 3,
                            child: Row(
                              children: [
                                const Expanded(
                                  child: WorkoutSectionLabel('Recent activity'),
                                ),
                                if (stats.recentSessions.isNotEmpty)
                                  _SeeAllLink(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const WorkoutHistoryPage(),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (stats.recentSessions.isEmpty)
                            StaggeredReveal(
                              index: 4,
                              child: const _EmptyCard(
                                label: "You haven't logged a session yet.",
                              ),
                            )
                          else
                            for (final (i, session)
                                in stats.recentSessions.indexed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: StaggeredReveal(
                                  index: 4 + i,
                                  child: _RecentSessionRow(
                                    session: session,
                                    now: now,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => SessionDetailsPage(
                                            session: session,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                          const SizedBox(height: 30),
                          StaggeredReveal(
                            index: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const WorkoutSectionLabel('Go deeper'),
                                const SizedBox(height: 10),
                                _DestinationCard(
                                  destinations: [
                                    _Destination(
                                      icon: AppIcons.analysis,
                                      accent: AppColors.pulse,
                                      label: 'Full analysis',
                                      detail:
                                          'Exercise-by-exercise, per training day',
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const WorkoutAnalysisPage(),
                                          ),
                                        );
                                      },
                                    ),
                                    _Destination(
                                      icon: AppIcons.history,
                                      accent: AppColors.iris,
                                      label: 'All history',
                                      detail: 'Every session you have logged',
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const WorkoutHistoryPage(),
                                          ),
                                        );
                                      },
                                    ),
                                    _Destination(
                                      icon: AppIcons.splits,
                                      accent: AppColors.solar,
                                      label: 'Splits',
                                      detail:
                                          'Switch or edit your training splits',
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const SplitManagementPage(),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
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

/// The pushed-page header — back chip and display title.
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PressableScale(
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
                child: const Icon(
                  AppIcons.back,
                  size: 18,
                  color: AppColors.ink2,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Progress',
            style: AppText.greeting.copyWith(fontSize: 30),
          ),
        ),
      ],
    );
  }
}

/// The "how much" answer — four instruments, one per hue, as a 2×2 of
/// quiet tiles. Distinct colors so the grid scans as four different
/// signals rather than four identical numbers.
class _OverviewStrip extends StatelessWidget {
  const _OverviewStrip({required this.stats});

  final TrainingDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _OverviewTile(
                icon: AppIcons.sessions,
                accent: AppColors.pulse,
                value: '${stats.sessionsThisWeek}',
                label: 'This week',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _OverviewTile(
                icon: AppIcons.streak,
                accent: AppColors.ember,
                value: '${stats.currentStreakDays}',
                label: 'Day streak',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _OverviewTile(
                icon: AppIcons.analysis,
                accent: AppColors.iris,
                value: '${stats.totalCompletedSessions}',
                label: 'Total sessions',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _OverviewTile(
                icon: AppIcons.timer,
                accent: AppColors.solar,
                value: stats.averageSessionDuration == null
                    ? '—'
                    : formatDurationShort(stats.averageSessionDuration!),
                label: 'Avg length',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.icon,
    required this.accent,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color accent;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
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
                  accent.withValues(alpha: 0.28),
                  accent.withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: accent.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.26),
                  blurRadius: 14,
                  spreadRadius: -3,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedStatValue(
                value: value,
                style: AppText.heroNumber.copyWith(
                  fontSize: 21,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: AppText.meta.copyWith(
                  color: AppColors.ink3,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

LiveSession? _firstActive(List<LiveSession> sessions) {
  for (final s in sessions) {
    if (s.status == SessionStatus.active) return s;
  }
  return null;
}

/// The active up-next day's overall verdict. Tapping anywhere opens the full
/// [WorkoutAnalysisPage] for the day-by-day, exercise-by-exercise breakdown.
class ProgressSummaryCard extends StatelessWidget {
  const ProgressSummaryCard({required this.analysis, super.key});

  final DayProgressAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final overall = analysis.overallVerdict;
    final (headline, color) = switch (overall) {
      null => (
        analysis.sessionCount == 0 ? "Let's get started" : 'Almost there',
        AppColors.ink2,
      ),
      ProgressVerdict.progressing => ('Progressing', AppColors.pulse),
      ProgressVerdict.matched => ('Holding steady', AppColors.ink2),
      ProgressVerdict.down => ('Slipping', AppColors.flare),
    };
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WorkoutAnalysisPage()),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.card,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.09),
                  color.withValues(alpha: 0.02),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.14)),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.10),
                  blurRadius: 28,
                  spreadRadius: -8,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            color.withValues(alpha: 0.28),
                            color.withValues(alpha: 0.10),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        overall == null
                            ? AppIcons.analysis
                            : switch (overall) {
                                ProgressVerdict.progressing => AppIcons.trendUp,
                                ProgressVerdict.matched => AppIcons.minus,
                                ProgressVerdict.down => AppIcons.trendDown,
                              },
                        size: 16,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        analysis.day.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.rowTitle.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (overall != null)
                      _AnalysisVerdictBadge(verdict: overall),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  headline,
                  style: AppText.cardTitle.copyWith(
                    fontSize: 24,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  overall == null
                      ? (analysis.sessionCount == 0
                            ? 'Log ${analysis.day.label} to start tracking progress.'
                            : "Log ${analysis.day.label} once more to see how you're trending.")
                      : '${analysis.improvedCount} improved · ${analysis.matchedCount} matched · '
                            '${analysis.regressedCount} regressed',
                  style: AppText.meta.copyWith(color: AppColors.ink3),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See full analysis',
                      style: AppText.meta.copyWith(
                        color: AppColors.pulse,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Icon(
                      AppIcons.chevron,
                      size: 16,
                      color: AppColors.pulse,
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

class _AnalysisVerdictBadge extends StatelessWidget {
  const _AnalysisVerdictBadge({required this.verdict});

  final ProgressVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = verdictStyle(verdict);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          // Verdict color is the state, not decoration — animate it with
          // the label rather than snapping when a new session re-verdicts.
          AnimatedStatValue(
            value: label,
            style: AppText.meta.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// The current split as a real distribution read: plan identity up top
/// (gradient mark, name, total), then each training day as a proportional
/// bar — how many sessions each day has actually absorbed. Replaces the old
/// cramped pill wrap, which turned six data points into six identical
/// chips. Tapping opens Splits; the Plan chip opens the plan viewer.
class SplitBreakdownCard extends StatelessWidget {
  const SplitBreakdownCard({
    required this.plan,
    required this.stats,
    super.key,
  });

  final WorkoutPlan plan;
  final TrainingDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final byDay = stats.sessionCountByDayLabel;
    final maxCount = byDay.values.fold(1, (a, b) => a > b ? a : b);
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SplitManagementPage()),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.hairline),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.pulse.withValues(alpha: 0.28),
                            AppColors.pulse.withValues(alpha: 0.10),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.pulse.withValues(alpha: 0.18),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.pulse.withValues(alpha: 0.24),
                            blurRadius: 16,
                            spreadRadius: -4,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        AppIcons.splits,
                        size: 19,
                        color: AppColors.pulse,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.rowTitle.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          AnimatedStatValue(
                            value:
                                '${stats.totalCompletedSessions} session${stats.totalCompletedSessions == 1 ? '' : 's'} completed',
                            style: AppText.meta.copyWith(color: AppColors.ink3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _PlanLinkButton(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const WorkoutPlanPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      AppIcons.chevron,
                      color: AppColors.ink3,
                      size: 20,
                    ),
                  ],
                ),
                if (byDay.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  // Per-day distribution — proportional bars, so "which day
                  // do I actually train" reads in one glance.
                  for (final entry in byDay.entries) ...[
                    _DayDistributionRow(
                      label: entry.key,
                      count: entry.value,
                      fraction: entry.value / maxCount,
                    ),
                    if (entry.key != byDay.keys.last)
                      const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayDistributionRow extends StatelessWidget {
  const _DayDistributionRow({
    required this.label,
    required this.count,
    required this.fraction,
  });

  final String label;
  final int count;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.meta.copyWith(color: AppColors.ink2, fontSize: 12.5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(height: 7, color: AppColors.hairline),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction.clamp(0.06, 1.0),
                  child: Container(
                    height: 7,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF2BD99B), AppColors.pulse],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 22,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: AppText.meta.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// A small "Manage"-style header action reaching the full plan editor — kept
/// as its own tappable chip (so it doesn't fall through to the card's own
/// tap-to-Splits) rather than a second full-card gesture.
class _PlanLinkButton extends StatelessWidget {
  const _PlanLinkButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              'Plan',
              style: AppText.meta.copyWith(
                color: AppColors.ink2,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeeAllLink extends StatelessWidget {
  const _SeeAllLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'See all',
                  style: AppText.meta.copyWith(
                    color: AppColors.ink2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(AppIcons.chevron, size: 15, color: AppColors.ink3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentSessionRow extends StatelessWidget {
  const _RecentSessionRow({
    required this.session,
    required this.now,
    required this.onTap,
  });

  final LiveSession session;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (session.status) {
      SessionStatus.completed => ('Completed', AppColors.pulse),
      SessionStatus.active => ('In progress', AppColors.solar),
      SessionStatus.abandoned => ('Not completed', AppColors.ink3),
    };
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
              boxShadow: AppShadows.card,
            ),
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
                        color.withValues(alpha: 0.26),
                        color.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    switch (session.status) {
                      SessionStatus.completed => AppIcons.trendUp,
                      SessionStatus.active => AppIcons.bolt,
                      SessionStatus.abandoned => AppIcons.minus,
                    },
                    size: 16,
                    color: color == AppColors.ink3 ? AppColors.ink2 : color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.dayLabel,
                        style: AppText.rowTitle.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        session.status == SessionStatus.completed
                            ? '${timeAgo(session.startedAt, now)} ago · ${formatDurationShort(session.elapsed)}'
                            : '${timeAgo(session.startedAt, now)} ago',
                        style: AppText.meta.copyWith(color: AppColors.ink3),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  // A live session going active→completed while this list is
                  // open is exactly a status changing under the user's eyes —
                  // color rides along with the label instead of snapping.
                  child: AnimatedStatValue(
                    value: label,
                    style: AppText.meta.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(AppIcons.chevron, color: AppColors.ink3, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Text(label, style: AppText.aside.copyWith(color: AppColors.ink2)),
    );
  }
}

class _Destination {
  const _Destination({
    required this.icon,
    required this.accent,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String detail;
  final VoidCallback onTap;
}

/// The deeper destinations as one grouped card of hairline-separated rows —
/// so no destination is lost when a block moves off the landing, and nothing
/// competes with the content above for attention.
class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.destinations});

  final List<_Destination> destinations;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          for (var i = 0; i < destinations.length; i++)
            _DestinationRow(
              destination: destinations[i],
              first: i == 0,
              last: i == destinations.length - 1,
            ),
        ],
      ),
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.destination,
    required this.first,
    required this.last,
  });

  final _Destination destination;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // Only the outer corners round, so the group reads as one card.
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(first ? 19 : 0),
            bottom: Radius.circular(last ? 19 : 0),
          ),
          onTap: destination.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              border: Border(
                top: first
                    ? BorderSide.none
                    : const BorderSide(color: AppColors.hairline),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        destination.accent.withValues(alpha: 0.28),
                        destination.accent.withValues(alpha: 0.10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: destination.accent.withValues(alpha: 0.18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: destination.accent.withValues(alpha: 0.26),
                        blurRadius: 14,
                        spreadRadius: -3,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Icon(
                    destination.icon,
                    size: 17,
                    color: destination.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.m + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.label,
                        style: AppText.rowTitle.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                          fontSize: 15.5,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        destination.detail,
                        style: AppText.meta.copyWith(
                          color: AppColors.ink3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(AppIcons.chevron, color: AppColors.ink3, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
