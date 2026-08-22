import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/body_weight_entry.dart';
import '../../domain/day_progress_analysis.dart';
import '../../domain/live_session.dart';
import '../../domain/progress_comparison.dart';
import '../../domain/training_dashboard_stats.dart';
import '../../domain/weight_trend.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../widgets/staggered_reveal.dart';
import '../widgets/trend_chart.dart';
import '../widgets/verdict_style.dart';

/// The progressive-overload Analysis page (WORKOUT_SYSTEM.md §3.3, Phase 2).
///
/// Reads as one continuous "how am I progressing" picture rather than a pile
/// of same-weight boxes: wrapping day chips pick the day, a hero headline
/// states that day's verdict in plain language, a [_BasisNote] spells out what
/// the comparison actually is (this day's last session vs the one before —
/// owner-reported confusion, so it's stated outright, not implied), then a
/// slim consistency strip and bodyweight snapshot give the day-INdependent
/// picture, and every exercise for the day lives as a row in a single
/// sectioned list. Nothing scrolls horizontally. Everything reads from real
/// data — [analyzeDayProgress], [computeTrainingDashboardStats], and
/// [computeWeightTrend] — nothing is a placeholder.
///
/// Dark, immersive body — matching the plan/live-session pages on the
/// app-wide [AppColors] theme.
class WorkoutAnalysisPage extends StatefulWidget {
  const WorkoutAnalysisPage({super.key});

  @override
  State<WorkoutAnalysisPage> createState() => _WorkoutAnalysisPageState();
}

class _WorkoutAnalysisPageState extends State<WorkoutAnalysisPage> {
  String? _selectedDayId;

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
        title: Text('Analysis', style: AppText.cardTitle.copyWith(color: AppColors.ink)),
      ),
      body: StreamBuilder<WorkoutPlan?>(
        stream: scope.workoutPlans.watchActivePlan(),
        initialData: scope.workoutPlans.activePlan,
        builder: (context, planSnap) {
          if (planSnap.hasError) return const _AnalysisErrorState();
          final plan = planSnap.data;
          final loading = plan == null && planSnap.connectionState == ConnectionState.waiting;
          if (loading) return const _AnalysisLoadingState();
          if (plan == null || plan.days.isEmpty) return const _NoPlanState();

          final days = [...plan.days]..sort((a, b) => a.order.compareTo(b.order));
          final selected = days.firstWhere(
            (d) => d.id == _selectedDayId,
            orElse: () => plan.nextDay ?? days.first,
          );

          return StreamBuilder<List<LiveSession>>(
            stream: scope.workoutSessions.watchAll(),
            initialData: scope.workoutSessions.current,
            builder: (context, sessionsSnap) {
              if (sessionsSnap.hasError) return const _AnalysisErrorState();
              final sessions = sessionsSnap.data ?? const <LiveSession>[];
              final analysis = analyzeDayProgress(day: selected, planId: plan.id, allSessions: sessions);
              final now = DateTime.now();
              final stats = computeTrainingDashboardStats(sessions: sessions, now: now);

              final bodyWeight = scope.bodyWeight;
              return StreamBuilder<List<BodyWeightEntry>>(
                stream: bodyWeight?.watchAll() ?? const Stream.empty(),
                initialData: bodyWeight?.current ?? const <BodyWeightEntry>[],
                builder: (context, weightSnap) {
                  final weightTrend = computeWeightTrend(
                    entries: weightSnap.data ?? const <BodyWeightEntry>[],
                    now: now,
                  );
                  // One single scroll, no horizontal scrolling anywhere: the
                  // day chips wrap onto as many lines as they need.
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 48),
                    children: [
                      _DayChips(
                        days: days,
                        selectedId: selected.id,
                        onSelect: (id) => setState(() => _selectedDayId = id),
                      ),
                      const SizedBox(height: 30),
                      _ProgressHero(analysis: analysis),
                      const SizedBox(height: 20),
                      _BasisNote(dayLabel: selected.label),
                      const SizedBox(height: 36),
                      _SectionLabel('Consistency'),
                      const SizedBox(height: 5),
                      // Called out because, unlike everything above, these
                      // three are day-independent — they span every session.
                      Text(
                        'Across all your training, not just ${selected.label}.',
                        style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      _ConsistencyRow(stats: stats),
                      if (weightTrend.latest != null) ...[
                        const SizedBox(height: 14),
                        _WeightSnapshotRow(trend: weightTrend),
                      ],
                      const SizedBox(height: 40),
                      _SectionLabel('${selected.label} exercises'),
                      const SizedBox(height: 12),
                      if (analysis.sessionCount == 0)
                        _DayEmptyState(dayLabel: selected.label)
                      else
                        _ExerciseListCard(exercises: analysis.exercises),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label.toUpperCase(), style: AppText.sectionLabel.copyWith(color: AppColors.ink3, letterSpacing: 0.8));
}

/// The day selector as a [Wrap] of chips — deliberately NOT a horizontal
/// scroller (owner-reported: the sideways scroll was disliked, and it hid days
/// off-screen edge). Wrapping shows every day at once and stays clean from 3
/// to 6+ days, at the cost of a second line on long labels — the right trade
/// when the whole page is about the day you pick. Labels are just the slot +
/// label with no "Day " prefix, so the chips stay narrow.
class _DayChips extends StatelessWidget {
  const _DayChips({required this.days, required this.selectedId, required this.onSelect});

  final List<WorkoutDay> days;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final day in days)
          _DayChip(
            label: '${day.slot} · ${day.label}',
            active: day.id == selectedId,
            onTap: () => onSelect(day.id),
          ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.pulse : AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: active ? Colors.transparent : AppColors.hairline2),
          ),
          child: Text(
            label,
            style: AppText.meta.copyWith(
              color: active ? Colors.white : AppColors.ink2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// States, in plain words, exactly what the numbers above compare — the
/// owner couldn't tell whether this page was per-day or per-week, so it says
/// so outright instead of leaving it to a small grey footnote. The basis is
/// real: [analyzeDayProgress] compares an exercise's two most recent
/// COMPLETED appearances on this day, index-aligning sets.
class _BasisNote extends StatelessWidget {
  const _BasisNote({required this.dayLabel});

  final String dayLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 17, color: AppColors.ink3),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppText.body.copyWith(color: AppColors.ink2, fontSize: 13.5, height: 1.45),
                children: [
                  const TextSpan(text: 'Your '),
                  TextSpan(
                    text: 'last $dayLabel',
                    style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(text: ' vs the '),
                  TextSpan(
                    text: 'one before it',
                    style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(
                    text: ' — exercise by exercise, comparing reps, top-set weight, '
                        'and volume (reps × weight). Not weekly, and not all workouts mixed together.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The visual anchor of the page — states the selected day's verdict in
/// plain language first (a big display headline, matching the Today page's
/// greeting/aside hierarchy), backed by the exact improved/matched/regressed
/// counts underneath. Everything else on the page supports this one line.
class _ProgressHero extends StatelessWidget {
  const _ProgressHero({required this.analysis});

  final DayProgressAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final overall = analysis.overallVerdict;
    final (headline, color) = switch (overall) {
      null => (analysis.sessionCount == 0 ? "Let's get started" : 'Almost there', AppColors.ink2),
      ProgressVerdict.progressing => ('Progressing', AppColors.pulse),
      ProgressVerdict.matched => ('Holding steady', AppColors.ink2),
      ProgressVerdict.down => ('Slipping', AppColors.flare),
    };
    final detail = overall == null
        ? (analysis.sessionCount == 0
              ? 'Log ${analysis.day.label} to start tracking progress.'
              : "Log ${analysis.day.label} once more to see how you're trending.")
        : '${analysis.improvedCount} improved · ${analysis.matchedCount} matched · '
              '${analysis.regressedCount} regressed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(analysis.day.label.toUpperCase(), style: AppText.sectionLabel.copyWith(color: color)),
        const SizedBox(height: 6),
        Text(headline, style: AppText.cardTitle.copyWith(fontSize: 32, color: AppColors.ink)),
        const SizedBox(height: 10),
        Text(detail, style: AppText.aside.copyWith(fontSize: 17, color: AppColors.ink2)),
      ],
    );
  }
}

/// The day-independent training picture — sessions this week, the current
/// day streak, and average session length — as one slim divided row rather
/// than three separate boxed tiles.
class _ConsistencyRow extends StatelessWidget {
  const _ConsistencyRow({required this.stats});

  final TrainingDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Row(
        children: [
          Expanded(child: _ConsistencyStat(value: '${stats.sessionsThisWeek}', label: 'This week')),
          _ConsistencyDivider(),
          Expanded(child: _ConsistencyStat(value: '${stats.currentStreakDays}', label: 'Day streak')),
          _ConsistencyDivider(),
          Expanded(
            child: _ConsistencyStat(
              value: stats.averageSessionDuration == null
                  ? '—'
                  : _formatDurationShort(stats.averageSessionDuration!),
              label: 'Avg length',
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsistencyDivider extends StatelessWidget {
  const _ConsistencyDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, margin: const EdgeInsets.symmetric(horizontal: 12), color: AppColors.hairline2);
}

class _ConsistencyStat extends StatelessWidget {
  const _ConsistencyStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.ink)),
        const SizedBox(height: 2),
        Text(label, style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 11)),
      ],
    );
  }
}

/// A compact bodyweight snapshot — latest reading, its 30-day delta, and a
/// small sparkline — folded in here so "how am I progressing" covers the
/// body, not just the lifts. Omitted entirely when nothing's been logged.
class _WeightSnapshotRow extends StatelessWidget {
  const _WeightSnapshotRow({required this.trend});

  final WeightTrend trend;

  @override
  Widget build(BuildContext context) {
    final latest = trend.latest!;
    final change = trend.changeKgOverWindow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_trim(latest.weightKg)} kg',
                style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              const SizedBox(height: 2),
              Text(
                change == null ? 'Bodyweight' : '${change > 0 ? '+' : ''}${_trim(change)}kg over 30d',
                style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          if (trend.series.length >= 2)
            SizedBox(
              width: 96,
              child: TrendChart(
                values: [for (final e in trend.series) e.weightKg],
                color: AppColors.solar,
                height: 36,
              ),
            ),
        ],
      ),
    );
  }
}

/// Every exercise for the selected day as one sectioned list — hairline
/// dividers between rows instead of a repeated bordered card per exercise —
/// so a five-exercise day reads as one coherent list, not five identical
/// boxes stacked on top of each other.
class _ExerciseListCard extends StatelessWidget {
  const _ExerciseListCard({required this.exercises});

  final List<ExerciseProgress> exercises;

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
          for (final (i, exercise) in exercises.indexed) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: AppColors.hairline2),
            StaggeredReveal(index: i, child: _ExerciseRow(exercise: exercise)),
          ],
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise});

  final ExerciseProgress exercise;

  @override
  Widget build(BuildContext context) {
    final weights = [for (final p in exercise.trend) p.topWeightKg];
    final hasWeightTrend = weights.any((w) => w != null);
    final series = hasWeightTrend ? weights : [for (final p in exercise.trend) p.volume];
    final showChart = exercise.appearances >= 2 && series.length >= 2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        exercise.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (exercise.verdict != null)
                      _VerdictBadge(verdict: exercise.verdict!, label: verdictStyle(exercise.verdict!).$3)
                    else
                      _NeutralTag(label: exercise.appearances == 0 ? 'Not logged' : 'First time'),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  _subtitle(exercise),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.meta.copyWith(color: AppColors.ink3),
                ),
              ],
            ),
          ),
          if (showChart) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 64,
              child: TrendChart(
                values: series,
                height: 32,
                // Green for Progressing/Matched (the chart's original look);
                // Down borrows the exact red verdictStyle uses for its
                // badge, so a regressing exercise reads as a red line at a
                // glance, not just a red badge.
                color: exercise.verdict == ProgressVerdict.down
                    ? verdictStyle(ProgressVerdict.down).$2
                    : AppColors.pulse,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _subtitle(ExerciseProgress exercise) {
    if (exercise.appearances >= 2) {
      final parts = <String>[
        if (exercise.repsChangePercent != null) 'Reps ${_signedPercent(exercise.repsChangePercent!)}',
        if (exercise.weightChangeKg != null) 'Weight ${_signedKg(exercise.weightChangeKg!)}',
        if (exercise.volumeChangePercent != null) 'Volume ${_signedPercent(exercise.volumeChangePercent!)}',
      ];
      if (parts.isNotEmpty) return parts.join('  ·  ');
    }
    if (exercise.appearances == 1) {
      return exercise.lastTopWeightKg == null
          ? 'Logged once — no weight recorded.'
          : 'Last: ${_trim(exercise.lastTopWeightKg!)}kg top set.';
    }
    return 'Not part of a session yet.';
  }

  static String _signedPercent(double v) => '${v > 0 ? '+' : ''}${v.round()}%';
  static String _signedKg(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}kg';
}

/// A pill badge for a [ProgressVerdict] — same visual language (icon,
/// pulse/ink3/flare coloring, translucent fill) as the live session's
/// per-set progress badge, so the analysis page's verdicts read as the same
/// system the user already sees mid-workout.
class _VerdictBadge extends StatelessWidget {
  const _VerdictBadge({required this.verdict, required this.label});

  final ProgressVerdict verdict;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (icon, color, _) = verdictStyle(verdict);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label, style: AppText.meta.copyWith(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _NeutralTag extends StatelessWidget {
  const _NeutralTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.ink3.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label, style: AppText.meta.copyWith(color: AppColors.ink3, fontWeight: FontWeight.w700)),
    );
  }
}

class _AnalysisLoadingState extends StatelessWidget {
  const _AnalysisLoadingState();

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

class _AnalysisErrorState extends StatelessWidget {
  const _AnalysisErrorState();

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
        child: Text(
          'Create a workout plan to see progress analysis.',
          style: AppText.aside.copyWith(color: AppColors.ink2),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// No completed sessions for this day yet — nothing to analyze.
class _DayEmptyState extends StatelessWidget {
  const _DayEmptyState({required this.dayLabel});

  final String dayLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.show_chart_rounded, size: 26, color: AppColors.ink3),
          const SizedBox(height: 12),
          Text(
            "You haven't logged $dayLabel yet.",
            style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            'Complete a session to start tracking progress.',
            style: AppText.meta.copyWith(color: AppColors.ink3),
          ),
        ],
      ),
    );
  }
}

String _trim(double v) => v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _formatDurationShort(Duration d) {
  final totalMinutes = d.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}
