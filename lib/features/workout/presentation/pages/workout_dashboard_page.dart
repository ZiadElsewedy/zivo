import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../../core/util/time_ago.dart';
import '../../domain/body_weight_entry.dart';
import '../../domain/body_weight_repository.dart';
import '../../domain/live_session.dart';
import '../../domain/session_status.dart';
import '../../domain/training_dashboard_stats.dart';
import '../../domain/up_next_selection.dart';
import '../../domain/weight_trend.dart';
import '../../domain/workout_plan.dart';
import '../widgets/trend_chart.dart';
import '../widgets/up_next_workout_card.dart';
import 'split_management_page.dart';
import 'workout_analysis_page.dart';
import 'workout_history_page.dart';
import 'workout_plan_edit_page.dart';
import 'workout_plan_page.dart';

/// The Workout tab's landing page — a real training dashboard, not just a
/// session log. Reads [LiveSession]s directly (the record of what actually
/// happened, when, and for how long — never the lossy flat `Workout` log
/// `WorkoutHistoryPage` shows) to answer: did I train today, what/how
/// consistently am I training, how long do sessions run, and how's my
/// bodyweight moving. The existing Plan/Splits/Analysis/History pages stay
/// one tap away via the AppBar — this page is the overview, not a
/// replacement for their depth.
class WorkoutDashboardPage extends StatelessWidget {
  const WorkoutDashboardPage({super.key});

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
        title: Text('Workout', style: AppText.cardTitle.copyWith(color: AppColors.ink)),
        actions: [
          IconButton(
            tooltip: 'Plan',
            icon: const Icon(Icons.list_alt_rounded, color: AppColors.ink2),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WorkoutPlanPage()),
            ),
          ),
          IconButton(
            tooltip: 'Splits',
            icon: const Icon(Icons.layers_rounded, color: AppColors.ink2),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SplitManagementPage()),
            ),
          ),
          IconButton(
            tooltip: 'Analysis',
            icon: const Icon(Icons.trending_up_rounded, color: AppColors.ink2),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WorkoutAnalysisPage()),
            ),
          ),
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history_rounded, color: AppColors.ink2),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WorkoutHistoryPage()),
            ),
          ),
        ],
      ),
      body: StreamBuilder<WorkoutPlan?>(
        stream: scope.workoutPlans.watchActivePlan(),
        initialData: scope.workoutPlans.activePlan,
        builder: (context, planSnap) {
          if (planSnap.hasError) return const _DashboardErrorState();
          final plan = planSnap.data;
          final loading = plan == null && planSnap.connectionState == ConnectionState.waiting;
          if (loading) return const _DashboardLoadingState();
          if (plan == null) return const _NoPlanState();

          return StreamBuilder<List<LiveSession>>(
            stream: scope.workoutSessions.watchAll(),
            initialData: scope.workoutSessions.current,
            builder: (context, sessionsSnap) {
              if (sessionsSnap.hasError) return const _DashboardErrorState();
              final sessions = sessionsSnap.data ?? const <LiveSession>[];
              final now = DateTime.now();
              final stats = computeTrainingDashboardStats(sessions: sessions, now: now);
              final selection = resolveUpNext(plan, _firstActive(sessions));

              final bodyWeight = scope.bodyWeight;
              return StreamBuilder<List<BodyWeightEntry>>(
                stream: bodyWeight?.watchAll() ?? const Stream.empty(),
                initialData: bodyWeight?.current ?? const <BodyWeightEntry>[],
                builder: (context, weightSnap) {
                  final weightTrend = computeWeightTrend(
                    entries: weightSnap.data ?? const <BodyWeightEntry>[],
                    now: now,
                  );
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 110),
                    children: [
                      if (selection.day != null)
                        UpNextWorkoutCard(plan: plan, day: selection.day!, resumable: selection.resumable),
                      const SizedBox(height: 22),
                      _SectionLabel('This week'),
                      const SizedBox(height: 10),
                      _StatsGrid(stats: stats),
                      const SizedBox(height: 26),
                      _SectionLabel('Bodyweight'),
                      const SizedBox(height: 10),
                      _WeightCard(
                        trend: weightTrend,
                        onLogWeight: bodyWeight == null
                            ? null
                            : () => _showLogWeightSheet(context, bodyWeight),
                      ),
                      const SizedBox(height: 26),
                      _SectionLabel('Current split'),
                      const SizedBox(height: 10),
                      _SplitBreakdownCard(plan: plan, stats: stats),
                      const SizedBox(height: 26),
                      _SectionLabel('Recent activity'),
                      const SizedBox(height: 10),
                      if (stats.recentSessions.isEmpty)
                        _EmptyCard(label: "You haven't logged a session yet.")
                      else
                        for (final session in stats.recentSessions)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RecentSessionRow(session: session, now: now),
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

}

LiveSession? _firstActive(List<LiveSession> sessions) {
  for (final s in sessions) {
    if (s.status == SessionStatus.active) return s;
  }
  return null;
}

Future<void> _showLogWeightSheet(BuildContext context, BodyWeightRepository bodyWeight) {
  final controller = TextEditingController();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          20,
          22,
          MediaQuery.of(sheetContext).viewInsets.bottom + 22,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Log today\'s weight', style: AppText.cardTitle.copyWith(color: AppColors.ink)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}$'))],
              style: AppText.rowTitle.copyWith(color: AppColors.ink),
              decoration: InputDecoration(
                suffixText: 'kg',
                suffixStyle: AppText.body.copyWith(color: AppColors.ink3),
                filled: true,
                fillColor: AppColors.surfaceRaised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 18),
            PillButton(
              label: 'Save',
              icon: Icons.check_rounded,
              color: AppColors.solar,
              enabled: true,
              onTap: () {
                final value = double.tryParse(controller.text);
                if (value == null || value <= 0) return;
                bodyWeight.save(
                  BodyWeightEntry(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    weightKg: value,
                    loggedAt: DateTime.now(),
                  ),
                );
                Navigator.of(sheetContext).pop();
              },
            ),
          ],
        ),
      );
    },
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label.toUpperCase(), style: AppText.meta.copyWith(color: AppColors.ink3, letterSpacing: 0.8));
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final TrainingDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Sessions',
                value: '${stats.sessionsThisWeek}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                label: 'Streak',
                value: stats.currentStreakWeeks == 0
                    ? '—'
                    : '${stats.currentStreakWeeks} wk${stats.currentStreakWeeks == 1 ? '' : 's'}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Avg duration',
                value: stats.averageSessionDuration == null
                    ? '—'
                    : formatDurationShort(stats.averageSessionDuration!),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatTile(
                label: 'Avg start',
                value: stats.averageStartMinutesSinceMidnight == null
                    ? '—'
                    : formatClockTime(stats.averageStartMinutesSinceMidnight!),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppText.heroNumber.copyWith(fontSize: 24, color: AppColors.ink)),
          const SizedBox(height: 2),
          Text(label, style: AppText.meta.copyWith(color: AppColors.ink3)),
        ],
      ),
    );
  }
}

class _WeightCard extends StatelessWidget {
  const _WeightCard({required this.trend, required this.onLogWeight});

  final WeightTrend trend;
  final VoidCallback? onLogWeight;

  @override
  Widget build(BuildContext context) {
    final latest = trend.latest;
    final change = trend.changeKgOverWindow;
    return Container(
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
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                latest == null ? '—' : '${_trimNumber(latest.weightKg)} kg',
                style: AppText.heroNumber.copyWith(fontSize: 28, color: AppColors.ink),
              ),
              if (change != null) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '${change > 0 ? '+' : ''}${_trimNumber(change)}kg / 30d',
                    style: AppText.meta.copyWith(
                      color: change > 0 ? AppColors.flare : AppColors.pulse,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            latest == null ? 'No weigh-ins logged yet.' : 'Last logged ${timeAgo(latest.loggedAt, DateTime.now())} ago',
            style: AppText.meta.copyWith(color: AppColors.ink3),
          ),
          if (trend.series.length >= 2) ...[
            const SizedBox(height: 14),
            TrendChart(values: [for (final e in trend.series) e.weightKg], color: AppColors.solar),
          ],
          const SizedBox(height: 14),
          PillButton(
            label: 'Log weight',
            icon: Icons.add_rounded,
            color: AppColors.solar,
            enabled: onLogWeight != null,
            onTap: onLogWeight ?? () {},
          ),
        ],
      ),
    );
  }

  static String _trimNumber(double v) =>
      v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _SplitBreakdownCard extends StatelessWidget {
  const _SplitBreakdownCard({required this.plan, required this.stats});

  final WorkoutPlan plan;
  final TrainingDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final byDay = stats.sessionCountByDayLabel;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.name,
            style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.pulse.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '${entry.key} · ${entry.value}',
                      style: AppText.meta.copyWith(color: AppColors.pulse, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentSessionRow extends StatelessWidget {
  const _RecentSessionRow({required this.session, required this.now});

  final LiveSession session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (session.status) {
      SessionStatus.completed => ('Completed', AppColors.pulse),
      SessionStatus.active => ('In progress', AppColors.solar),
      SessionStatus.abandoned => ('Not completed', AppColors.ink3),
    };
    return Container(
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
                  style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(label, style: AppText.meta.copyWith(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
          ),
        ],
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

class _DashboardLoadingState extends StatelessWidget {
  const _DashboardLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 140,
        height: 140,
        decoration: const BoxDecoration(color: AppColors.surfaceRaised, shape: BoxShape.circle),
        padding: const EdgeInsets.all(10),
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(AppColors.ink2, BlendMode.srcIn),
          child: Lottie.asset('assets/loading.json', fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _DashboardErrorState extends StatelessWidget {
  const _DashboardErrorState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 30, color: AppColors.ink3),
            const SizedBox(height: 12),
            Text("Couldn't load this.", style: AppText.aside.copyWith(color: AppColors.ink2), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'Check your connection and try again in a moment.',
              style: AppText.meta.copyWith(color: AppColors.ink3),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPlanState extends StatelessWidget {
  const _NoPlanState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fitness_center_rounded, size: 30, color: AppColors.ink3),
            const SizedBox(height: 12),
            Text('No workout plan yet.', style: AppText.aside.copyWith(color: AppColors.ink2)),
            const SizedBox(height: 16),
            SizedBox(
              width: 200,
              child: PillButton(
                label: 'Create a plan',
                icon: Icons.add_rounded,
                color: AppColors.pulse,
                enabled: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WorkoutPlanEditPage(initialPlan: null)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "52m" under an hour, "1h 12m" past one.
String formatDurationShort(Duration d) {
  final totalMinutes = d.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

/// Minutes-since-midnight to a 12-hour clock label, e.g. 390 -> "6:30 AM".
String formatClockTime(double minutesSinceMidnight) {
  final total = minutesSinceMidnight.round() % (24 * 60);
  final h24 = total ~/ 60;
  final minute = total % 60;
  final period = h24 < 12 ? 'AM' : 'PM';
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h12:${minute.toString().padLeft(2, '0')} $period';
}
