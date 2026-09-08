import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/util/date_format.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/sleep_metrics.dart';
import '../../domain/sleep_night.dart';
import '../../domain/sleep_stage_breakdown.dart';
import '../controllers/sleep_controller.dart';
import '../sleep_labels.dart';
import '../widgets/sleep_duration_text.dart';
import '../widgets/sleep_stage_split.dart';
import '../widgets/sleep_week_raster.dart';
import '../widgets/sleep_why_sheet.dart';

/// **Sleep history — a week at a time, and the run behind it.**
///
/// Deliberately not "the dashboard with seven of everything". A daily screen
/// answers *how did I sleep*; this one answers questions a single night cannot
/// pose:
///
/// * is my schedule drifting? — the raster, one shared axis, seven rows;
/// * what does a typical night look like? — mean and median duration, and the
///   **circular** mean bedtime and wake time;
/// * how did each night actually go? — one row per day, gaps included;
/// * what is it made of? — stage composition averaged over the staged nights;
/// * where is it heading? — the four-week Theil–Sen trend, and the week
///   before this one.
///
/// ## Paging
///
/// The week is chosen by [_weekEnd], and every figure on the page is derived
/// from that one date through [SleepController.weekEndingOn] and
/// [SleepController.metricsFor]. There is no second definition of "a week"
/// here — which is the reason this page can page backwards at all without the
/// numbers on it drifting out of agreement with the dashboard's.
///
/// ## The controller is passed in, not built
///
/// It is the same [SleepController] the dashboard is already running, handed
/// down the route. Constructing a second one would open a second set of
/// Firestore snapshot listeners on the same three documents, and — worse —
/// the two would settle their first frames independently, so a user tapping
/// through would watch a page of figures they had just been shown re-resolve
/// in front of them.
class SleepWeekPage extends StatefulWidget {
  const SleepWeekPage({required this.controller, super.key});

  final SleepController controller;

  @override
  State<SleepWeekPage> createState() => _SleepWeekPageState();
}

class _SleepWeekPageState extends State<SleepWeekPage> {
  /// How many weeks back from today is being shown. `0` is the seven days
  /// ending today.
  int _weeksBack = 0;

  SleepController get _c => widget.controller;

  DateTime get _weekEnd =>
      _c.today.subtract(Duration(days: 7 * _weeksBack));

  DateTime get _weekStart => _weekEnd.subtract(const Duration(days: 6));

  /// How far back paging is allowed to go.
  ///
  /// Bounded by what storage actually holds: `FirestoreSleepRepository`
  /// mirrors 120 nights, so paging past that would walk into weeks that are
  /// empty because we did not load them, not because nothing was recorded —
  /// an empty state that is a lie about the user's data.
  static const int _maxWeeksBack = 16;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);

    return TrainScreen(
      tint: TrainColors.sleepTint,
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final nights = _c.weekEndingOn(_weekEnd);
          final metrics = _c.metricsFor(nights);
          final hasAny = nights.any((night) => night.hasData);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  0,
                  AppSpacing.screen,
                  AppSpacing.base,
                ),
                child: TrainPageHeader(
                  title: strings.sleepHistoryTitle,
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: TrainColors.sleepGlyph,
                  backgroundColor: TrainColors.raised,
                  onRefresh: () => _c.refresh(),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.screen,
                      0,
                      AppSpacing.screen,
                      TrainBottomInset.of(context),
                    ),
                    children: [
                      RiseIn(
                        child: _WeekPager(
                          start: _weekStart,
                          end: _weekEnd,
                          isCurrent: _weeksBack == 0,
                          canGoEarlier: _weeksBack < _maxWeeksBack,
                          canGoLater: _weeksBack > 0,
                          onEarlier: () => setState(() => _weeksBack++),
                          onLater: () => setState(() => _weeksBack--),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),

                      // The raster stays even for an empty week: seven blank
                      // rows on a shared axis is what "nothing recorded" looks
                      // like, and it keeps the page from changing shape as the
                      // user pages back through patchy history.
                      RiseIn(
                        delay: const Duration(milliseconds: 40),
                        child: _RasterCard(
                          nights: nights,
                          controller: _c,
                          metrics: metrics,
                          empty: !hasAny,
                        ),
                      ),

                      if (hasAny) ...[
                        const SizedBox(height: AppSpacing.section),
                        RiseIn(
                          delay: const Duration(milliseconds: 80),
                          child: _TypicalNight(metrics: metrics),
                        ),
                        const SizedBox(height: AppSpacing.section),
                        RiseIn(
                          delay: const Duration(milliseconds: 120),
                          child: _Composition(
                            averages: _c.stageAveragesFor(nights),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.section),
                        RiseIn(
                          delay: const Duration(milliseconds: 160),
                          child: _NightList(nights: nights),
                        ),
                      ],

                      // The trend is of the last four weeks regardless of
                      // which week is on screen, so it is labelled for its own
                      // window and shown even on an empty one — a blank week
                      // is a fact the trend already accounts for.
                      const SizedBox(height: AppSpacing.section),
                      RiseIn(
                        delay: const Duration(milliseconds: 200),
                        child: _LongerRun(controller: _c),
                      ),
                      const SizedBox(height: AppSpacing.m),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Which week
// ---------------------------------------------------------------------------

/// The week selector: two arrows and the span between them.
///
/// The span is spelled out as dates rather than as "3 weeks ago", because the
/// day rows below it are dated and a reader comparing the two should not have
/// to convert between a relative label and an absolute one.
class _WeekPager extends StatelessWidget {
  const _WeekPager({
    required this.start,
    required this.end,
    required this.isCurrent,
    required this.canGoEarlier,
    required this.canGoLater,
    required this.onEarlier,
    required this.onLater,
  });

  final DateTime start;
  final DateTime end;
  final bool isCurrent;
  final bool canGoEarlier;
  final bool canGoLater;
  final VoidCallback onEarlier;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    return Row(
      children: [
        _PagerButton(
          // Directional, so "earlier" points left in English and right in
          // Arabic — an arrow that means "back in time" has to follow the
          // reading direction or it means the opposite.
          icon: Icons.chevron_left_rounded,
          semanticLabel: strings.sleepWeekEarlier,
          enabled: canGoEarlier,
          onTap: onEarlier,
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                isCurrent
                    ? strings.sleepWeekCurrent
                    : strings.sleepWeekRange(
                        formatMonthDay(context, start),
                        formatMonthDay(context, end),
                      ),
                textAlign: TextAlign.center,
                style: AppText.rowTitle.copyWith(fontSize: 15),
              ),
              if (isCurrent) ...[
                const SizedBox(height: 2),
                Text(
                  strings.sleepWeekRange(
                    formatMonthDay(context, start),
                    formatMonthDay(context, end),
                  ),
                  textAlign: TextAlign.center,
                  style: AppText.meta.copyWith(color: TrainColors.ink4),
                ),
              ],
            ],
          ),
        ),
        _PagerButton(
          icon: Icons.chevron_right_rounded,
          semanticLabel: strings.sleepWeekLater,
          enabled: canGoLater,
          onTap: onLater,
        ),
      ],
    );
  }
}

class _PagerButton extends StatelessWidget {
  const _PagerButton({
    required this.icon,
    required this.semanticLabel,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Disabled rather than absent: a control that vanishes at the end of the
    // range makes the two arrows swap places under the user's thumb.
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: PressableScale(
        child: Material(
          color: TrainColors.glass,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: TrainColors.hairlineStrong),
              ),
              child: Icon(
                icon,
                size: 20,
                color: enabled ? TrainColors.sleepGlyph : TrainColors.ink4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The chart
// ---------------------------------------------------------------------------

/// The raster, and the week's headline count under it.
class _RasterCard extends StatelessWidget {
  const _RasterCard({
    required this.nights,
    required this.controller,
    required this.metrics,
    required this.empty,
  });

  final List<SleepNight> nights;
  final SleepController controller;
  final SleepWindowMetrics metrics;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    return TrainCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SleepWeekRaster(
            nights: nights,
            targets: controller.targets,
            onTapNight: (night) => showSleepWhySheet(context, night),
          ),
          const _CardRule(),
          Text(
            empty
                ? strings.sleepWeekEmpty
                : sleepNightsOfText(
                    context,
                    metrics.nightCount,
                    metrics.windowNights,
                  ),
            style: AppText.meta.copyWith(
              color: empty ? TrainColors.ink3 : TrainColors.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The typical night
// ---------------------------------------------------------------------------

/// Mean and median duration, and the week's typical bedtime and wake time.
///
/// **The two clock times are circular means** (`SleepMetrics`), which is the
/// one arithmetic in this feature that cannot be done the obvious way: the
/// ordinary average of 23:40 and 00:20 is noon. They are shown next to the
/// durations because the pair is what a schedule *is*, and reading them apart
/// is how a user concludes their sleep is fine while their timing has moved
/// two hours.
///
/// Mean and median sit together for a different reason: where they disagree,
/// the week was irregular, and that disagreement is itself the finding.
class _TypicalNight extends StatelessWidget {
  const _TypicalNight({required this.metrics});

  final SleepWindowMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainSectionLabel(
          strings.sleepWeekTypicalTitle,
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
            children: [
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
                        label: strings.sleepWeekMedian,
                        value: metrics.medianDurationMinutes == null
                            ? null
                            : SleepDurationText(
                                duration: Duration(
                                  minutes: metrics.medianDurationMinutes!
                                      .round(),
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
                            : Text(
                                ltrFor(
                                  context,
                                  sleepVariabilityText(
                                    context,
                                    metrics.midpointSdMinutes!,
                                  ),
                                ),
                                maxLines: 1,
                                style: TrainType.mono(
                                  size: 18,
                                  tracking: -0.03,
                                  color: TrainColors.ink,
                                ),
                              ),
                        have: metrics.nightCount,
                        need: SleepGates.minNightsForVariability,
                      ),
                    ),
                  ],
                ),
              ),
              const _CardRule(),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Figure(
                        label: strings.sleepWeekBedtime,
                        value: _clock(context, metrics.meanBedtimeMinutes),
                        have: metrics.nightCount,
                        need: SleepGates.minNightsForAverage,
                      ),
                    ),
                    const _FigureDivider(),
                    Expanded(
                      child: _Figure(
                        label: strings.sleepWeekWake,
                        value: _clock(context, metrics.meanWakeMinutes),
                        have: metrics.nightCount,
                        need: SleepGates.minNightsForAverage,
                      ),
                    ),
                    const _FigureDivider(),
                    Expanded(
                      child: _Figure(
                        label: strings.sleepWeekOnTarget,
                        value: metrics.nightsOnTargetBedtime == null
                            ? null
                            : Text(
                                ltrFor(
                                  context,
                                  strings.sleepOnTargetRatio(
                                    metrics.nightsOnTargetBedtime!,
                                    metrics.nightCount,
                                  ),
                                ),
                                maxLines: 1,
                                style: TrainType.mono(
                                  size: 19,
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
            ],
          ),
        ),
      ],
    );
  }

  Widget? _clock(BuildContext context, double? minutes) {
    if (minutes == null) return null;
    return Text(
      ltrFor(
        context,
        formatMinutesSinceMidnight(context, minutes.round()),
      ),
      maxLines: 1,
      style: TrainType.mono(
        size: 18,
        tracking: -0.03,
        color: TrainColors.ink,
      ),
    );
  }
}

/// One figure of a three-up, or an honest statement of how far off it is.
///
/// The gate is rendered, not hidden: an em dash over "1 of 3 nights" tells the
/// user what would make the figure appear, where a blank column just looks
/// broken.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.have,
    required this.need,
  });

  final String label;

  /// Null when the figure's gate has not passed.
  final Widget? value;
  final int have;
  final int need;

  @override
  Widget build(BuildContext context) {
    final gated = value == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Column(
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
                      style: TrainType.mono(size: 20, color: TrainColors.ink4),
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
          // The slot is reserved either way so the columns keep one baseline
          // whether or not their gates have passed.
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

// ---------------------------------------------------------------------------
// Composition
// ---------------------------------------------------------------------------

/// The week's average stage split, over **the staged nights only**.
///
/// The denominator is the reason this section is worth having separately from
/// the daily one. A user with three staged nights out of seven has a real
/// answer to "what is my sleep made of" and no answer at all to "how much deep
/// sleep did I get this week" — so the shares are averaged per staged night
/// and the count of staged nights is printed under them, rather than a weekly
/// total that would silently treat four unstaged nights as zero deep sleep.
class _Composition extends StatelessWidget {
  const _Composition({required this.averages});

  final SleepStageAverages? averages;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final split = averages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainSectionLabel(strings.sleepWeekCompositionTitle),
        const SizedBox(height: AppSpacing.s),
        TrainCard(
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 17),
          child: split == null
              ? Text(
                  strings.sleepWeekNoStages,
                  style: AppText.body.copyWith(color: TrainColors.ink3),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SleepStageSplit(
                      // Reusing the daily widget on the weekly averages keeps
                      // one visual language for stages: the same ramp, the
                      // same ordering, the same rows. A second stage chart
                      // would be a second thing to keep in agreement.
                      breakdown: SleepStageBreakdown(
                        light: split.meanLight,
                        deep: split.meanDeep,
                        rem: split.meanRem,
                        awake: Duration.zero,
                        unspecified: Duration.zero,
                        stagedTotal: split.meanAsleep,
                      ),
                      sessionDuration: split.meanAsleep,
                    ),
                    const SizedBox(height: AppSpacing.m),
                    Text(
                      strings.sleepWeekCompositionBasis(split.nightsWithStages),
                      style: TrainType.caption(
                        size: 8.5,
                        tracking: 0.14,
                        color: TrainColors.ink4,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Every night
// ---------------------------------------------------------------------------

/// The week, day by day — the part a raster cannot do.
///
/// A raster shows drift; it does not let you read Tuesday's actual figures.
/// Both are here because they are answers to different questions and the list
/// is the one a user checks against their memory of the week.
///
/// **Every day in the window has a row, including the empty ones.** Filtering
/// them out would make a three-night week look like a three-day week and quietly
/// remove the most actionable thing on the page.
class _NightList extends StatelessWidget {
  const _NightList({required this.nights});

  final List<SleepNight> nights;

  @override
  Widget build(BuildContext context) {
    // Newest first: the most recent night is the one the reader came for.
    final ordered = nights.reversed.toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainSectionLabel(l(context).sleepWeekNightsTitle),
        const SizedBox(height: AppSpacing.s),
        TrainCard(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            children: [
              for (var i = 0; i < ordered.length; i++) ...[
                if (i > 0)
                  Container(height: 1, color: TrainColors.hairline),
                _NightRow(night: ordered[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NightRow extends StatelessWidget {
  const _NightRow({required this.night});

  final SleepNight night;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final session = night.main;
    final breakdown = session == null
        ? null
        : SleepStageBreakdown.forSession(session);

    return Semantics(
      button: session != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: session == null
            ? null
            : () => showSleepWhySheet(context, night),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 42,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatWeekdayShort(context, night.sleepDay),
                      style: AppText.rowTitle.copyWith(
                        fontSize: 13,
                        color: session == null
                            ? TrainColors.ink4
                            : TrainColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ltrFor(context, '${night.sleepDay.day}'),
                      style: TrainType.mono(
                        size: 11,
                        color: TrainColors.ink4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: session == null
                    // In words, never as `0h 0m`. A zero is a statement about
                    // the night; this is a statement about the data.
                    ? Text(
                        strings.sleepNightRowNoData,
                        style: AppText.meta.copyWith(color: TrainColors.ink4),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ltrFor(
                              context,
                              strings.sleepNightRowRange(
                                sleepClockText(
                                  context,
                                  session.localStart,
                                  session.provenance,
                                ),
                                sleepClockText(
                                  context,
                                  session.localEnd,
                                  session.provenance,
                                ),
                              ),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.meta.copyWith(
                              color: TrainColors.ink2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  sleepMethodLabel(
                                    context,
                                    session.provenance.method,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TrainType.caption(
                                    size: 8.5,
                                    tracking: 0.12,
                                    color: TrainColors.ink4,
                                  ),
                                ),
                              ),
                              // A stage strip only where stages exist — the
                              // row's own version of the rule that a stage
                              // figure is measured or absent.
                              if (breakdown != null) ...[
                                const SizedBox(width: AppSpacing.s),
                                _StageStrip(breakdown: breakdown),
                              ],
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: AppSpacing.s),
              if (session != null)
                SleepDurationText(
                  duration: session.asleepDuration,
                  size: 17,
                  weight: FontWeight.w400,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 44px proportional bar of the night's stages — the composition at a
/// glance, in a row that has no space for the full split.
class _StageStrip extends StatelessWidget {
  const _StageStrip({required this.breakdown});

  final SleepStageBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final parts = breakdown.gradedParts;
    if (parts.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: 44,
        height: 4,
        child: Row(
          children: [
            for (final (stage, duration) in parts)
              Expanded(
                flex: duration.inSeconds.clamp(1, 1 << 30),
                child: ColoredBox(color: sleepStageColor(stage)),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The longer run
// ---------------------------------------------------------------------------

/// Four weeks of direction, plus this week against the one before it.
///
/// The trend is a **Theil–Sen** slope (`SleepMetrics.trend`) and it is reported
/// as a direction only. The slope is a real number and a useless sentence:
/// "1.4 minutes more per night" is not something anyone can act on, and
/// quoting it spends precision the estimate does not have.
///
/// When the gate has not passed the section still renders, and says exactly
/// what would open it. That sentence is doing real work — before the sync
/// window was widened, this gate could never open at all, and a section that
/// simply vanished gave no way to notice.
class _LongerRun extends StatelessWidget {
  const _LongerRun({required this.controller});

  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final trend = controller.trend;
    final comparison = controller.comparison;

    final (String text, String? basis) = switch (trend.direction) {
      SleepTrendDirection.insufficientData => (
        strings.sleepTrendNeedMore(
          trend.nightCount,
          SleepGates.minNightsForTrend,
          SleepGates.minDaysSpanForTrend,
        ),
        null,
      ),
      SleepTrendDirection.rising => (
        strings.sleepTrendRising,
        strings.sleepTrendBasis(trend.nightCount, trend.daySpan),
      ),
      SleepTrendDirection.falling => (
        strings.sleepTrendFalling,
        strings.sleepTrendBasis(trend.nightCount, trend.daySpan),
      ),
      SleepTrendDirection.flat => (
        strings.sleepTrendFlat,
        strings.sleepTrendBasis(trend.nightCount, trend.daySpan),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainSectionLabel(strings.sleepTrendTitle),
        const SizedBox(height: AppSpacing.s),
        TrainCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: TrainType.ui(
                  size: 15.5,
                  weight: FontWeight.w500,
                  height: 1.45,
                  color: basis == null ? TrainColors.ink3 : TrainColors.ink,
                ),
              ),
              if (basis != null) ...[
                const SizedBox(height: 6),
                Text(
                  ltrFor(context, basis),
                  style: TrainType.caption(
                    size: 8.5,
                    tracking: 0.14,
                    color: TrainColors.ink4,
                  ),
                ),
              ],
              const _CardRule(),
              _WeekComparison(comparison: comparison),
            ],
          ),
        ),
      ],
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
        // Labelled, because unlabelled it read as a stray figure repeating the
        // "not enough nights" line above it.
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

/// The hairline between bands inside a card, with the vertical rhythm the
/// cards on this screen share.
class _CardRule extends StatelessWidget {
  const _CardRule();

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: AppSpacing.base),
    color: TrainColors.hairline,
  );
}
