import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/day_progress_analysis.dart';
import '../../domain/live_session.dart';
import '../../domain/progress_comparison.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../widgets/staggered_reveal.dart';
import '../widgets/trend_chart.dart';
import '../widgets/verdict_style.dart';

/// The progressive-overload Analysis page (WORKOUT_SYSTEM.md §3.3, Phase 2).
/// Pick a day in the active plan; see per-exercise last-vs-previous deltas +
/// verdict and a recent-sessions trend, plus a day-level overall verdict.
/// Built entirely on completed [LiveSession]s (never the flat Workout log).
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
              return Column(
                children: [
                  _DayPicker(
                    days: days,
                    selectedId: selected.id,
                    onSelect: (id) => setState(() => _selectedDayId = id),
                  ),
                  Expanded(
                    child: analysis.sessionCount == 0
                        ? _DayEmptyState(dayLabel: selected.label)
                        : _AnalysisBody(analysis: analysis),
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

/// A horizontal row of day pills — "Day A · Push" etc — the selected one
/// filled pulse, the rest a quiet outline.
class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.days, required this.selectedId, required this.onSelect});

  final List<WorkoutDay> days;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Horizontal padding only — a vertical component here shrinks the
        // cross-axis space every pill gets *before* its own padding applies,
        // which was squeezing the text box tight enough to clip the 'y'
        // descender in "Day".
        padding: const EdgeInsets.symmetric(horizontal: 22),
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final day = days[i];
          final active = day.id == selectedId;
          return Material(
            color: active ? AppColors.pulse : AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: InkWell(
              onTap: () => onSelect(day.id),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: active ? Colors.transparent : AppColors.hairline2),
                ),
                child: Text(
                  'Day ${day.slot} · ${day.label}',
                  style: AppText.meta.copyWith(
                    color: active ? Colors.white : AppColors.ink2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AnalysisBody extends StatelessWidget {
  const _AnalysisBody({required this.analysis});

  final DayProgressAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final exercises = analysis.exercises;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 40),
      children: [
        _DayVerdictHeader(analysis: analysis),
        const SizedBox(height: 18),
        for (final (i, exercise) in exercises.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: StaggeredReveal(index: i, child: _ExerciseAnalysisCard(exercise: exercise)),
          ),
      ],
    );
  }
}

/// The day-level summary: overall verdict badge (mirroring the live Goal
/// card's badge language) + improved/matched/regressed counts, or a calm
/// "log one more session" nudge when nothing's comparable yet.
class _DayVerdictHeader extends StatelessWidget {
  const _DayVerdictHeader({required this.analysis});

  final DayProgressAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final overall = analysis.overallVerdict;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: overall == null
          ? Text(
              'Log ${analysis.day.label} once more to start seeing progress.',
              style: AppText.body.copyWith(color: AppColors.ink2),
            )
          : Row(
              children: [
                _VerdictBadge(verdict: overall, label: switch (overall) {
                  ProgressVerdict.progressing => 'Progressing',
                  ProgressVerdict.matched => 'Holding steady',
                  ProgressVerdict.down => 'Slipping',
                }),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${analysis.improvedCount} improved · ${analysis.matchedCount} matched · '
                    '${analysis.regressedCount} regressed',
                    style: AppText.meta.copyWith(color: AppColors.ink3),
                  ),
                ),
              ],
            ),
    );
  }
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

/// One exercise's card: name + verdict (or a neutral "First time"/"Not
/// logged" tag), the reps/weight/volume deltas when there's something to
/// compare, and a trend chart across recent sessions.
class _ExerciseAnalysisCard extends StatelessWidget {
  const _ExerciseAnalysisCard({required this.exercise});

  final ExerciseProgress exercise;

  @override
  Widget build(BuildContext context) {
    final weights = [for (final p in exercise.trend) p.topWeightKg];
    final hasWeightTrend = weights.any((w) => w != null);
    final series = hasWeightTrend ? weights : [for (final p in exercise.trend) p.volume];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.name,
                  style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 10),
              if (exercise.verdict != null)
                _VerdictBadge(verdict: exercise.verdict!, label: verdictStyle(exercise.verdict!).$3)
              else
                _NeutralTag(label: exercise.appearances == 0 ? 'Not logged' : 'First time'),
            ],
          ),
          if (exercise.appearances >= 2) ...[
            const SizedBox(height: 10),
            _DeltaRow(exercise: exercise),
          ],
          const SizedBox(height: 12),
          if (exercise.appearances >= 2 && series.length >= 2) ...[
            TrendChart(
              values: series,
              // Green for Progressing/Matched (the chart's original look);
              // Down borrows the exact red verdictStyle uses for its badge,
              // so a regressing exercise reads as a red line at a glance,
              // not just a red badge above an otherwise-green chart.
              color: exercise.verdict == ProgressVerdict.down
                  ? verdictStyle(ProgressVerdict.down).$2
                  : AppColors.pulse,
            ),
            const SizedBox(height: 2),
            Text(
              hasWeightTrend ? 'Top set weight (kg)' : 'Volume (kg)',
              style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 11),
            ),
          ] else if (exercise.appearances == 1)
            Text(
              exercise.lastTopWeightKg == null
                  ? 'Logged once — no weight recorded.'
                  : 'Last: ${_trim(exercise.lastTopWeightKg!)}kg top set.',
              style: AppText.meta.copyWith(color: AppColors.ink3),
            )
          else
            Text('Not part of a session yet.', style: AppText.meta.copyWith(color: AppColors.ink3)),
        ],
      ),
    );
  }

  static String _trim(double v) => v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _DeltaRow extends StatelessWidget {
  const _DeltaRow({required this.exercise});

  final ExerciseProgress exercise;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (exercise.repsChangePercent != null) 'Reps ${_signedPercent(exercise.repsChangePercent!)}',
      if (exercise.weightChangeKg != null) 'Weight ${_signedKg(exercise.weightChangeKg!)}',
      if (exercise.volumeChangePercent != null) 'Volume ${_signedPercent(exercise.volumeChangePercent!)}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join('  ·  '), style: AppText.meta.copyWith(color: AppColors.ink2));
  }

  static String _signedPercent(double v) => '${v > 0 ? '+' : ''}${v.round()}%';
  static String _signedKg(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}kg';
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.show_chart_rounded, size: 30, color: AppColors.ink3),
            const SizedBox(height: 12),
            Text(
              "You haven't logged $dayLabel yet.",
              style: AppText.aside.copyWith(color: AppColors.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Complete a session to start tracking progress.',
              style: AppText.meta.copyWith(color: AppColors.ink3),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
