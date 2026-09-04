import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../domain/analytics/plan_adherence.dart';
import '../../domain/analytics/workout_analytics.dart';
import '../../domain/live_session.dart';
import '../../domain/training_volume.dart';
import '../../domain/workout_plan.dart';
import '../widgets/progress_status_style.dart';
import '../widgets/staggered_reveal.dart';
import '../widgets/trend_chart.dart';
import 'exercise_analysis_page.dart';
import '../../../../l10n/l10n.dart';

/// The Analysis hub — a coaching dashboard, not one AI text block.
///
/// Driven entirely by the centralized [analyzeTraining] engine (plus
/// [analyzePlanAdherence] for what's being skipped) — the SAME numbers the AI
/// coach reasons over, so screen and coach can never disagree. It is organised
/// the way a coach reads a client's block (product brief §3): the verdict, then
/// what's going well, what's getting worse, what's stalled, what's being
/// skipped, and — reachable from every exercise row — the full per-exercise
/// drill-down. Everything reads from real completed sessions; a verdict is only
/// shown once there's enough history to mean it.
class WorkoutAnalysisPage extends StatelessWidget {
  const WorkoutAnalysisPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return TrainScreen(
      tint: TrainColors.hubTint,
      child: StreamBuilder<WorkoutPlan?>(
        stream: scope.workoutPlans.watchActivePlan(),
        initialData: scope.workoutPlans.activePlan,
        builder: (context, planSnap) {
          return StreamBuilder<List<LiveSession>>(
            stream: scope.workoutSessions.watchAll(),
            initialData: scope.workoutSessions.current,
            builder: (context, snap) {
              if (snap.hasError) return const _ErrorState();
              if (!snap.hasData &&
                  snap.connectionState == ConnectionState.waiting) {
                return const _LoadingState();
              }
              final sessions = snap.data ?? const <LiveSession>[];
              final now = DateTime.now();
              final analysis = analyzeTraining(sessions: sessions, now: now);
              final adherence = analyzePlanAdherence(
                plan: planSnap.data,
                sessions: sessions,
                now: now,
              );

              final declining = analysis.exercises
                  .where((e) => e.status == ProgressStatus.regressing)
                  .toList(growable: false);
              final stalled = analysis.exercises
                  .where((e) => e.status == ProgressStatus.plateauing)
                  .toList(growable: false);

              var step = 60;
              Duration delay() => Duration(milliseconds: (step += 20));

              return ListView(
                padding: EdgeInsets.fromLTRB(
                    22, 12, 22, TrainBottomInset.of(context)),
                children: [
                  RiseIn(child: TrainPageHeader(title: l(context).workoutAnalysis)),
                  const SizedBox(height: 20),
                  RiseIn(
                    delay: const Duration(milliseconds: 40),
                    child: _OverallCard(analysis: analysis),
                  ),
                  if (analysis.isEmpty) ...[
                    const SizedBox(height: 16),
                    const _EmptyHint(),
                  ] else ...[
                    if (analysis.recentPrs.isNotEmpty)
                      _Section(
                        label: l(context).workoutRecentPrs,
                        delay: delay(),
                        child: _RecentPrsCard(prs: analysis.recentPrs),
                      ),
                    if (analysis.improving.isNotEmpty)
                      _Section(
                        label: l(context).workoutGoingWell,
                        trailing: l(context).workoutImprovingCount(
                          analysis.improving.length,
                        ),
                        delay: delay(),
                        child: _ExerciseCard(exercises: analysis.improving),
                      ),
                    if (declining.isNotEmpty)
                      _Section(
                        label: l(context).workoutGettingWorse,
                        trailing: l(context).workoutDecliningCount(
                          declining.length,
                        ),
                        delay: delay(),
                        child: _ExerciseCard(exercises: declining),
                      ),
                    if (stalled.isNotEmpty)
                      _Section(
                        label: l(context).workoutStalled,
                        trailing: l(context).workoutFlatCount(stalled.length),
                        delay: delay(),
                        child: _ExerciseCard(exercises: stalled),
                      ),
                    if (adherence.neglected.isNotEmpty)
                      _Section(
                        label: l(context).workoutBeingSkipped,
                        trailing: l(context).workoutSkippedOfPlanned(
                          adherence.neglected.length,
                          adherence.plannedExerciseCount,
                        ),
                        delay: delay(),
                        child: _SkippedCard(neglected: adherence.neglected),
                      ),
                    if (analysis.nextStep != null)
                      _Section(
                        label: l(context).workoutFocusNext,
                        delay: delay(),
                        child: _NextStepCard(step: analysis.nextStep!),
                      ),
                    _Section(
                      label: l(context).workoutTrainingVolume,
                      delay: delay(),
                      child: _VolumeCard(volume: analysis.volume),
                    ),
                    if (analysis.exercises.isNotEmpty)
                      _Section(
                        label: l(context).workoutAllExercises,
                        trailing: l(context).workoutTapToDrillIn,
                        delay: delay(),
                        child: _ExerciseCard(exercises: analysis.exercises),
                      ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

String _signedPct(double v) => '${v > 0 ? '+' : ''}${v.round()}%';

String _trim(double v) =>
    v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// "100kg × 8" (or "8 reps" when unloaded) — a record set in one line.
String _setLine(BuildContext context, double? weightKg, int reps) =>
    weightKg == null
    ? l(context).workoutRepsOnly(reps)
    : l(context).workoutWeightByReps(_trim(weightKg), reps);

void _openExercise(BuildContext context, String id, String name) {
  HapticFeedback.selectionClick();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ExerciseAnalysisPage(exerciseId: id, exerciseName: name),
    ),
  );
}

// ---- Section chrome -------------------------------------------------------

/// A labelled, animated section — the one place the hub's rhythm (28px gap,
/// mono label, staggered rise) is defined, so every block reads the same.
class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.child,
    required this.delay,
    this.trailing,
  });

  final String label;
  final String? trailing;
  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        TrainSectionLabel(label.toUpperCase(), trailing: trailing?.toUpperCase()),
        const SizedBox(height: 10),
        RiseIn(delay: delay, child: child),
      ],
    );
  }
}

// ---- Overall --------------------------------------------------------------

/// The hero: the one-line verdict + short human explanation, over a soft aura
/// of the status's own color. Everything else supports this line.
class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.analysis});

  final TrainingAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final style = progressStatusStyle(context, analysis.overallStatus);
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
                l(context).workoutOverallCaps,
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
            StaggeredReveal(
              index: i,
              child: _PrRow(pr: pr),
            ),
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
      PrKind.heaviestWeight => l(context).workoutPrHeaviest,
      PrKind.mostReps => l(context).workoutPrMostReps,
      PrKind.bestEstimatedStrength => l(context).workoutPrBestStrength,
    };
    return InkWell(
      onTap: () => _openExercise(context, pr.exerciseId, pr.name),
      child: Padding(
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
                    '$kind · ${_setLine(context, pr.weightKg, pr.reps)}',
                    style: AppText.meta.copyWith(color: TrainColors.ink4),
                  ),
                ],
              ),
            ),
            const Icon(AppIcons.chevron, size: 16, color: TrainColors.ink4),
          ],
        ),
      ),
    );
  }
}

// ---- Exercise rows (shared across the coaching sections) ------------------

/// One card of hairline-separated, tappable exercise rows. Reused by every
/// exercise-list section (improving, declining, stalled, all) so they read
/// identically — the only difference between sections is which subset feeds it.
class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercises});

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
    final style = progressStatusStyle(context, ex.status);
    final change = ex.strengthChangePercent;
    final showChart = ex.e1rmSeries.length >= 2;
    return InkWell(
      onTap: () => _openExercise(context, ex.exerciseId, ex.name),
      child: Padding(
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
                            ? l(context).workoutStatusWithStrength(
                                style.label,
                                _signedPct(change),
                              )
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
                width: 56,
                child: TrendChart(
                  values: [for (final v in ex.e1rmSeries) v],
                  height: 30,
                  color: ex.status == ProgressStatus.regressing
                      ? TrainColors.ember
                      : TrainColors.green,
                ),
              ),
            ],
            const SizedBox(width: 8),
            const Icon(AppIcons.chevron, size: 16, color: TrainColors.ink4),
          ],
        ),
      ),
    );
  }
}

// ---- Skipped --------------------------------------------------------------

class _SkippedCard extends StatelessWidget {
  const _SkippedCard({required this.neglected});

  final List<NeglectedExercise> neglected;

  @override
  Widget build(BuildContext context) {
    final shown = neglected.take(6).toList();
    return _Card(
      child: Column(
        children: [
          for (final (i, n) in shown.indexed) ...[
            if (i > 0) const _RowDivider(),
            StaggeredReveal(index: i, child: _SkippedRow(item: n)),
          ],
        ],
      ),
    );
  }
}

class _SkippedRow extends StatelessWidget {
  const _SkippedRow({required this.item});

  final NeglectedExercise item;

  @override
  Widget build(BuildContext context) {
    final (line, color) = switch (item.reason) {
      AdherenceReason.neverTrained => (
        l(context).workoutNeverTrained,
        TrainColors.ember,
      ),
      // `daysSinceLast` is only null on the neverTrained branch, which the
      // case above already took — `analyzePlanAdherence` always sets it for a
      // stale entry. Fall back rather than force-unwrap: a wrong number is a
      // smaller failure than a crashed Analysis page.
      AdherenceReason.stale => (
        l(context).workoutStaleSince(item.daysSinceLast ?? 0, item.dayLabel),
        TrainColors.amber,
      ),
    };
    return InkWell(
      onTap: () => _openExercise(context, item.exerciseId, item.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(AppIcons.calendarClock, size: 16, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.rowTitle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: TrainColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(line, style: AppText.meta.copyWith(color: color)),
                ],
              ),
            ),
            const Icon(AppIcons.chevron, size: 16, color: TrainColors.ink4),
          ],
        ),
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
      null => (l(context).workoutNoPriorWeek, TrainColors.ink4),
      _ when change > 0 => (
        l(context).workoutVsLastWeek(_signedPct(change)),
        TrainColors.green,
      ),
      _ when change < 0 => (
        l(context).workoutVsLastWeek(_signedPct(change)),
        TrainColors.ember,
      ),
      _ => (l(context).workoutSameAsLastWeek, TrainColors.ink4),
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
                    l(context).workoutThisWeekWorkingSets,
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

// ---- Next step ------------------------------------------------------------

class _NextStepCard extends StatelessWidget {
  const _NextStepCard({required this.step});

  final NextStepRecommendation step;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openExercise(context, step.exerciseId, step.name),
          child: Container(
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
                const Icon(AppIcons.chevron, size: 16, color: TrainColors.green),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Shared chrome --------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
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
              l(context).workoutAnalysisEmptyTitle,
              style: AppText.rowTitle.copyWith(
                fontWeight: FontWeight.w600,
                color: TrainColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l(context).workoutAnalysisEmptyBody,
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
                l(context).errorCouldntLoad,
                style: AppText.aside.copyWith(color: TrainColors.ink2),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}
