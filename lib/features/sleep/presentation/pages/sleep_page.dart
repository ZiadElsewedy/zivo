import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/date_format.dart';
import '../../../../core/widgets/async_action.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/zivo_toast.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/sleep_insight.dart';
import '../../domain/sleep_metrics.dart';
import '../../domain/sleep_night.dart';
import '../../domain/sleep_service.dart';
import '../controllers/sleep_controller.dart';
import '../sleep_insight_labels.dart';
import '../sleep_labels.dart';
import '../widgets/sleep_about_sheet.dart';
import '../widgets/sleep_axis.dart';
import '../widgets/sleep_bar.dart';
import '../widgets/sleep_duration_text.dart';
import '../widgets/sleep_edit_night_sheet.dart';
import '../widgets/sleep_source_chip.dart';
import '../widgets/sleep_targets_sheet.dart';
import '../widgets/sleep_week_raster.dart';
import '../widgets/sleep_why_sheet.dart';

/// The Sleep screen: tonight, last night, the week, and what it means — in
/// that order, on one scroll, over a docked action.
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
///
/// ## Why the primary action is docked
///
/// "I'm going to sleep" used to be the last widget in the scroll, and the
/// state it opens rendered in place of it — at the very bottom of a page long
/// enough to push the result below the fold. Tapping the one control on the
/// screen therefore looked like it did nothing: the pill you just pressed
/// scrolled out of view and a line of text took its place where you were not
/// looking. It is docked now, and the session it opens is announced at the
/// **top** of the scroll ([_SessionCard]), so one tap changes the screen in
/// two places at once and neither of them can be off-screen.
class SleepPage extends StatefulWidget {
  const SleepPage({super.key});

  @override
  State<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends State<SleepPage> with AsyncAction<SleepPage> {
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
    final strings = l(context);

    return TrainScreen(
      tint: TrainColors.sleepTint,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                0,
                AppSpacing.screen,
                AppSpacing.base,
              ),
              child: TrainPageHeader(
                title: strings.sleepTitle,
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TrainHeaderAction(
                      icon: AppIcons.info,
                      accent: TrainColors.sleepAccent,
                      semanticLabel: strings.sleepAboutTitle,
                      onTap: () => showSleepAboutSheet(context),
                    ),
                    TrainHeaderAction(
                      icon: AppIcons.sleepTargets,
                      accent: TrainColors.sleepAccent,
                      semanticLabel: strings.sleepTargetsTitle,
                      onTap: () => _editTargets(controller),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: TrainColors.sleepGlyph,
                backgroundColor: TrainColors.raised,
                onRefresh: () => controller.refresh(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    0,
                    AppSpacing.screen,
                    AppSpacing.m,
                  ),
                  children: [
                    if (controller.openMark != null) ...[
                      RiseIn(
                        child: _SessionCard(
                          controller: controller,
                          onCancel: _cancelMark,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.section),
                    ],
                    RiseIn(child: _LastNight(controller: controller)),
                    const SizedBox(height: AppSpacing.section),
                    RiseIn(
                      delay: const Duration(milliseconds: 60),
                      child: _Week(controller: controller),
                    ),
                    const SizedBox(height: AppSpacing.section),
                    RiseIn(
                      delay: const Duration(milliseconds: 120),
                      child: _Insights(controller: controller),
                    ),
                  ],
                ),
              ),
            ),
            _ActionDock(
              awake: controller.openMark == null,
              busy: actionInFlight,
              onTap: () => _toggleMark(controller),
            ),
          ],
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

  /// The one committing action on this screen, both ways round.
  ///
  /// Guarded and reported. A manual log is the only path to sleep data for an
  /// iPhone with no watch (`docs/SLEEP_SYSTEM.md` §3), so a write that fails
  /// silently is not a cosmetic problem — the user goes to bed believing the
  /// night is being recorded.
  Future<void> _toggleMark(SleepController controller) =>
      runAction(#mark, () async {
        final providerName = l(context).sleepProviderYou;
        try {
          if (controller.openMark == null) {
            await controller.markGoingToSleep();
          } else {
            await controller.markAwake(providerName: providerName);
          }
        } catch (_) {
          _reportFailure();
        }
      });

  Future<void> _cancelMark() => runAction(#cancel, () async {
    try {
      await _controller!.cancelOpenMark();
    } catch (_) {
      _reportFailure();
    }
  });

  void _reportFailure() {
    if (!mounted) return;
    showZivoToast(
      context,
      l(context).sleepMarkFailed,
      kind: ToastKind.error,
    );
  }
}

// ---------------------------------------------------------------------------
// The open session
// ---------------------------------------------------------------------------

/// **Tonight.** The card that appears the moment "I'm going to sleep" lands.
///
/// It is the visible half of the fix described on [SleepPage]: the state a tap
/// creates is announced at the top of the page, not at the bottom where the
/// button was. It also has a job of its own — saying plainly that *nothing is
/// being measured*. An open session is two timestamps and a promise; the
/// elapsed figure here is arithmetic on the clock, not a reading, and the hint
/// says so by naming what actually records the night.
class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.controller, required this.onCancel});

  final SleepController controller;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final mark = controller.openMark!;
    final elapsed = controller.openMarkElapsed ?? Duration.zero;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainSectionLabel(strings.sleepSessionOpen),
        const SizedBox(height: AppSpacing.s),
        TrainCard(
          border: TrainColors.sleepAccent.withValues(alpha: 0.22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x1F7C9CFF), Color(0x0A7C9CFF)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  // Under a minute a duration renders "0m", which on this
                  // screen is the one shape every figure is forbidden — so
                  // the first minute says so in words instead.
                  if (elapsed.inMinutes < 1)
                    Text(
                      strings.sleepMarkJustNow,
                      style: TrainType.ui(
                        size: 30,
                        weight: FontWeight.w700,
                        tracking: -0.02,
                        color: TrainColors.ink,
                        height: 1.1,
                      ),
                    )
                  else ...[
                    SleepDurationText(
                      duration: elapsed,
                      size: 44,
                      color: TrainColors.ink,
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Text(
                      strings.sleepMarkSoFar.toUpperCase(),
                      style: TrainType.caption(
                        size: 9,
                        tracking: 0.16,
                        color: TrainColors.sleepGlyph,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                strings.sleepMarkOpenSince(
                  // A mark is the user's own statement, so the minute they
                  // tapped is exactly what is shown — no method-based
                  // rounding applies.
                  ltrFor(context, formatClockTime(context, mark.localAt)),
                ),
                style: AppText.body.copyWith(color: TrainColors.ink2),
              ),
              const _CardRule(),
              Text(
                strings.sleepMarkHint,
                style: AppText.meta.copyWith(
                  color: TrainColors.ink3,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              _QuietAction(
                label: strings.sleepMarkCancel,
                icon: AppIcons.close,
                onTap: () => onCancel(),
              ),
            ],
          ),
        ),
      ],
    );
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
    final strings = l(context);

    // Order matters. A read that failed outranks "nothing to show": the
    // second is a statement about the user's data, and we have not earned it.
    final Widget body;
    if (controller.loadFailed) {
      body = _LoadFailed(controller: controller);
    } else if (!controller.hasLoaded) {
      // "Still loading" and "loaded and empty" must not share a rendering:
      // one is a promise, the other is a fact.
      body = const _LastNightSkeleton();
    } else if (controller.lastNight == null) {
      body = _EmptyState(controller: controller);
    } else {
      body = _LastNightCard(
        night: controller.lastNight!,
        controller: controller,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainSectionLabel(strings.sleepLastNight),
        const SizedBox(height: AppSpacing.s),
        body,
      ],
    );
  }
}

class _LastNightCard extends StatelessWidget {
  const _LastNightCard({required this.night, required this.controller});

  final SleepNight night;
  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    final session = night.main!;
    final strings = l(context);

    return GestureDetector(
      onTap: () => showSleepWhySheet(context, night),
      behavior: HitTestBehavior.opaque,
      child: TrainCard(
        padding: const EdgeInsets.fromLTRB(18, 17, 18, 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The figure, and — always, never optionally — where it came from.
            SleepDurationText(duration: session.asleepDuration, size: 52),
            const SizedBox(height: AppSpacing.m),
            Wrap(
              spacing: AppSpacing.s,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SleepSourceChip(provenance: session.provenance),
                SleepConfidenceBadge(
                  confidence: session.provenance.confidence,
                ),
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

            // The two clock times, each phrased for how it is known. This is
            // the copy contract at its most visible: "Asleep 1:47 AM" and
            // "You logged 1:30 AM" are the same row with different verbs.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    sleepOnsetText(context, session),
                    style: AppText.meta.copyWith(color: TrainColors.ink2),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    sleepWakeText(context, session),
                    textAlign: TextAlign.end,
                    style: AppText.meta.copyWith(color: TrainColors.ink2),
                  ),
                ),
              ],
            ),

            const _CardRule(),
            _TargetLines(night: night),

            if (night.naps.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                strings.sleepNapCount(night.naps.length),
                style: AppText.meta.copyWith(color: TrainColors.ink3),
              ),
            ],

            const SizedBox(height: AppSpacing.base),
            Row(
              children: [
                Flexible(
                  child: _QuietAction(
                    label: strings.sleepWhyTitle,
                    icon: AppIcons.info,
                    onTap: () => showSleepWhySheet(context, night),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Flexible(
                  child: _QuietAction(
                    label: strings.sleepEditNight,
                    icon: AppIcons.edit,
                    onTap: () => _edit(context, night),
                  ),
                ),
              ],
            ),
          ],
        ),
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
          Text(
            duration,
            style: AppText.rowTitle.copyWith(
              color: TrainColors.ink,
              fontSize: 15,
            ),
          ),
        if (bedtime != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(bedtime, style: AppText.meta.copyWith(color: TrainColors.ink3)),
        ],
      ],
    );
  }
}

/// The shape of the headline while it is still loading.
///
/// A skeleton rather than a gap. The old placeholder was a bare
/// `SizedBox(height: 120)`, which on a screen whose empty state is a whole
/// paragraph rendered as a void between the title and the week — and, when
/// the read errored and `hasLoaded` never flipped, a permanent one.
class _LastNightSkeleton extends StatelessWidget {
  const _LastNightSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: l(context).sleepLoading,
      child: TrainCard(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _SkeletonBar(width: 150, height: 34),
            SizedBox(height: AppSpacing.base),
            _SkeletonBar(width: 128, height: 12),
            SizedBox(height: AppSpacing.l),
            _SkeletonBar(width: double.infinity, height: 18),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: TrainColors.glassStrong,
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
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
        TrainSectionLabel(
          strings.sleepWeekTitle,
          // The window's own n, once, where it belongs — rather than repeated
          // under each of the three figures below it.
          trailing: sleepNightsOfText(
            context,
            metrics.nightCount,
            metrics.windowNights,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        TrainCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SleepWeekRaster(
                nights: controller.week,
                targets: controller.targets,
                onTapNight: (night) => showSleepWhySheet(context, night),
              ),
              const _CardRule(),

              // Three figures, each carrying its own n. A number without its
              // denominator is a claim without its evidence.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Figure(
                        label: strings.sleepWeekAverage,
                        value: metrics.meanDurationMinutes == null
                            ? null
                            : SleepDurationText(
                                duration: Duration(
                                  minutes: metrics.meanDurationMinutes!.round(),
                                ),
                                size: 21,
                                weight: FontWeight.w400,
                              ),
                        have: metrics.nightCount,
                        need: SleepGates.minNightsForAverage,
                      ),
                    ),
                    const _FigureDivider(),
                    Expanded(
                      child: _Figure(
                        label: strings.sleepWeekConsistency,
                        value: metrics.midpointSdMinutes == null
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment:
                                    CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    '±',
                                    style: TrainType.mono(
                                      size: 15,
                                      color: TrainColors.ink3,
                                    ),
                                  ),
                                  SleepDurationText(
                                    duration: Duration(
                                      minutes: metrics.midpointSdMinutes!
                                          .round(),
                                    ),
                                    size: 21,
                                    weight: FontWeight.w400,
                                  ),
                                ],
                              ),
                        have: metrics.nightCount,
                        need: SleepGates.minNightsForVariability,
                      ),
                    ),
                    const _FigureDivider(),
                    Expanded(
                      child: _Figure(
                        label: strings.sleepWeekOnTarget,
                        value: metrics.nightsOnTargetBedtime == null
                            ? null
                            : Text(
                                strings.sleepOnTargetRatio(
                                  metrics.nightsOnTargetBedtime!,
                                  metrics.nightCount,
                                ),
                                maxLines: 1,
                                style: TrainType.mono(
                                  size: 21,
                                  tracking: -0.03,
                                  color: TrainColors.ink,
                                ),
                              ),
                        have: metrics.nightCount,
                        need: SleepGates.minNightsForAverage,
                      ),
                    ),
                  ],
                ),
              ),

              const _CardRule(),
              _WeekComparison(comparison: controller.comparison),
            ],
          ),
        ),
      ],
    );
  }
}

/// One figure of the weekly three-up, or an honest statement of how far off
/// it is.
///
/// The gate is rendered, not hidden: an em dash over "1 of 3 nights" tells the
/// user what would make the figure appear, where a blank column just looks
/// broken. It used to be a full-width row reading "Not enough nights yet —
/// 1 of 3", three times over, which is the same fact stated three times in
/// three long grey sentences. The claim is unchanged; only its density is.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.have,
    required this.need,
  });

  final String label;

  /// Null when the figure's gate has not passed. Durations pass a
  /// [SleepDurationText] so the unit stays out of the mono run.
  final Widget? value;
  final int have;
  final int need;

  @override
  Widget build(BuildContext context) {
    final gated = value == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(
            height: 26,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child:
                    value ??
                    Text(
                      '—',
                      style: TrainType.mono(
                        size: 20,
                        color: TrainColors.ink4,
                      ),
                    ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TrainType.caption(
              size: 8.5,
              tracking: 0.14,
              color: TrainColors.ink3,
            ),
          ),
          const SizedBox(height: 4),
          // The slot is reserved either way so the three columns keep one
          // baseline whether or not their gates have passed.
          SizedBox(
            height: 13,
            child: gated
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      l(context).sleepGateProgress(have, need),
                      maxLines: 1,
                      style: TrainType.caption(
                        size: 8.5,
                        tracking: 0.06,
                        color: TrainColors.ink4,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _FigureDivider extends StatelessWidget {
  const _FigureDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    margin: const EdgeInsets.symmetric(vertical: 2),
    color: TrainColors.hairline,
  );
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
    final insufficient =
        comparison.verdict == SleepComparisonVerdict.insufficientData;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Labelled, because unlabelled it read as a fourth stray figure
        // repeating the "not enough nights" line above it.
        Text(
          strings.sleepVsLastWeek.toUpperCase(),
          style: TrainType.caption(
            size: 8.5,
            tracking: 0.16,
            color: TrainColors.ink4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          text,
          style: AppText.body.copyWith(
            color: insufficient ? TrainColors.ink3 : TrainColors.ink2,
          ),
        ),
      ],
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
///
/// **Set in Manrope, not the italic serif.** This was ZIVO's speaking voice
/// (`AppText.aside`) and the owner ruled it out here: at 21px italic over a
/// paragraph of near-black it is the least readable text on the screen, and
/// the sentences it carries are the screen's conclusions. The voice stays the
/// serif elsewhere (ADR-009); this section reports rather than speaks.
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

    final rendered = [
      for (final draft in drafts)
        if (sleepInsightText(context, draft) != null) draft,
    ];
    if (rendered.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainSectionLabel(strings.sleepInsightsTitle),
        const SizedBox(height: AppSpacing.s),
        TrainCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < rendered.length; i++) ...[
                if (i > 0) const _CardRule(),
                _Insight(draft: rendered[i]),
              ],
            ],
          ),
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
    final text = sleepInsightText(context, draft)!;
    final insufficient = draft.kind == SleepInsightKind.insufficientData;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A short accent rule rather than a bullet: it marks where a sentence
        // starts without pretending the sentences are a list of equals.
        Container(
          width: 2,
          height: 17,
          margin: const EdgeInsetsDirectional.only(top: 4, end: AppSpacing.m),
          decoration: BoxDecoration(
            color: insufficient
                ? TrainColors.hairlineStrong
                : TrainColors.sleepAccent,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: TrainType.ui(
                  size: 15.5,
                  weight: FontWeight.w500,
                  height: 1.45,
                  color: insufficient ? TrainColors.ink3 : TrainColors.ink,
                ),
              ),
              // The provenance footnote. An insight that cannot say what it
              // rests on does not get shown at all.
              if (!insufficient) ...[
                const SizedBox(height: 6),
                Text(
                  l(context).sleepInsightBasis(draft.nightCount),
                  style: TrainType.caption(
                    size: 8.5,
                    tracking: 0.14,
                    color: TrainColors.ink4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty and failed states
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

    return _MessageCard(
      icon: AppIcons.sleep,
      title: title,
      body: body,
      action: action,
      onAction: controller.requestAccess,
    );
  }
}

/// Storage refused, rather than the health store. See
/// [SleepController.loadFailed] for why this is its own screen and not a
/// placeholder that never resolves.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.controller});

  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    return _MessageCard(
      icon: AppIcons.warning,
      title: strings.sleepLoadFailedTitle,
      body: strings.sleepLoadFailedBody,
      action: strings.sleepRetry,
      onAction: controller.retryLoad,
    );
  }
}

/// A titled card with one sentence and at most one action — the shape every
/// "there is nothing here, and here is why" state on this screen takes.
class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return TrainCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TrainIconTile(
            icon: icon,
            accent: TrainColors.sleepGlyph,
            size: 34,
            iconSize: 16,
          ),
          const SizedBox(height: AppSpacing.base),
          Text(
            title,
            style: AppText.cardTitle.copyWith(fontSize: 19, height: 1.25),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(body, style: AppText.body.copyWith(color: TrainColors.ink2)),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.base),
            _QuietAction(
              label: action!,
              icon: AppIcons.sleepSync,
              onTap: () => onAction(),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chrome
// ---------------------------------------------------------------------------

/// The docked primary action. See [SleepPage] for why it is not in the scroll.
class _ActionDock extends StatelessWidget {
  const _ActionDock({
    required this.awake,
    required this.busy,
    required this.onTap,
  });

  /// Whether there is *no* open session — i.e. the button offers to open one.
  final bool awake;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.base,
        AppSpacing.screen,
        TrainBottomInset.of(context),
      ),
      decoration: const BoxDecoration(
        // The list scrolls under the dock; the scrim is what keeps a row of
        // text from ending mid-fade against the pill.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00080908), TrainColors.base, TrainColors.base],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Opacity(
        opacity: busy ? 0.6 : 1,
        child: TrainPrimaryButton(
          label: awake ? strings.sleepGoingToSleep : strings.sleepImAwake,
          icon: Icon(
            awake ? AppIcons.sleep : AppIcons.sleepWoke,
            size: 17,
            color: TrainColors.sleepOnAccent,
          ),
          color: TrainColors.sleepAccent,
          labelColor: TrainColors.sleepOnAccent,
          height: 56,
          onTap: busy ? () {} : onTap,
        ),
      ),
    );
  }
}

/// A small glass pill — the secondary actions inside a card ("Why this
/// number", "Edit this night", "Try again").
///
/// These were bare violet text links, which at 13px on a dark ground read as
/// coloured captions rather than as controls and sat well under the 44px
/// touch target.
class _QuietAction extends StatelessWidget {
  const _QuietAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: TrainColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: TrainColors.hairlineStrong),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: TrainColors.sleepGlyph),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TrainType.ui(
                      size: 13,
                      weight: FontWeight.w600,
                      height: 1,
                      color: TrainColors.inkPlain,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The hairline that separates the bands inside a card, with the vertical
/// rhythm the cards on this screen share.
class _CardRule extends StatelessWidget {
  const _CardRule();

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: AppSpacing.base),
    color: TrainColors.hairline,
  );
}
