import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../domain/analytics/exercise_analysis.dart';
import '../../domain/analytics/workout_analytics.dart';
import '../../domain/live_session.dart';
import '../../domain/planned_exercise.dart';
import '../../domain/training_volume.dart';
import '../../domain/workout_plan.dart';
import '../widgets/progress_status_style.dart';
import '../widgets/staggered_reveal.dart';
import '../widgets/trend_chart.dart';
import '../../../../core/util/date_format.dart';
import '../../../../l10n/l10n.dart';

/// The exercise drill-down — everything a coach would open on ONE movement.
///
/// Driven entirely by the deterministic [analyzeExercise] engine, so every
/// number and every arrow traces back to a logged set. Read top to bottom it
/// answers, for this lift alone: where am I now (status + the plain-language
/// what-happened / why / do), how strong (e1RM trend + PRs), and — the part the
/// hub can't show — exactly what changed session to session, with the deltas
/// computed, not narrated (product brief §1–2).
class ExerciseAnalysisPage extends StatelessWidget {
  const ExerciseAnalysisPage({
    required this.exerciseId,
    required this.exerciseName,
    super.key,
  });

  final String exerciseId;

  /// Shown in the header while the stream warms up, before the analysis (which
  /// carries the freshest name) is available.
  final String exerciseName;

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
              final sessions = snap.data ?? const <LiveSession>[];
              final analysis = analyzeExercise(
                exerciseId: exerciseId,
                sessions: sessions,
                now: DateTime.now(),
                planned: _plannedFor(planSnap.data, exerciseId),
              );

              return ListView(
                padding: EdgeInsets.fromLTRB(
                  22,
                  12,
                  22,
                  TrainBottomInset.of(context),
                ),
                children: [
                  RiseIn(child: TrainPageHeader(title: analysis?.name ?? exerciseName)),
                  const SizedBox(height: 18),
                  if (analysis == null)
                    const _EmptyState()
                  else ...[
                    RiseIn(
                      delay: const Duration(milliseconds: 40),
                      child: _StatusHeader(analysis: analysis),
                    ),
                    const SizedBox(height: 14),
                    RiseIn(
                      delay: const Duration(milliseconds: 70),
                      child: _InsightCard(insight: analysis.insight),
                    ),
                    const SizedBox(height: 24),
                    _Label(
                      analysis.isWeighted
                          ? l(context).workoutStrengthTrend
                          : l(context).workoutVolumeTrend,
                    ),
                    const SizedBox(height: 10),
                    RiseIn(
                      delay: const Duration(milliseconds: 100),
                      child: _TrendCard(analysis: analysis),
                    ),
                    const SizedBox(height: 22),
                    _Label(l(context).workoutAtAGlance),
                    const SizedBox(height: 10),
                    RiseIn(
                      delay: const Duration(milliseconds: 120),
                      child: _MetricsGrid(analysis: analysis),
                    ),
                    if (analysis.records.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _Label(l(context).workoutPersonalRecords),
                      const SizedBox(height: 10),
                      RiseIn(
                        delay: const Duration(milliseconds: 140),
                        child: _RecordsCard(records: analysis.records),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _Label(
                      l(context).workoutSessionHistory,
                      trailing: l(context).workoutSessionsLogged(
                        analysis.totalSessions,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SessionTimeline(analysis: analysis),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  static PlannedExercise? _plannedFor(WorkoutPlan? plan, String exerciseId) {
    if (plan == null) return null;
    for (final day in plan.days) {
      for (final ex in day.exercises) {
        if (ex.id == exerciseId) return ex;
      }
    }
    return null;
  }
}

// ---- Status header --------------------------------------------------------

/// Name + muscle + the one-word direction, over a soft aura of its own colour.
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.analysis});

  final ExerciseAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final style = progressStatusStyle(context, analysis.status);
    final change = analysis.strengthChangePercent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            style.color.withValues(alpha: 0.10),
            style.color.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          TrainIconTile(icon: style.icon, accent: style.color, size: 42, iconSize: 20, radius: 13),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  style.label,
                  style: TrainType.ui(
                    size: 19,
                    weight: FontWeight.w800,
                    tracking: -0.02,
                    color: TrainColors.ink,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (analysis.muscleGroup != null) analysis.muscleGroup!,
                    if (change != null)
                      l(context).workoutEstStrengthChange(_signed(change)),
                  ].join(' · '),
                  style: TrainType.mono(size: 11, tracking: 0.02, color: style.color),
                ),
              ],
            ),
          ),
          if (analysis.currentE1RM != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _kg(analysis.currentE1RM!),
                  style: TrainType.mono(size: 24, tracking: -0.03, color: TrainColors.ink),
                ),
                Text(
                  l(context).workoutEst1rmCaps,
                  style: TrainType.caption(size: 8, tracking: 0.16, color: TrainColors.ink4),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---- Coaching insight (what happened / why / do) --------------------------

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});

  final CoachingInsight insight;

  @override
  Widget build(BuildContext context) {
    final color = progressStatusStyle(context, insight.tone).color;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InsightLine(
            marker: l(context).workoutWhatHappenedCaps,
            markerColor: TrainColors.ink4,
            text: insight.whatHappened,
          ),
          const SizedBox(height: 14),
          _InsightLine(
            marker: l(context).workoutWhyItMattersCaps,
            markerColor: TrainColors.ink4,
            text: insight.whyItMatters,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: color.withValues(alpha: 0.16)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.bolt, size: 16, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: _InsightLine(
                    marker: l(context).workoutDoThisCaps,
                    markerColor: color,
                    text: insight.whatToDo,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightLine extends StatelessWidget {
  const _InsightLine({
    required this.marker,
    required this.markerColor,
    required this.text,
  });

  final String marker;
  final Color markerColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          marker,
          style: TrainType.caption(size: 8.5, tracking: 0.18, color: markerColor),
        ),
        const SizedBox(height: 5),
        Text(
          text,
          style: TrainType.ui(
            size: 14,
            weight: FontWeight.w400,
            height: 1.45,
            color: TrainColors.ink,
          ),
        ),
      ],
    );
  }
}

// ---- Trend ----------------------------------------------------------------

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.analysis});

  final ExerciseAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    // e1RM for a loaded movement (the intensity story); volume otherwise.
    final series = analysis.isWeighted ? analysis.e1rmSeries : analysis.volumeSeries;
    final unit = analysis.isWeighted
        ? l(context).workoutEst1rmUnitCaps
        : l(context).workoutVolumeUnitCaps;
    final color = analysis.status == ProgressStatus.regressing
        ? TrainColors.ember
        : TrainColors.green;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            unit,
            style: TrainType.caption(size: 8.5, tracking: 0.16, color: TrainColors.ink4),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: TrendChart(values: series, color: color, height: 64),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l(context).workoutOldest,
                style: TrainType.caption(size: 8.5, tracking: 0.1, color: TrainColors.ink4),
              ),
              Text(
                l(context).workoutLatest,
                style: TrainType.caption(size: 8.5, tracking: 0.1, color: TrainColors.ink4),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- At-a-glance metrics --------------------------------------------------

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.analysis});

  final ExerciseAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final vol = formatVolume(analysis.totalVolumeKg);
    final freq = analysis.sessionsPerWeek;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                icon: AppIcons.trophy,
                accent: TrainColors.amber,
                value: analysis.bestE1RM == null ? '—' : _kg(analysis.bestE1RM!),
                unit: analysis.bestE1RM == null ? null : 'kg',
                label: l(context).workoutBestEst1rm,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Metric(
                icon: AppIcons.workout,
                accent: TrainColors.green,
                value: vol.value,
                unit: vol.unit,
                label: l(context).workoutTotalVolume,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Metric(
                icon: AppIcons.repeat,
                accent: TrainColors.violet,
                value: freq == null ? '—' : freq.toStringAsFixed(freq >= 10 ? 0 : 1),
                unit: freq == null ? null : l(context).workoutPerWeek,
                label: l(context).workoutFrequency,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Metric(
                icon: AppIcons.calendarClock,
                accent: analysis.daysSinceLast >= kQuietExerciseDays
                    ? TrainColors.amber
                    : TrainColors.ink2,
                value: analysis.daysSinceLast == 0
                    ? l(context).workoutToday
                    : '${analysis.daysSinceLast}',
                unit: analysis.daysSinceLast == 0
                    ? null
                    : l(context).workoutDaysAgo,
                label: l(context).workoutLastTrained,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.accent,
    required this.value,
    required this.unit,
    required this.label,
  });

  final IconData icon;
  final Color accent;
  final String value;
  final String? unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TrainStatTile(icon: icon, accent: accent, value: value, unit: unit, label: label);
  }
}

// ---- Personal records -----------------------------------------------------

class _RecordsCard extends StatelessWidget {
  const _RecordsCard({required this.records});

  final Map<PrKind, PrRecord> records;

  @override
  Widget build(BuildContext context) {
    final order = [PrKind.heaviestWeight, PrKind.bestEstimatedStrength, PrKind.mostReps];
    final rows = <Widget>[];
    for (final kind in order) {
      final r = records[kind];
      if (r == null) continue;
      rows.add(_PrRow(kind: kind, record: r));
    }
    return TrainListCard(rows: rows);
  }
}

class _PrRow extends StatelessWidget {
  const _PrRow({required this.kind, required this.record});

  final PrKind kind;
  final PrRecord record;

  @override
  Widget build(BuildContext context) {
    final (label, value) = switch (kind) {
      PrKind.heaviestWeight => (
        l(context).workoutPrHeaviestLoad,
        _setLine(record.weightKg, record.reps),
      ),
      PrKind.bestEstimatedStrength => (
        l(context).workoutBestEst1rm,
        record.estimatedOneRepMax == null
            ? '—'
            : l(context).workoutKgValue(_kg(record.estimatedOneRepMax!)),
      ),
      PrKind.mostReps => (
        l(context).workoutPrMostReps,
        _setLine(record.weightKg, record.reps),
      ),
    };
    return TrainListRow(
      icon: AppIcons.trophy,
      accent: TrainColors.amber,
      label: label,
      value: value,
    );
  }
}

// ---- Session timeline -----------------------------------------------------

/// The heart of the page: every session for this lift, newest first, each with
/// its sets, its reduced metrics, and — attached to the newer session — the
/// exact deltas versus the one before it.
class _SessionTimeline extends StatelessWidget {
  const _SessionTimeline({required this.analysis});

  final ExerciseAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    // comparisons[i] compares sessions[i] → sessions[i+1]; index by the newer
    // session's id so each card can find its own "vs last time".
    final byCurrent = <String, SessionComparison>{
      for (final c in analysis.comparisons) c.current.sessionId: c,
    };
    final newestFirst = analysis.sessions.reversed.toList(growable: false);
    return Column(
      children: [
        for (final (i, s) in newestFirst.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: StaggeredReveal(
              index: i,
              child: _SessionCard(
                record: s,
                comparison: byCurrent[s.sessionId],
                index: analysis.totalSessions - i,
              ),
            ),
          ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.record,
    required this.comparison,
    required this.index,
  });

  final ExerciseSessionRecord record;
  final SessionComparison? comparison;

  /// 1-based ordinal (oldest = 1) — "Session 3", as the brief labels them.
  final int index;

  @override
  Widget build(BuildContext context) {
    final vol = formatVolume(record.totalVolumeKg);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: ordinal + date, with a PR badge / tone chip on the right.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l(context).workoutSessionNumberCaps(index),
                            style: TrainType.caption(size: 8.5, tracking: 0.16, color: TrainColors.ink4),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            formatWeekdayDateTime(context, record.date),
                            style: TrainType.ui(
                              size: 14.5,
                              weight: FontWeight.w700,
                              color: TrainColors.inkPlain,
                              height: 1.05,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (record.isPrSession) const _PrBadge(),
                    if (comparison != null) ...[
                      if (record.isPrSession) const SizedBox(width: 6),
                      _ToneChip(tone: comparison!.tone),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // Set chips — the actual performance.
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final s in record.sets) _SetChip(set: s)],
                ),
                const SizedBox(height: 14),
                // Reduced metrics — equal columns split by hairlines, so the
                // row can't overflow on a narrow phone.
                TrainStatStrip(
                  valueSize: 15,
                  items: [
                    TrainStat(
                      '${record.workingSetCount}',
                      l(context).workoutSetsShort,
                    ),
                    TrainStat(
                      _setLine(record.topWeightKg, record.topReps),
                      l(context).workoutTopSet,
                    ),
                    TrainStat(
                      '${vol.value}${vol.unit == 'kg' ? '' : vol.unit}',
                      l(context).workoutVolumeShort,
                    ),
                    if (record.bestE1RM != null)
                      TrainStat(
                        _kg(record.bestE1RM!),
                        l(context).workoutEst1rmShort,
                      ),
                  ],
                ),
              ],
            ),
          ),
          // "Exactly what changed" — the deltas versus the previous session.
          if (comparison != null) _DeltaStrip(comparison: comparison!),
        ],
      ),
    );
  }
}

/// The row of measured deltas versus the previous session — the "↑ Load · ↓
/// Reps · ↑ Volume · ↑ Strength · New PB" line, each computed from records.
class _DeltaStrip extends StatelessWidget {
  const _DeltaStrip({required this.comparison});

  final SessionComparison comparison;

  @override
  Widget build(BuildContext context) {
    final chips = _deltaChips(context, comparison);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: TrainColors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l(context).workoutVsPreviousSessionCaps,
            style: TrainType.caption(size: 8, tracking: 0.16, color: TrainColors.ink4),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final c in chips) _DeltaChip(chip: c)],
          ),
        ],
      ),
    );
  }
}

// ---- Small building blocks ------------------------------------------------

class _SetChip extends StatelessWidget {
  const _SetChip({required this.set});

  final PerformedSet set;

  @override
  Widget build(BuildContext context) {
    final top = set.isTopSet;
    final color = top ? TrainColors.green : TrainColors.ink2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: top ? TrainColors.green.withValues(alpha: 0.10) : TrainColors.glass,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: top ? TrainColors.green.withValues(alpha: 0.22) : TrainColors.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            set.weightKg == null ? '${set.reps ?? '—'}' : '${_kg(set.weightKg!)}×${set.reps ?? '—'}',
            style: TrainType.mono(size: 12, tracking: -0.01, color: color),
          ),
          if (set.type.name != 'working') ...[
            const SizedBox(width: 4),
            Text(
              set.type.name == 'dropset'
                  ? l(context).workoutSetDropsetShort
                  : set.type.name == 'failure'
                  ? l(context).workoutSetFailureShort
                  : '',
              style: TrainType.caption(size: 8, tracking: 0.1, color: TrainColors.amber),
            ),
          ],
        ],
      ),
    );
  }
}

class _PrBadge extends StatelessWidget {
  const _PrBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: TrainColors.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.trophy, size: 11, color: TrainColors.amber),
          const SizedBox(width: 4),
          Text(
            l(context).workoutPbCaps,
            style: TrainType.mono(size: 9, weight: FontWeight.w600, tracking: 0.1, color: TrainColors.amber),
          ),
        ],
      ),
    );
  }
}

class _ToneChip extends StatelessWidget {
  const _ToneChip({required this.tone});

  final ExerciseTrendTone tone;

  @override
  Widget build(BuildContext context) {
    final style = trendToneStyle(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 11, color: style.color),
          const SizedBox(width: 4),
          Text(
            style.label,
            style: TrainType.mono(size: 9, weight: FontWeight.w600, tracking: 0.06, color: style.color),
          ),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  const _DeltaChip({required this.chip});

  final _Chip chip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: chip.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: chip.color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(chip.icon, size: 11, color: chip.color),
          const SizedBox(width: 5),
          Text(
            chip.text,
            style: TrainType.mono(size: 10.5, tracking: 0.01, color: chip.color),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) =>
      TrainSectionLabel(text, trailing: trailing?.toUpperCase());
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
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
            l(context).workoutExerciseEmptyTitle,
            style: TrainType.ui(size: 15, weight: FontWeight.w600, color: TrainColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            l(context).workoutExerciseEmptyBody,
            style: TrainType.ui(size: 12.5, weight: FontWeight.w400, height: 1.4, color: TrainColors.ink4),
          ),
        ],
      ),
    );
  }
}

// ---- Delta chip model -----------------------------------------------------

class _Chip {
  const _Chip(this.text, this.color, this.icon);
  final String text;
  final Color color;
  final IconData icon;
}

/// Turns a [SessionComparison] into the ordered display chips. Colour encodes
/// meaning conservatively: green for a genuine gain, ember for a genuine loss,
/// neutral ink where a direction isn't itself good or bad (fewer reps at a
/// heavier load is a trade, not a regression). Amber marks a PB.
List<_Chip> _deltaChips(BuildContext context, SessionComparison c) {
  final strings = l(context);
  final e1rm = strings.workoutDeltaE1rm(_signed(c.e1rmChangePercent));
  final load = strings.workoutDeltaLoad(_signedKg(c.loadChangeKg));
  final reps = strings.workoutDeltaReps(_signedInt(c.topRepsChange));
  final volume = strings.workoutDeltaVolume(_signed(c.volumeChangePercent));
  final out = <_Chip>[];
  for (final tag in c.tags) {
    switch (tag) {
      case SessionChange.newPr:
        out.add(_Chip(strings.workoutNewPb, TrainColors.amber, AppIcons.trophy));
      case SessionChange.strengthUp:
        out.add(_Chip(e1rm, TrainColors.green, AppIcons.trendUp));
      case SessionChange.strengthDown:
        out.add(_Chip(e1rm, TrainColors.ember, AppIcons.trendDown));
      case SessionChange.loadUp:
        out.add(_Chip(load, TrainColors.green, AppIcons.trendUp));
      case SessionChange.loadDown:
        out.add(_Chip(load, TrainColors.ink2, AppIcons.trendDown));
      case SessionChange.repsUp:
        out.add(_Chip(reps, TrainColors.green, AppIcons.trendUp));
      case SessionChange.repsDown:
        out.add(_Chip(reps, TrainColors.ink2, AppIcons.trendDown));
      case SessionChange.volumeUp:
        out.add(_Chip(volume, TrainColors.green, AppIcons.trendUp));
      case SessionChange.volumeDown:
        out.add(_Chip(volume, TrainColors.ink2, AppIcons.trendDown));
      case SessionChange.noChange:
        out.add(_Chip(
          strings.workoutNoMeaningfulChange,
          TrainColors.ink4,
          AppIcons.minus,
        ));
    }
  }
  return out;
}

// ---- Formatting -----------------------------------------------------------

String _kg(double v) =>
    v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _setLine(double? weightKg, int reps) =>
    weightKg == null ? '$reps' : '${_kg(weightKg)}×$reps';

String _signed(double? pct) =>
    pct == null ? '—' : '${pct > 0 ? '+' : ''}${pct.round()}%';

String _signedInt(int v) => '${v > 0 ? '+' : ''}$v';

String _signedKg(double? v) =>
    v == null ? '—' : '${v > 0 ? '+' : ''}${_kg(v)}kg';

