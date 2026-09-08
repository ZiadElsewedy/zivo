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
import '../../domain/sleep_session.dart';
import '../controllers/sleep_controller.dart';
import '../sleep_insight_labels.dart';
import '../sleep_labels.dart';
import '../widgets/sleep_about_sheet.dart';
import '../widgets/sleep_axis.dart';
import '../widgets/sleep_bar.dart';
import '../widgets/sleep_duration_text.dart';
import '../widgets/sleep_edit_night_sheet.dart';
import '../widgets/sleep_source_chip.dart';
import '../widgets/sleep_stage_split.dart';
import '../widgets/sleep_targets_sheet.dart';
import '../widgets/sleep_why_sheet.dart';
import 'sleep_week_page.dart';

/// **The Sleep dashboard: one night, answered completely.**
///
/// The screen answers exactly one question — *how did I sleep?* — and answers
/// it about the most recent night, in five bands that each hold one idea:
/// the figure, what it was made of, what was measured around it, how it sat
/// against the target, and what it means. The week lives behind a row at the
/// foot ([SleepWeekPage]).
///
/// ## Why the week is not here any more
///
/// It used to be, as a card of its own: a seven-row raster, three gated
/// figures, and a week-over-week sentence, sitting directly under last night's
/// hero duration. Two numbers in that arrangement were of last night, seven
/// rows were of the week, three figures were averages *over* the week and one
/// sentence compared it to a different week — five different time bases in one
/// scroll, none of them labelled loudly enough to tell apart at a glance. The
/// commonest failure was the worst one: reading a weekly average as last
/// night's sleep.
///
/// A dashboard about today and a history view are different jobs. Splitting
/// them is not a navigation preference; it is what lets every number on this
/// screen share one time base, so a figure here can only ever mean one thing.
///
/// ## The claims this screen is allowed to make
///
/// Unchanged, and still the point (`docs/SLEEP_SYSTEM.md` §13):
///
/// * the hero figure is never shown without its source chip;
/// * a night with no data renders in words, never as `0h 0m`;
/// * **the headline names its own night.** The most recent record is called
///   "last night" only when it *is* last night; older than that it is dated
///   and says so, because a real figure attached to the wrong night is
///   indistinguishable from an app that has stopped updating — and was in
///   fact the way this screen showed a five-day-old number as this morning's;
/// * on iOS an empty read cannot be narrated as "no sleep data", because
///   Apple does not disclose read denial;
/// * a stage split is drawn from measured stages or not at all;
/// * every gated figure shows its `n`, or says it is not there yet.
///
/// ## Why the primary action is docked
///
/// "I'm going to sleep" used to be the last widget in the scroll, and the
/// state it opens rendered in place of it — at the bottom of a page long
/// enough to push the result below the fold, so the one control on the screen
/// looked inert. It is docked now, and the session it opens is announced at
/// the **top** of the scroll ([_SessionCard]).
class SleepPage extends StatefulWidget {
  const SleepPage({super.key});

  @override
  State<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends State<SleepPage>
    with AsyncAction<SleepPage>, WidgetsBindingObserver {
  SleepController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

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

  /// Re-read the health store when the app comes forward with this page open.
  ///
  /// The screen used to read it exactly once, when it was first built. Leave
  /// ZIVO open on Sleep, put the phone down overnight, pick it up in the
  /// morning: the watch has written the night, and the page is still showing
  /// the night before with nothing to say it is stale. `syncIfStale` carries
  /// the throttle, so this costs nothing on an ordinary app switch.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller?.refreshIfStale();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
                    // Everything below the headline describes a night, so it
                    // is present exactly when there is one. Deciding that here
                    // — once, from one condition — is what keeps four
                    // sections from each inventing their own idea of empty.
                    _Band(
                      delay: 60,
                      visible: _hasNight(controller),
                      child: _Stages(controller: controller),
                    ),
                    _Band(
                      delay: 100,
                      visible: _hasNight(controller),
                      child: _Detail(controller: controller),
                    ),
                    _Band(
                      delay: 140,
                      visible: _hasNight(controller),
                      child: _AgainstTarget(controller: controller),
                    ),
                    _Band(
                      delay: 180,
                      visible: renderedInsights(context, controller).isNotEmpty,
                      child: _Insights(controller: controller),
                    ),
                    _Band(
                      delay: 220,
                      visible: true,
                      child: _HistoryRow(controller: controller),
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
    showZivoToast(context, l(context).sleepMarkFailed, kind: ToastKind.error);
  }
}

/// Whether there is a night for the sections below the headline to describe.
bool _hasNight(SleepController controller) =>
    controller.latestNight?.main != null;

/// A section of the scroll **with the gap above it**, or nothing at all.
///
/// Sections here collapse routinely — no night, no stages, no insights yet —
/// and a `SizedBox.shrink` under an unconditional `SizedBox(height: section)`
/// leaves the gap behind. Two absent sections in a row then open a 64px hole
/// in the middle of the page that reads as a layout fault rather than as an
/// absence. Binding the spacer to its content is what keeps the vertical
/// rhythm true whichever sections are present.
class _Band extends StatelessWidget {
  const _Band({
    required this.delay,
    required this.visible,
    required this.child,
  });

  final int delay;
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.section),
      child: RiseIn(
        delay: Duration(milliseconds: delay),
        child: child,
      ),
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
// The headline: one night, named
// ---------------------------------------------------------------------------

class _LastNight extends StatelessWidget {
  const _LastNight({required this.controller});

  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    final night = controller.latestNight;

    // Order matters. A read that failed outranks "nothing to show": the
    // second is a statement about the user's data, and we have not earned it.
    final Widget body;
    if (controller.loadFailed) {
      body = _LoadFailed(controller: controller);
    } else if (!controller.hasLoaded) {
      // "Still loading" and "loaded and empty" must not share a rendering:
      // one is a promise, the other is a fact.
      body = const _LastNightSkeleton();
    } else if (night == null) {
      body = _EmptyState(controller: controller);
    } else {
      body = _LastNightCard(night: night, controller: controller);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainSectionLabel(
          headlineLabel(context, controller),
          // The date the figure belongs to, always — the cheapest possible
          // guard against reading an old night as this morning's.
          trailing: night == null
              ? null
              : formatWeekdayDate(context, night.sleepDay),
        ),
        const SizedBox(height: AppSpacing.s),
        body,
      ],
    );
  }
}

/// "Last night", or "3 nights ago" when that is what it is.
///
/// Exposed rather than private because [SleepWeekPage] shows the same night
/// under the same name, and two screens naming one night differently is how a
/// user concludes the app is confused.
String headlineLabel(BuildContext context, SleepController controller) {
  final age = controller.latestNightAgeDays;
  // 0 is the night we woke from this morning; 1 is a night recorded before
  // today's sleep-day opened. Both are "last night" in ordinary speech.
  if (age == null || age <= 1) return l(context).sleepLastNight;
  return l(context).sleepNightsAgo(age);
}

class _LastNightCard extends StatelessWidget {
  const _LastNightCard({required this.night, required this.controller});

  final SleepNight night;
  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    final session = night.main!;

    return GestureDetector(
      onTap: () => showSleepWhySheet(context, night),
      behavior: HitTestBehavior.opaque,
      child: TrainCard(
        padding: const EdgeInsets.fromLTRB(18, 17, 18, 15),
        // The one tinted card on the page. Five stacked cards of identical
        // weight is the "collection of cards" failure — every section reads
        // as equally important and the eye has nowhere to land. The night is
        // what the screen is *for*, so it gets the hue and the others stay
        // plain; the sections below are its supporting detail and now look
        // like it.
        border: TrainColors.sleepAccent.withValues(alpha: 0.20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x1A7C9CFF), Color(0x087C9CFF)],
        ),
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
                SleepConfidenceBadge(confidence: session.provenance.confidence),
              ],
            ),

            if (controller.isLatestNightStale) ...[
              const SizedBox(height: AppSpacing.m),
              _StaleNotice(),
            ],

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
                    child: Center(
                      child: SleepBar(
                        night: night,
                        height: 18,
                        // Only here. The night's own stages, drawn where they
                        // happened — and a plain method fill when the source
                        // did not grade it.
                        showStages: true,
                      ),
                    ),
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

            _Context(controller: controller, session: session),

            const SizedBox(height: AppSpacing.base),
            Row(
              children: [
                Flexible(
                  child: _QuietAction(
                    label: l(context).sleepWhyTitle,
                    icon: AppIcons.info,
                    onTap: () => showSleepWhySheet(context, night),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Flexible(
                  child: _QuietAction(
                    label: l(context).sleepEditNight,
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

/// Said out loud, under the figure, when the figure is not last night's.
///
/// The alternative was to show the date and trust the reader to do the
/// subtraction. They do not — a large confident number under a small grey date
/// is read as current, which is exactly how "the app isn't updating" starts.
class _StaleNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: TrainColors.glass,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: TrainColors.hairlineStrong),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(AppIcons.warning, size: 14, color: TrainColors.ink3),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(
            l(context).sleepStaleNotice,
            style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

/// One line placing the night against the fortnight before it.
///
/// The **fortnight before it** — the baseline deliberately excludes the night
/// being described (`SleepController.baselineMetrics`). Comparing a night to
/// an average it is itself part of pulls the average toward the night and
/// shrinks every difference, most severely on exactly the weeks with fewest
/// nights, where the reader is least able to notice.
class _Context extends StatelessWidget {
  const _Context({required this.controller, required this.session});

  final SleepController controller;
  final SleepSession session;

  @override
  Widget build(BuildContext context) {
    final metrics = controller.baselineMetrics;
    final mean = metrics.meanDurationMinutes;
    if (mean == null) return const SizedBox.shrink();

    final strings = l(context);
    final average = sleepMinutesText(context, mean);
    final delta = session.asleepDuration.inMinutes - mean;
    final amount = sleepMinutesText(context, delta);

    // The same noise floor the week-over-week comparison uses. A twelve-minute
    // difference against a fortnight's mean is not a finding, and calling it
    // one here while `SleepMetrics.compare` refuses to would put two
    // contradicting sentences on one feature.
    final text = delta.abs() < SleepGates.minMeaningfulDeltaMinutes
        ? strings.sleepContextTypical(average)
        : (delta > 0
              ? strings.sleepContextLonger(amount, average)
              : strings.sleepContextShorter(amount, average));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardRule(),
        Text(
          text,
          style: AppText.rowTitle.copyWith(
            color: TrainColors.ink,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          strings.sleepContextBasis(metrics.nightCount),
          style: TrainType.caption(
            size: 8.5,
            tracking: 0.14,
            color: TrainColors.ink4,
          ),
        ),
      ],
    );
  }
}

/// The shape of the headline while it is still loading.
///
/// A skeleton rather than a gap. The old placeholder was a bare
/// `SizedBox(height: 120)`, which on a screen whose empty state is a whole
/// paragraph rendered as a void between the title and what followed — and,
/// when the read errored and `hasLoaded` never flipped, a permanent one.
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
// Stages
// ---------------------------------------------------------------------------

/// What the night was made of — or a named admission that the source did not
/// say.
///
/// The absent case is a section rather than a silence on purpose. Staging is
/// the thing users most expect a sleep screen to have and most often cannot
/// get (an iPhone with no watch, an Apple Watch before watchOS 9, a Health
/// Connect writer that logs a session without stages). Hiding the section
/// leaves them to conclude ZIVO simply does not do stages; naming the source
/// and saying it did not record them is the true and more useful sentence.
class _Stages extends StatelessWidget {
  const _Stages({required this.controller});

  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.latestNight?.main;
    if (session == null) return const SizedBox.shrink();
    final breakdown = controller.latestNightStages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainSectionLabel(l(context).sleepStagesTitle),
        const SizedBox(height: AppSpacing.s),
        TrainCard(
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 17),
          child: breakdown == null
              ? Text(
                  l(context).sleepStagesUnavailable(
                    sleepProviderName(context, session.provenance),
                  ),
                  style: AppText.body.copyWith(
                    color: TrainColors.ink3,
                    height: 1.45,
                  ),
                )
              : SleepStageSplit(
                  breakdown: breakdown,
                  sessionDuration: session.duration,
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Detail
// ---------------------------------------------------------------------------

/// Time in bed, efficiency, interruptions, naps — the measured surroundings of
/// the figure.
///
/// Every row here can be genuinely unknown, and each says so in its own words
/// rather than as a zero. "Not tracked" against efficiency is the load-bearing
/// one: a source with no in-bed data yields no efficiency, and the tempting
/// default — 100% — is a fabricated number wearing a measured number's
/// clothes.
class _Detail extends StatelessWidget {
  const _Detail({required this.controller});

  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    final night = controller.latestNight;
    final session = night?.main;
    if (night == null || session == null) return const SizedBox.shrink();
    final strings = l(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainSectionLabel(strings.sleepDetailTitle),
        const SizedBox(height: AppSpacing.s),
        TrainCard(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
          child: Column(
            children: [
              _DetailRow(
                label: strings.sleepTimeInBedLabel,
                value: session.timeInBed == null
                    ? null
                    : ltrFor(
                        context,
                        sleepDurationText(context, session.timeInBed!),
                      ),
              ),
              _DetailRow(
                label: strings.sleepEfficiencyLabel,
                value: session.efficiency == null
                    ? null
                    : sleepPercentText(context, session.efficiency!),
              ),
              _DetailRow(
                label: strings.sleepInterruptionCount(
                  session.interruptions.length,
                ),
                // The label already carries the count; the value is how much
                // of the night they took, which is the part a reader cannot
                // work out from a number of bouts.
                value: session.interruptions.isEmpty
                    ? null
                    : ltrFor(
                        context,
                        sleepDurationText(
                          context,
                          session.duration - session.asleepDuration,
                        ),
                      ),
                showUnknown: session.interruptions.isNotEmpty,
              ),
              if (night.naps.isNotEmpty)
                _DetailRow(
                  label: strings.sleepNapCount(night.naps.length),
                  value: ltrFor(
                    context,
                    sleepDurationText(
                      context,
                      night.naps.fold(
                        Duration.zero,
                        (sum, nap) => sum + nap.asleepDuration,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.showUnknown = true,
  });

  final String label;

  /// Null means the source does not provide it — rendered as "Not tracked",
  /// never as a zero.
  final String? value;

  /// When false, a null [value] renders as nothing at all rather than as "Not
  /// tracked" — for a row whose label already states the answer ("No
  /// interruptions").
  final bool showUnknown;

  @override
  Widget build(BuildContext context) {
    final shown = value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppText.body.copyWith(color: TrainColors.ink2),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          if (shown != null)
            Text(shown, style: TrainType.mono(size: 14, color: TrainColors.ink))
          else if (showUnknown)
            Text(
              l(context).sleepEfficiencyUnknown,
              style: AppText.meta.copyWith(color: TrainColors.ink4),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Against target
// ---------------------------------------------------------------------------

/// Actual against target, as a signed sentence — never a score and never a
/// tick. ZIVO knows how long you slept; it does not know whether the night was
/// good.
class _AgainstTarget extends StatelessWidget {
  const _AgainstTarget({required this.controller});

  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    final night = controller.latestNight;
    if (night?.main == null) return const SizedBox.shrink();

    final duration = sleepDurationDeltaText(context, night!);
    final bedtime = sleepBedtimeDeltaText(context, night);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainSectionLabel(l(context).sleepAgainstTargetTitle),
        const SizedBox(height: AppSpacing.s),
        TrainCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: duration == null && bedtime == null
              // No target set. An invitation, not a zero delta against a goal
              // nobody chose.
              ? Text(
                  l(context).sleepNoTargets,
                  style: AppText.body.copyWith(color: TrainColors.ink3),
                )
              : Column(
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
                      if (duration != null)
                        const SizedBox(height: AppSpacing.s),
                      Text(
                        bedtime,
                        style: AppText.meta.copyWith(color: TrainColors.ink3),
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
// Insights
// ---------------------------------------------------------------------------

/// What the recent nights mean — two or three sentences, each with the number
/// of nights it rests on.
///
/// These are the **deterministic** tier (`sleep_insight.dart`): pure arithmetic
/// that is always available and grounded by construction, produced only for
/// figures that passed their gate. The model layer
/// (`functions/ai/sleep_insights.js`) replaces the wording, never the set —
/// and whatever it writes goes through the same numeral gate before it can be
/// shown.
///
/// **Set in Manrope, not the italic serif.** This was ZIVO's speaking voice
/// (`AppText.aside`) and the owner ruled it out here: at 21px italic over a
/// paragraph of near-black it is the least readable text on the screen, and
/// the sentences it carries are the screen's conclusions. The voice stays the
/// serif elsewhere (ADR-009); this section reports rather than speaks.
/// The insight drafts that actually have a sentence, for [controller]'s
/// window.
///
/// Shared by the section and by the decision to show the section at all: an
/// insights heading over an empty card is worse than no heading, and deriving
/// "is it empty" separately from "what goes in it" is how the two drift apart.
List<SleepInsightDraft> renderedInsights(
  BuildContext context,
  SleepController controller,
) {
  final drafts = deterministicInsights(
    sheet: controller.factSheet,
    metrics: controller.weekMetrics,
    comparison: controller.comparison,
    trend: controller.trend,
  );
  return [
    for (final draft in drafts)
      if (sleepInsightText(context, draft) != null) draft,
  ];
}

class _Insights extends StatelessWidget {
  const _Insights({required this.controller});

  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    final rendered = renderedInsights(context, controller);
    if (rendered.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainSectionLabel(l(context).sleepInsightsTitle),
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
// The way through to history
// ---------------------------------------------------------------------------

/// The one door out of the dashboard, and the only place the week is named on
/// this screen.
///
/// It carries the week's own headline figure so the row is worth reading
/// standing still, and so the number the user came looking for is visible
/// before the tap — but the figure is labelled with its window, which is
/// exactly the labelling the old inline week card could not manage next to a
/// nightly hero.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.controller});

  final SleepController controller;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final metrics = controller.weekMetrics;

    return PressableScale(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SleepWeekPage(controller: controller),
          ),
        ),
        child: TrainCard(
          padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
          child: Row(
            children: [
              TrainIconTile(
                icon: AppIcons.sleepTargets,
                accent: TrainColors.sleepGlyph,
                size: 34,
                iconSize: 19,
              ),
              const SizedBox(width: AppSpacing.base),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings.sleepHistoryTitle, style: AppText.rowTitle),
                    const SizedBox(height: 3),
                    Text(
                      // The average when there is one, its gate when there is
                      // not — never a blank second line, and never an average
                      // over too few nights.
                      metrics.meanDurationMinutes == null
                          ? strings.sleepHistorySubtitle
                          : sleepHistoryStatText(
                              context,
                              metrics.meanDurationMinutes!,
                              metrics.nightCount,
                              metrics.windowNights,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.meta.copyWith(color: TrainColors.ink3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: TrainColors.ink3,
              ),
            ],
          ),
        ),
      ),
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
            iconSize: 20,
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
      decoration: BoxDecoration(
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
