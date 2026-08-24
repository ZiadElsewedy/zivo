import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
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
/// dashboard landing. The landing answers "what am I doing now"; this answers
/// "how is it going": the current split, how the up-next day is trending, and
/// what was logged recently, plus one explicit way into each deeper
/// destination (Analysis, History, Splits).
///
/// Reads the same live [LiveSession] stream the dashboard does, so the two
/// screens can never disagree. Deliberately kept as one flat section list —
/// the final home for these blocks is still open, and a flat list is trivial
/// to re-cut.
class WorkoutProgressPage extends StatelessWidget {
  const WorkoutProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.ink2),
        title: Text(
          'Progress',
          style: AppText.cardTitle.copyWith(color: AppColors.ink),
        ),
      ),
      body: StreamBuilder<WorkoutPlan?>(
        stream: scope.workoutPlans.watchActivePlan(),
        initialData: scope.workoutPlans.activePlan,
        builder: (context, planSnap) {
          final plan = planSnap.data;
          return StreamBuilder<List<LiveSession>>(
            stream: scope.workoutSessions.watchAll(),
            initialData: scope.workoutSessions.current,
            builder: (context, sessionsSnap) {
              final sessions = sessionsSnap.data ?? const <LiveSession>[];
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
                  if (analysis != null) ...[
                    const WorkoutSectionLabel('Progress'),
                    const SizedBox(height: 10),
                    ProgressSummaryCard(analysis: analysis),
                    const SizedBox(height: 30),
                  ],
                  if (plan != null) ...[
                    const WorkoutSectionLabel('Current split'),
                    const SizedBox(height: 10),
                    SplitBreakdownCard(plan: plan, stats: stats),
                    const SizedBox(height: 30),
                  ],
                  Row(
                    children: [
                      const Expanded(
                        child: WorkoutSectionLabel('Recent activity'),
                      ),
                      if (stats.recentSessions.isNotEmpty)
                        _SeeAllLink(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const WorkoutHistoryPage(),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (stats.recentSessions.isEmpty)
                    const _EmptyCard(label: "You haven't logged a session yet.")
                  else
                    for (final session in stats.recentSessions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RecentSessionRow(
                          session: session,
                          now: now,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  SessionDetailsPage(session: session),
                            ),
                          ),
                        ),
                      ),
                  const SizedBox(height: 30),
                  const WorkoutSectionLabel('Go deeper'),
                  const SizedBox(height: 10),
                  _DestinationCard(
                    destinations: [
                      _Destination(
                        icon: Icons.trending_up_rounded,
                        label: 'Full analysis',
                        detail: 'Exercise-by-exercise, per training day',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const WorkoutAnalysisPage(),
                          ),
                        ),
                      ),
                      _Destination(
                        icon: Icons.history_rounded,
                        label: 'All history',
                        detail: 'Every session you have logged',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const WorkoutHistoryPage(),
                          ),
                        ),
                      ),
                      _Destination(
                        icon: Icons.dashboard_customize_rounded,
                        label: 'Splits',
                        detail: 'Switch or edit your training splits',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SplitManagementPage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WorkoutAnalysisPage()),
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.hairline2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
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
                  if (overall != null) _AnalysisVerdictBadge(verdict: overall),
                ],
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
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.pulse,
                  ),
                ],
              ),
            ],
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
          Text(
            label,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SplitManagementPage()),
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.hairline2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      plan.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowTitle.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PlanLinkButton(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WorkoutPlanPage()),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.ink3,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${stats.totalCompletedSessions} session${stats.totalCompletedSessions == 1 ? '' : 's'} completed',
                style: AppText.meta.copyWith(color: AppColors.ink3),
              ),
              if (byDay.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in byDay.entries)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.pulse.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          '${entry.key} · ${entry.value}',
                          style: AppText.meta.copyWith(
                            color: AppColors.pulse,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
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
    return Material(
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
    );
  }
}

class _SeeAllLink extends StatelessWidget {
  const _SeeAllLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
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
              const Icon(
                Icons.chevron_right_rounded,
                size: 15,
                color: AppColors.ink3,
              ),
            ],
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline2),
          ),
          child: Row(
            children: [
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
                child: Text(
                  label,
                  style: AppText.meta.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.ink3,
                size: 18,
              ),
            ],
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
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Text(label, style: AppText.aside.copyWith(color: AppColors.ink2)),
    );
  }
}

class _Destination {
  const _Destination({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
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
        border: Border.all(color: AppColors.hairline2),
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
    return Material(
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
              Icon(destination.icon, size: 20, color: AppColors.ink2),
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
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.ink3,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
