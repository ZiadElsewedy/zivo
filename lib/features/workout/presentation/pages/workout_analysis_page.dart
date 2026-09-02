import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../domain/analytics/workout_analytics.dart';
import '../../domain/live_session.dart';
import '../../domain/training_volume.dart';
import '../widgets/staggered_reveal.dart';
import '../widgets/trend_chart.dart';

/// The progress/analysis surface, driven entirely by the centralized
/// [analyzeTraining] engine — the SAME numbers the AI coach reasons over, so
/// screen and coach can never disagree.
///
/// It answers five questions, top to bottom, and stops (per the product
/// brief — not a deep analytics dashboard):
///   1. Am I progressing?      → the overall summary
///   2. Any new PRs?           → Recent PRs
///   3. What am I improving at? / stuck on? → Exercise progress
///   4. Is my volume right?    → Training volume
///   5. What should I do next? → Needs attention + Next step
///
/// Everything reads from real completed sessions; nothing is a placeholder,
/// and a verdict is only shown once there's enough history to mean it.
class WorkoutAnalysisPage extends StatelessWidget {
  const WorkoutAnalysisPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return TrainScreen(
      tint: TrainColors.hubTint,
      child: StreamBuilder<List<LiveSession>>(
        stream: scope.workoutSessions.watchAll(),
        initialData: scope.workoutSessions.current,
        builder: (context, snap) {
          if (snap.hasError) return const _ErrorState();
          if (!snap.hasData &&
              snap.connectionState == ConnectionState.waiting) {
            return const _LoadingState();
          }
          final analysis = analyzeTraining(
            sessions: snap.data ?? const <LiveSession>[],
            now: DateTime.now(),
          );

          return ListView(
            padding: EdgeInsets.fromLTRB(22, 12, 22, TrainBottomInset.of(context)),
            children: [
              RiseIn(child: const TrainPageHeader(title: 'Analysis')),
              const SizedBox(height: 20),
              RiseIn(
                delay: const Duration(milliseconds: 40),
                child: _OverallCard(analysis: analysis),
              ),
              if (analysis.isEmpty) ...[
                const SizedBox(height: 16),
                const _EmptyHint(),
              ] else ...[
                if (analysis.recentPrs.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const _SectionLabel('Recent PRs'),
                  const SizedBox(height: 10),
                  RiseIn(
                    delay: const Duration(milliseconds: 80),
                    child: _RecentPrsCard(prs: analysis.recentPrs),
                  ),
                ],
                if (analysis.exercises.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const _SectionLabel('Exercise progress'),
                  const SizedBox(height: 10),
                  RiseIn(
                    delay: const Duration(milliseconds: 100),
                    child: _ExerciseListCard(exercises: analysis.exercises),
                  ),
                ],
                const SizedBox(height: 28),
                const _SectionLabel('Training volume'),
                const SizedBox(height: 10),
                RiseIn(
                  delay: const Duration(milliseconds: 120),
                  child: _VolumeCard(volume: analysis.volume),
                ),
                if (analysis.needsAttention.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const _SectionLabel('Needs attention'),
                  const SizedBox(height: 10),
                  RiseIn(
                    delay: const Duration(milliseconds: 140),
                    child: _AttentionCard(exercises: analysis.needsAttention),
                  ),
                ],
                if (analysis.nextStep != null) ...[
                  const SizedBox(height: 28),
                  const _SectionLabel('Next step'),
                  const SizedBox(height: 10),
                  RiseIn(
                    delay: const Duration(milliseconds: 160),
                    child: _NextStepCard(step: analysis.nextStep!),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

// ---- Status vocabulary ----------------------------------------------------

/// A status → (label, color, icon) — the one place the five directions get
/// their visual language, so every section reads them the same way.
({String label, Color color, IconData icon}) _statusStyle(ProgressStatus s) =>
    switch (s) {
      ProgressStatus.progressing =>
        (label: 'Progressing', color: TrainColors.green, icon: AppIcons.trendUp),
      ProgressStatus.maintaining =>
        (label: 'Maintaining', color: TrainColors.ink2, icon: AppIcons.minus),
      ProgressStatus.plateauing =>
        (label: 'Plateauing', color: TrainColors.amber, icon: AppIcons.minus),
      ProgressStatus.regressing =>
        (label: 'Trending down', color: TrainColors.ember, icon: AppIcons.trendDown),
      ProgressStatus.building =>
        (label: 'Building', color: TrainColors.ink4, icon: AppIcons.analysis),
    };

String _signedPct(double v) => '${v > 0 ? '+' : ''}${v.round()}%';

String _trim(double v) =>
    v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// "100kg × 8" (or "8 reps" when unloaded) — a record/anchor set in one line.
String _setLine(double? weightKg, int reps) =>
    weightKg == null ? '$reps reps' : '${_trim(weightKg)}kg × $reps';

// ---- Overall --------------------------------------------------------------

/// The hero: the one-line verdict + short human explanation, over a soft aura
/// of the status's own color. Everything else supports this line.
class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.analysis});

  final TrainingAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final style = _statusStyle(analysis.overallStatus);
    final color = analysis.isEmpty ? TrainColors.ink2 : style.color;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.10), color.withValues(alpha: 0.02)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.14)),
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
                    colors: [
                      color.withValues(alpha: 0.30),
                      color.withValues(alpha: 0.10),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(style.icon, size: 16, color: color),
              ),
              const SizedBox(width: 9),
              Text(
                'OVERALL',
                style: AppText.sectionLabel.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            analysis.summaryHeadline,
            style: AppText.cardTitle.copyWith(fontSize: 30, color: TrainColors.ink),
          ),
          const SizedBox(height: 10),
          Text(
            analysis.summaryDetail,
            style: AppText.aside.copyWith(fontSize: 16, color: TrainColors.ink2),
          ),
        ],
      ),
    );
  }
}

// ---- Recent PRs -----------------------------------------------------------

class _RecentPrsCard extends StatelessWidget {
  const _RecentPrsCard({required this.prs});

  final List<PrRecord> prs;

  @override
  Widget build(BuildContext context) {
    // Cap the strip so a big month doesn't become a wall — the most recent win.
    final shown = prs.take(6).toList();
    return _Card(
      child: Column(
        children: [
          for (final (i, pr) in shown.indexed) ...[
            if (i > 0) const _RowDivider(),
            StaggeredReveal(index: i, child: _PrRow(pr: pr)),
          ],
        ],
      ),
    );
  }
}

class _PrRow extends StatelessWidget {
  const _PrRow({required this.pr});

  final PrRecord pr;

  @override
  Widget build(BuildContext context) {
    final kind = switch (pr.kind) {
      PrKind.heaviestWeight => 'Heaviest',
      PrKind.mostReps => 'Most reps',
      PrKind.bestEstimatedStrength => 'Best strength',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(AppIcons.trophy, size: 18, color: TrainColors.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pr.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.rowTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: TrainColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$kind · ${_setLine(pr.weightKg, pr.reps)}',
                  style: AppText.meta.copyWith(color: TrainColors.ink4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Exercise progress ----------------------------------------------------

class _ExerciseListCard extends StatelessWidget {
  const _ExerciseListCard({required this.exercises});

  final List<ExercisePerformance> exercises;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          for (final (i, ex) in exercises.indexed) ...[
            if (i > 0) const _RowDivider(),
            StaggeredReveal(index: i, child: _ExerciseRow(ex: ex)),
          ],
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.ex});

  final ExercisePerformance ex;

  @override
  Widget build(BuildContext context) {
    final style = _statusStyle(ex.status);
    final change = ex.strengthChangePercent;
    final showChart = ex.e1rmSeries.length >= 2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ex.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.rowTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: TrainColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(style.icon, size: 13, color: style.color),
                    const SizedBox(width: 5),
                    Text(
                      // A concrete number when we have one, else the plain
                      // status word — never a fake percentage.
                      change != null
                          ? '${style.label} · ${_signedPct(change)} strength'
                          : style.label,
                      style: AppText.meta.copyWith(
                        color: style.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (showChart) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 60,
              child: TrendChart(
                values: [for (final v in ex.e1rmSeries) v],
                height: 30,
                color: ex.status == ProgressStatus.regressing
                    ? TrainColors.ember
                    : TrainColors.green,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- Volume ---------------------------------------------------------------

class _VolumeCard extends StatelessWidget {
  const _VolumeCard({required this.volume});

  final VolumeSummary volume;

  @override
  Widget build(BuildContext context) {
    final parts = formatVolume(volume.thisWeekKg);
    final change = volume.changePercent;
    final (deltaText, deltaColor) = switch (change) {
      null => ('No prior week to compare', TrainColors.ink4),
      _ when change > 0 => ('${_signedPct(change)} vs last week', TrainColors.green),
      _ when change < 0 => ('${_signedPct(change)} vs last week', TrainColors.ember),
      _ => ('Same as last week', TrainColors.ink4),
    };
    return _Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    TrainColors.green.withValues(alpha: 0.28),
                    TrainColors.green.withValues(alpha: 0.10),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(AppIcons.workout, size: 17, color: TrainColors.green),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Working sets only — warm-ups excluded.',
                    style: AppText.meta.copyWith(color: TrainColors.ink4, fontSize: 11.5),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    deltaText,
                    style: AppText.rowTitle.copyWith(
                      fontWeight: FontWeight.w700,
                      color: deltaColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: parts.value,
                    style: TrainType.mono(size: 22, color: TrainColors.ink),
                  ),
                  TextSpan(
                    text: ' ${parts.unit}',
                    style: TrainType.mono(size: 12, color: TrainColors.ink4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Needs attention ------------------------------------------------------

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.exercises});

  final List<ExercisePerformance> exercises;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          for (final (i, ex) in exercises.indexed) ...[
            if (i > 0) const _RowDivider(),
            _AttentionRow(ex: ex),
          ],
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.ex});

  final ExercisePerformance ex;

  @override
  Widget build(BuildContext context) {
    // Plain, non-clinical language — describe what happened, claim nothing
    // about the body (per the brief).
    final line = ex.status == ProgressStatus.regressing
        ? "${ex.name} has been trending down recently."
        : "${ex.name} hasn't moved much across your last few sessions.";
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ex.status == ProgressStatus.regressing
                ? AppIcons.trendDown
                : AppIcons.minus,
            size: 16,
            color: ex.status == ProgressStatus.regressing
                ? TrainColors.ember
                : TrainColors.amber,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              line,
              style: AppText.body.copyWith(
                fontSize: 13.5,
                height: 1.4,
                color: TrainColors.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Next step ------------------------------------------------------------

class _NextStepCard extends StatelessWidget {
  const _NextStepCard({required this.step});

  final NextStepRecommendation step;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            TrainColors.green.withValues(alpha: 0.12),
            TrainColors.green.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TrainColors.green.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(AppIcons.bolt, size: 18, color: TrainColors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              step.text,
              style: AppText.body.copyWith(
                fontSize: 15,
                height: 1.45,
                color: TrainColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Shared chrome --------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label.toUpperCase(),
        style: AppText.sectionLabel.copyWith(
          color: TrainColors.ink4,
          letterSpacing: 0.8,
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: TrainColors.hairline),
        ),
        child: child,
      );
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => const Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: TrainColors.hairline,
      );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: TrainColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(AppIcons.analysis, size: 22, color: TrainColors.green),
            const SizedBox(height: 12),
            Text(
              'Complete a few sessions to start tracking progress.',
              style: AppText.rowTitle.copyWith(
                fontWeight: FontWeight.w600,
                color: TrainColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Once you've logged the same exercise a few times, ZIVO will show "
              'your strength trend, PRs, and what to focus on next.',
              style: AppText.meta.copyWith(color: TrainColors.ink4, height: 1.4),
            ),
          ],
        ),
      );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: 120,
          height: 120,
          child: Lottie.asset('assets/loading.json', fit: BoxFit.contain),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 30, color: TrainColors.ink4),
              const SizedBox(height: 12),
              Text(
                "Couldn't load this.",
                style: AppText.aside.copyWith(color: TrainColors.ink2),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}
