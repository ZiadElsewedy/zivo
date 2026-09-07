import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/date_format.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/sleep_insight.dart';
import '../../domain/sleep_metrics.dart';
import '../../domain/sleep_night.dart';
import '../../domain/sleep_service.dart';
import '../controllers/sleep_controller.dart';
import '../sleep_insight_labels.dart';
import '../sleep_labels.dart';
import '../widgets/sleep_axis.dart';
import '../widgets/sleep_bar.dart';
import '../widgets/sleep_duration_text.dart';
import '../widgets/sleep_edit_night_sheet.dart';
import '../widgets/sleep_source_chip.dart';
import '../widgets/sleep_targets_sheet.dart';
import '../widgets/sleep_week_raster.dart';
import '../widgets/sleep_why_sheet.dart';

/// The Sleep screen: last night, the week, and what it means — in that order,
/// on one scroll.
///
/// Deliberately one page rather than a daily screen with a weekly drill-down.
/// The whole feature is three sections and the sections answer each other:
/// "6h 52m" means little until the raster shows it is the shortest of six
/// nights, and the raster means little until the source chip says how much of
/// it was measured. Splitting them across a navigation layer would put a tap
/// between a number and its context.
///
/// The screen's job is to make every claim on it defensible
/// (`docs/SLEEP_SYSTEM.md` §13):
///
/// * the hero figure is never shown without its source chip;
/// * a night with no data renders in words, never as `0h 0m`;
/// * on iOS an empty read cannot be narrated as "no sleep data", because
///   Apple does not disclose read denial and we would be asserting something
///   we cannot know;
/// * every gated figure shows its `n`, or says it is not there yet.
class SleepPage extends StatefulWidget {
  const SleepPage({super.key});

  @override
  State<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends State<SleepPage> {
  SleepController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final scope = AppScope.of(context);
    final service = scope.requireSleepService;
    _controller = SleepController(
      repository: scope.requireSleep,
      service: service,
    );
    // Fire and forget: a sync failure becomes a state on screen, never an
    // exception and never a spinner that outlives it.
    service.sync();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();

    return TrainScreen(
      tint: TrainColors.sleepTint,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => RefreshIndicator(
          color: TrainColors.violetGlyph,
          backgroundColor: TrainColors.raised,
          onRefresh: () => controller.refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              0,
              AppSpacing.screen,
              120,
            ),
            children: [
              TrainPageHeader(
                title: l(context).sleepTitle,
                action: TrainHeaderAction(
                  icon: Icons.tune,
                  semanticLabel: l(context).sleepTargetsTitle,
                  onTap: () => _editTargets(controller),
                ),
              ),
              RiseIn(child: _LastNight(controller: controller)),
              const SizedBox(height: AppSpacing.section),
              RiseIn(delay: const Duration(milliseconds: 60),
                  child: _Week(controller: controller)),
              const SizedBox(height: AppSpacing.section),
              RiseIn(delay: const Duration(milliseconds: 120),
                  child: _Insights(controller: controller)),
              const SizedBox(height: AppSpacing.section),
              RiseIn(delay: const Duration(milliseconds: 180),
                  child: _Log(controller: controller)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editTargets(SleepController controller) async {
    final targets = await showSleepTargetsSheet(
      context,
      initial: controller.targets,
    );
    if (targets == null) return;
    await controller.saveTargets(targets);
  }
}

// ---------------------------------------------------------------------------
// Last night
// ---------------------------------------------------------------------------

class _LastNight extends StatelessWidget {
  const _LastNight({required this.controller});

  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasLoaded) {
      // "Still loading" and "loaded and empty" must not share a rendering:
      // one is a promise, the other is a fact.
      return const SizedBox(height: 120);
    }

    final night = controller.lastNight;
    if (night == null) return _EmptyState(controller: controller);

    final session = night.main!;
    final strings = l(context);

    return GestureDetector(
      onTap: () => showSleepWhySheet(context, night),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TrainSectionLabel(strings.sleepLastNight),
          const SizedBox(height: AppSpacing.s),

          // The figure, and — always, never optionally — where it came from.
          SleepDurationText(
            duration: session.asleepDuration,
            size: 58,
          ),
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              SleepSourceChip(provenance: session.provenance),
              const SizedBox(width: AppSpacing.s),
              SleepConfidenceBadge(confidence: session.provenance.confidence),
            ],
          ),

          const SizedBox(height: AppSpacing.l),
          const SleepAxisLabels(),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 26,
            child: Stack(
              children: [
                Positioned.fill(
                  child: SleepAxisGrid(
                    targetBedtimeMinutes: night.targets?.bedtimeMinutes,
                    targetWakeMinutes: night.targets?.wakeMinutes,
                  ),
                ),
                Positioned.fill(
                  child: Center(child: SleepBar(night: night, height: 18)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),

          // The two clock times, each phrased for how it is known. This is the
          // copy contract at its most visible: "Asleep 1:47 AM" and "You
          // logged 1:30 AM" are the same row with different verbs.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                sleepOnsetText(context, session),
                style: AppText.meta.copyWith(color: TrainColors.ink2),
              ),
              Text(
                sleepWakeText(context, session),
                style: AppText.meta.copyWith(color: TrainColors.ink2),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.base),
          _TargetLines(night: night),

          if (night.naps.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              strings.sleepNapCount(night.naps.length),
              style: AppText.meta.copyWith(color: TrainColors.ink3),
            ),
          ],

          const SizedBox(height: AppSpacing.m),
          Row(
            children: [
              _TextAction(
                label: strings.sleepWhyTitle,
                onTap: () => showSleepWhySheet(context, night),
              ),
              const SizedBox(width: AppSpacing.base),
              _TextAction(
                label: strings.sleepEditNight,
                onTap: () => _edit(context, night),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, SleepNight night) async {
    final edit = await showSleepEditNightSheet(context, night);
    if (edit == null || !context.mounted) return;
    await controller.editNight(
      sleepDay: night.sleepDay,
      startAtUtc: edit.startAtUtc,
      endAtUtc: edit.endAtUtc,
      providerName: l(context).sleepProviderYou,
    );
  }
}

/// Actual against target, as a signed sentence — never a score and never a
/// tick. ZIVO knows how long you slept; it does not know whether the night
/// was good.
class _TargetLines extends StatelessWidget {
  const _TargetLines({required this.night});

  final SleepNight night;

  @override
  Widget build(BuildContext context) {
    final duration = sleepDurationDeltaText(context, night);
    final bedtime = sleepBedtimeDeltaText(context, night);
    if (duration == null && bedtime == null) {
      return Text(
        l(context).sleepNoTargets,
        style: AppText.meta.copyWith(color: TrainColors.ink3),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (duration != null)
          Text(duration, style: AppText.body.copyWith(color: TrainColors.ink2)),
        if (bedtime != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(bedtime, style: AppText.meta.copyWith(color: TrainColors.ink3)),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The week
// ---------------------------------------------------------------------------

class _Week extends StatelessWidget {
  const _Week({required this.controller});

  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final metrics = controller.weekMetrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainSectionLabel(strings.sleepWeekTitle),
        const SizedBox(height: AppSpacing.m),
        SleepWeekRaster(
          nights: controller.week,
          targets: controller.targets,
          onTapNight: (night) => showSleepWhySheet(context, night),
        ),
        const SizedBox(height: AppSpacing.l),

        // Three figures, each carrying its own n. A number without its
        // denominator is a claim without its evidence.
        _Figure(
          label: strings.sleepWeekAverage,
          value: metrics.meanDurationMinutes == null
              ? null
              : SleepDurationText(
                  duration: Duration(
                    minutes: metrics.meanDurationMinutes!.round(),
                  ),
                  size: 22,
                  weight: FontWeight.w400,
                ),
          have: metrics.nightCount,
          need: SleepGates.minNightsForAverage,
          caption: sleepNightsOfText(
            context,
            metrics.nightCount,
            metrics.windowNights,
          ),
        ),
        _Figure(
          label: strings.sleepWeekConsistency,
          value: metrics.midpointSdMinutes == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '±',
                      style: AppText.amount.copyWith(
                        fontSize: 18,
                        color: TrainColors.ink2,
                      ),
                    ),
                    SleepDurationText(
                      duration: Duration(
                        minutes: metrics.midpointSdMinutes!.round(),
                      ),
                      size: 22,
                      weight: FontWeight.w400,
                    ),
                  ],
                ),
          have: metrics.nightCount,
          need: SleepGates.minNightsForVariability,
        ),
        _Figure(
          label: strings.sleepWeekOnTarget,
          value: metrics.nightsOnTargetBedtime == null
              ? null
              : Text(
                  strings.sleepOnTargetRatio(
                    metrics.nightsOnTargetBedtime!,
                    metrics.nightCount,
                  ),
                  maxLines: 1,
                  style: AppText.amount.copyWith(fontSize: 20),
                ),
          have: metrics.nightCount,
          need: SleepGates.minNightsForAverage,
        ),

        const SizedBox(height: AppSpacing.m),
        _WeekComparison(comparison: controller.comparison),
      ],
    );
  }
}

/// One figure, or an honest statement of how far off it is.
///
/// The gate is rendered, not hidden: "Not enough nights yet — 3 of 5" tells
/// the user what would make it appear, where a blank row just looks broken.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.have,
    required this.need,
    this.caption,
  });

  final String label;

  /// Null when the figure's gate has not passed. Durations pass a
  /// [SleepDurationText] so the unit stays out of the mono run.
  final Widget? value;
  final int have;
  final int need;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppText.rowTitle.copyWith(color: TrainColors.ink2),
                ),
                if (value != null && caption != null)
                  Text(
                    caption!,
                    style: AppText.meta.copyWith(
                      color: TrainColors.ink4,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          if (value == null)
            Flexible(
              child: Text(
                strings.sleepInsufficientFor(have, need),
                textAlign: TextAlign.end,
                style: AppText.meta.copyWith(color: TrainColors.ink4),
              ),
            )
          else
            value!,
        ],
      ),
    );
  }
}

/// Week over week — including the case where the honest answer is "about the
/// same", which is a finding rather than a failure to find one.
class _WeekComparison extends StatelessWidget {
  const _WeekComparison({required this.comparison});

  final SleepComparison comparison;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final delta = comparison.deltaMinutes;

    final text = switch (comparison.verdict) {
      // The WEAKER of the two weeks, not the current one. A comparison needs
      // both halves, so reporting "5 of 5" because this week is full while
      // last week is empty tells the reader nothing and reads as a bug.
      SleepComparisonVerdict.insufficientData => strings.sleepInsufficientFor(
        comparison.currentNights < comparison.previousNights
            ? comparison.currentNights
            : comparison.previousNights,
        SleepGates.minNightsPerWeekForComparison,
      ),
      SleepComparisonVerdict.unchanged => strings.sleepWeekUnchanged,
      SleepComparisonVerdict.improved => strings.sleepWeekImproved(
        sleepMinutesText(context, delta!),
      ),
      SleepComparisonVerdict.declined => strings.sleepWeekDeclined(
        sleepMinutesText(context, delta!),
      ),
    };

    return Text(
      text,
      style: AppText.body.copyWith(
        color: comparison.verdict == SleepComparisonVerdict.insufficientData
            ? TrainColors.ink4
            : TrainColors.ink2,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Insights
// ---------------------------------------------------------------------------

/// What the week means — two or three sentences, each with the number of
/// nights it rests on.
///
/// These are the **deterministic** tier (`sleep_insight.dart`): pure
/// arithmetic that is always available and grounded by construction, produced
/// only for figures that passed their gate. The model layer
/// (`functions/ai/sleep_insights.js`) replaces the wording, never the set —
/// and whatever it writes goes through the same numeral gate before it can be
/// shown. When nothing qualifies, this section says so in a sentence rather
/// than disappearing, because "we cannot tell you yet" is an answer.
class _Insights extends StatelessWidget {
  const _Insights({required this.controller});

  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final sheet = controller.factSheet;
    final drafts = deterministicInsights(
      sheet: sheet,
      metrics: controller.weekMetrics,
      comparison: controller.comparison,
      trend: controller.trend,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainSectionLabel(strings.sleepInsightsTitle),
        const SizedBox(height: AppSpacing.m),
        for (final draft in drafts)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.m),
            child: _Insight(draft: draft),
          ),
      ],
    );
  }
}

class _Insight extends StatelessWidget {
  const _Insight({required this.draft});

  final SleepInsightDraft draft;

  @override
  Widget build(BuildContext context) {
    final text = sleepInsightText(context, draft);
    if (text == null) return const SizedBox.shrink();

    final insufficient = draft.kind == SleepInsightKind.insufficientData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: AppText.aside(context).copyWith(
            color: insufficient ? TrainColors.ink3 : TrainColors.ink,
          ),
        ),
        // The provenance footnote. An insight that cannot say what it rests on
        // does not get shown at all.
        if (!insufficient) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l(context).sleepInsightBasis(draft.nightCount),
            style: AppText.sectionLabel.copyWith(
              color: TrainColors.ink4,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Manual logging
// ---------------------------------------------------------------------------

/// "I'm going to sleep" / "I'm awake".
///
/// Always available, not a fallback for when the health read fails. On iOS an
/// iPhone with no watch produces **no automatic sleep data at all** since iOS
/// 18 removed time-in-bed tracking, so for a large share of users this is the
/// only way sleep gets into ZIVO (`docs/SLEEP_SYSTEM.md` §3).
class _Log extends StatelessWidget {
  const _Log({required this.controller});

  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final mark = controller.openMark;

    if (mark != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.sleepMarkOpenSince(
              // A mark is the user's own statement, so the minute they tapped
              // is exactly what is shown — no method-based rounding applies.
              ltrFor(context, formatClockTime(context, mark.localAt)),
            ),
            style: AppText.body.copyWith(color: TrainColors.ink2),
          ),
          const SizedBox(height: AppSpacing.m),
          _PrimaryAction(
            label: strings.sleepImAwake,
            onTap: () => controller.markAwake(
              providerName: l(context).sleepProviderYou,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          _TextAction(
            label: strings.sleepMarkCancel,
            onTap: controller.cancelOpenMark,
          ),
        ],
      );
    }

    return _PrimaryAction(
      label: strings.sleepGoingToSleep,
      onTap: controller.markGoingToSleep,
    );
  }
}

// ---------------------------------------------------------------------------
// Empty states
// ---------------------------------------------------------------------------

/// Nothing to show — and the wording depends on **why**.
///
/// The three cases are genuinely different claims and must not collapse into
/// one "no data" screen:
///
/// * the platform confirmed a refusal → say so, and offer the fix;
/// * the platform will not say (iOS, always) → say the data is not *visible*,
///   which is all we know;
/// * the platform confirmed access and returned nothing → only here may the
///   screen say there is no sleep recorded.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller});

  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final state = controller.syncState;
    final provider = sleepProviderStoreName(
      context,
      isApple: !kIsWeb && Platform.isIOS,
    );

    final (title, body, action) = switch (state.status) {
      SleepSyncStatus.permissionDenied => (
        strings.sleepPermissionDeniedTitle,
        strings.sleepPermissionDeniedBody(provider),
        strings.sleepConnect(provider),
      ),
      SleepSyncStatus.unavailable => (
        strings.sleepUnavailableTitle,
        strings.sleepUnavailableBody,
        null,
      ),
      SleepSyncStatus.historyUnavailable => (
        strings.sleepNoDataTitle,
        strings.sleepHistoryUnavailable(provider),
        strings.sleepConnect(provider),
      ),
      SleepSyncStatus.failed => (
        strings.sleepNoDataTitle,
        strings.sleepSyncFailed,
        null,
      ),
      SleepSyncStatus.idle || SleepSyncStatus.syncing =>
        controller.canAssertNoData
            ? (
                strings.sleepNoDataTitle,
                strings.sleepNoDataBody,
                strings.sleepConnect(provider),
              )
            // The iOS case. We know nothing came back; we do not know we were
            // allowed to look, so we do not claim there is nothing there.
            : (
                strings.sleepNotVisibleTitle,
                strings.sleepNotVisibleBody(provider),
                strings.sleepConnect(provider),
              ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.cardTitle),
        const SizedBox(height: AppSpacing.s),
        Text(body, style: AppText.body.copyWith(color: TrainColors.ink2)),
        const SizedBox(height: AppSpacing.l),
        if (action != null) ...[
          _PrimaryAction(label: action, onTap: controller.requestAccess),
          const SizedBox(height: AppSpacing.s),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared bits
// ---------------------------------------------------------------------------

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.label, required this.onTap});

  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: TrainColors.violet,
        foregroundColor: const Color(0xFF0B0A14),
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
      onPressed: () => onTap(),
      child: Text(label, style: AppText.button),
    ),
  );
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Text(
      label,
      style: AppText.meta.copyWith(color: TrainColors.violetGlyph),
    ),
  );
}
