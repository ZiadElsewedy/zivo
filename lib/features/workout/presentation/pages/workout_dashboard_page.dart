import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
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
import '../widgets/workout_section_label.dart';
import 'workout_pdf_import_page.dart';
import 'workout_plan_edit_page.dart';
import 'workout_progress_page.dart';

/// The Workout tab's landing page — a real training dashboard, not just a
/// session log. Reads [LiveSession]s directly (the record of what actually
/// happened, when, and for how long — never the lossy flat `Workout` log
/// `WorkoutHistoryPage` shows) to answer: did I train today, what/how
/// consistently am I training, how long do sessions run, and how's my
/// bodyweight moving. Deliberately only three blocks: the training card, this
/// week, and bodyweight. The split breakdown, progress verdict and recent
/// activity — plus the Analysis/History/Splits destinations — live one tap
/// away on [WorkoutProgressPage] via the AppBar's Progress action, so this
/// landing stays calm instead of stacking six similar-looking cards.
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
            tooltip: 'Progress',
            icon: const Icon(Icons.insights_rounded, color: AppColors.ink2),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WorkoutProgressPage()),
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
                  // Deliberately just three blocks — the training card, this
                  // week, and bodyweight. Split/progress/recent-activity depth
                  // lives on `WorkoutProgressPage` (the AppBar's Progress
                  // action) so this landing stays calm and scannable.
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 110),
                    children: [
                      if (selection.day != null)
                        UpNextWorkoutCard(plan: plan, day: selection.day!, resumable: selection.resumable),
                      const SizedBox(height: 30),
                      const WorkoutSectionLabel('This week'),
                      const SizedBox(height: 10),
                      _StatsGrid(stats: stats),
                      const SizedBox(height: 30),
                      const WorkoutSectionLabel('Bodyweight'),
                      const SizedBox(height: 10),
                      _WeightCard(
                        trend: weightTrend,
                        onLogWeight: bodyWeight == null
                            ? null
                            : () => _showLogWeightSheet(context, bodyWeight),
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
                label: 'Day streak',
                value: '${stats.currentStreakDays}',
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
            const _PhaseIconLike(icon: Icons.fitness_center_rounded, color: AppColors.pulse),
            const SizedBox(height: 18),
            Text(
              'No workout plan yet',
              style: AppText.cardTitle.copyWith(color: AppColors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              "Import a PDF and I'll turn it into a real split, or build one from scratch.",
              style: AppText.body.copyWith(color: AppColors.ink3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 220,
              child: PillButton(
                label: 'Import from PDF',
                icon: Icons.upload_file_rounded,
                color: AppColors.pulse,
                enabled: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WorkoutPdfImportPage()),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WorkoutPlanEditPage(initialPlan: null)),
              ),
              child: Text('Build manually instead', style: AppText.meta.copyWith(color: AppColors.ink2)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The same tinted icon-chip language `workout_pdf_import_page.dart` uses for
/// its own phase states — reused here so the empty state that leads INTO
/// that flow already looks like part of the same product.
class _PhaseIconLike extends StatelessWidget {
  const _PhaseIconLike({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Icon(icon, size: 28, color: color),
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
