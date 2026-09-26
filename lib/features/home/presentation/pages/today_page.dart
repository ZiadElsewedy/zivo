import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../profile/domain/user_profile.dart';
import '../../../readiness/presentation/widgets/readiness_glance.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../diet/domain/diet_plan.dart';
import '../../../diet/domain/diet_summary.dart';
import '../../../diet/domain/diet_state_builder.dart';
import '../../../diet/domain/nutrition/food_log_entry.dart';
import '../../../diet/domain/nutrition_targets.dart';
import '../../../diet/presentation/today_diet.dart';
import '../../../expenses/domain/expense.dart';
import '../../../expenses/presentation/pages/expense_capture_page.dart';
import '../../../workout/domain/live_session.dart';
import '../../../workout/domain/session_estimate.dart';
import '../../../workout/domain/up_next_selection.dart';
import '../../../workout/domain/workout_day.dart';
import '../../../workout/domain/workout_plan.dart';
import '../../../workout/presentation/pages/workout_plan_edit_page.dart';
import '../../../workout/presentation/widgets/add_workout_sheet.dart';
import '../../../../l10n/l10n.dart';
import '../header_builder.dart';
import '../motivation_lines.dart';
import '../../../../core/theme/zivo_palette.dart';
import '../../../../core/motion/springs.dart';
import '../widgets/common.dart';
import '../widgets/diet_glance.dart';
import '../widgets/sleep_glance.dart';
import '../widgets/today_pulse_card.dart';
import '../../../workout/presentation/widgets/up_next_workout_card.dart';
import '../../../shell/presentation/widgets/bottom_chrome.dart';
import '../../../../core/util/date_format.dart';

/// The Today command centre — the adaptive surface that reads like a
/// sentence about the day, built live from the day's real signals.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key, this.onOpenAsk, this.now});

  /// The clock the **insights strip** is judged against — real wall time in
  /// production, injected in tests.
  ///
  /// Deliberately scoped to that one section rather than to the whole page:
  /// it is the only part of Today whose *output* changes with the hour (two
  /// of [buildInsights]'s rules only speak after 16:00 and 19:00), which is
  /// what made this page's widget tests pass or fail depending on the time
  /// of day they were run. Everything else here reads the clock for a date
  /// or an elapsed figure, which no test asserts to the hour.
  final DateTime Function()? now;

  /// Opens the Ask tab — Today can't switch tabs itself (HomeShell owns the
  /// tab index), so this is how the readiness card's "ask about it" reaches
  /// it.
  final VoidCallback? onOpenAsk;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

/// Vertical room the now-playing strip occupies above the tab bar (the strip
/// plus its swipe handle and margins) — see the list padding below.
/// Vertical room for the capture FAB that floats over the end of this list.
/// The FAB is 56 tall and Flutter insets it 16 above the bottom bar.
const double _kCaptureFabAllowance = 56 + 16;

class _TodayPageState extends State<TodayPage> {
  /// Bumped by pull-to-refresh. Keys the sections, so each one remounts:
  /// every stream resubscribes, and everything judged against the clock
  /// (insights, readiness, the greeting) is judged again.
  int _generation = 0;

  /// Pull-to-refresh. Most of Today is live streams that never go stale on
  /// their own; what doesn't update itself is sleep, which is READ from
  /// Health on a throttle — so a pull forces that read (past the throttle),
  /// then rebuilds the sections over the result. It used to open Ask
  /// instead, which a pull on a feed never means anywhere else in iOS.
  Future<void> _refresh() async {
    HapticFeedback.mediumImpact();
    final sleep = AppScope.of(context).sleepService;
    await Future.wait([
      if (sleep != null) sleep.sync().catchError((Object _) {}),
      // A floor, so an instant refresh still reads as one rather than the
      // spinner blinking.
      Future<void>.delayed(const Duration(milliseconds: 600)),
    ]);
    if (mounted) setState(() => _generation++);
  }

  /// The spinner the pull reveals: drawn in as the pull deepens, spinning
  /// once armed — the platform control, in the page's own ink.
  Widget _refreshIndicator(
    BuildContext context,
    RefreshIndicatorMode mode,
    double pulled,
    double trigger,
    double extent,
  ) {
    final progress = (pulled / trigger).clamp(0.0, 1.0);
    final color = TrainColors.inkAt(0.6);
    // The gap opens at the very top of the screen, under the status bar —
    // so the spinner is pinned to the gap's bottom and then drawn one
    // status bar lower, into the list's own (empty) top inset. It rides just
    // above the date, clear of the Dynamic Island, without holding the
    // content a whole extra status bar down while it spins.
    return Align(
      alignment: Alignment.bottomCenter,
      child: Transform.translate(
        offset: Offset(0, MediaQuery.paddingOf(context).top - 16),
        child: switch (mode) {
          RefreshIndicatorMode.inactive => const SizedBox.shrink(),
          RefreshIndicatorMode.drag => Opacity(
            opacity: Curves.easeIn.transform(progress),
            child: CupertinoActivityIndicator.partiallyRevealed(
              progress: progress,
              color: color,
              radius: 12,
            ),
          ),
          RefreshIndicatorMode.armed || RefreshIndicatorMode.refresh =>
            CupertinoActivityIndicator(color: color, radius: 12),
          RefreshIndicatorMode.done => Opacity(
            opacity: progress,
            child: CupertinoActivityIndicator(color: color, radius: 12),
          ),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(gradient: TrainColors.todayTint),
      child: Stack(
        children: [
          // One soft radial glow per screen, and on Today that glow is
          // [TrainColors.todayTint] — the wash this very `DecoratedBox` is
          // painting. A second bloom used to sit over it from the opposite
          // corner, so the screen the handoff describes as having exactly one
          // glow was lit from both the top-left and the top-right at once.
          //
          // The status-bar inset lives INSIDE the scroll view (the list's
          // top padding), not in a fixed band above it: a band outside the
          // viewport shrank the scrollable area on every device and pinned a
          // strip of dead ground to the top of the screen. Inside, the
          // viewport is the full height of the page, the first card still
          // starts 62px down, and the inset scrolls away with the content the
          // way it does everywhere else in iOS.
          Positioned.fill(
            child: CustomScrollView(
              // Pullable even when the day's content is shorter than the
              // screen.
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                // Must be the FIRST sliver — the control reads the pull from
                // the viewport's own overscroll. (Its spinner is drawn down
                // past the status bar; see [_refreshIndicator].)
                CupertinoSliverRefreshControl(
                  onRefresh: _refresh,
                  builder: _refreshIndicator,
                  refreshTriggerPullDistance: 110,
                  refreshIndicatorExtent: 50,
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    // 62px from the top of the safe area to the date caption,
                    // per the handoff's screen padding.
                    media.padding.top + 14,
                    AppSpacing.screen,
                    // The shell runs `extendBody: true`, so the list scrolls
                    // UNDER the whole bottom object — nav island plus the
                    // fused now-playing strip. [BottomChrome] is that
                    // object's live measured height, so this tracks music
                    // appearing and leaving. The FAB floats over this same
                    // corner, so its disc clears too.
                    BottomChrome.of(context) +
                        _kCaptureFabAllowance +
                        AppSpacing.base,
                  ),
                  sliver: SliverList.list(
                    key: ValueKey(_generation),
                    children: [
                      RiseIn(delay: Duration.zero, child: const _Header()),
                      // Primary tier — the day at a glance: train / fuel /
                      // move rings answering "what have I done today?"
                      RiseIn(
                        delay: const Duration(milliseconds: 70),
                        child: TodayPulseSection(now: widget.now),
                      ),
                      // The day's training, full-weight card — the first thing to
                      // act on today, so it leads the sections below the pulse.
                      const RiseIn(
                        delay: Duration(milliseconds: 105),
                        child: _TrainingSection(),
                      ),
                      // The day's call — train hard / go light / rest — fused from
                      // sleep, training load, recovery and weight. Hides itself
                      // when there is nothing to base a call on.
                      RiseIn(
                        delay: const Duration(milliseconds: 140),
                        child: ReadinessSection(
                          onOpenAsk: widget.onOpenAsk,
                          now: widget.now,
                        ),
                      ),
                      // Momentum — "how am I doing?" streak, week bars,
                      // weight trend.
                      RiseIn(
                        delay: const Duration(milliseconds: 210),
                        child: MomentumSection(now: widget.now),
                      ),
                      // Worth knowing — computed right-now nudges.
                      RiseIn(
                        delay: const Duration(milliseconds: 280),
                        child: InsightsSection(now: widget.now),
                      ),
                      // Tertiary tier — quiet glances, muted ink tones (no bright hues).
                      const RiseIn(
                        delay: Duration(milliseconds: 350),
                        child: _DietSection(),
                      ),
                      // Sleep hides itself when there is no night to report,
                      // rather than showing a zero — see SleepGlanceSection.
                      const RiseIn(
                        delay: Duration(milliseconds: 420),
                        child: SleepGlanceSection(),
                      ),
                    ],
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

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatTodayShort(
            now,
            Localizations.localeOf(context).toLanguageTag(),
          ),
          style: TrainType.mono(
            size: 10,
            weight: FontWeight.w500,
            tracking: 0.18,
            color: TrainColors.inkAt(0.42),
          ),
        ),
        const SizedBox(height: 12),
        // The live clock is the header's anchor and this screen's one hero
        // number — a glance answers "what time is it" before anything else
        // on Today does.
        const _LiveTime(),
        const SizedBox(height: 10),
        _GreetingRow(now: now),
        const SizedBox(height: 8),
        const _MotivationLine(),
      ],
    );
  }
}

/// The hourly push under the greeting (see [motivationFor]) — lit like a
/// flame, amber at its base burning into ember, so it reads as the day's
/// heat rather than one more caption. Smaller and lighter than the greeting,
/// and text rather than a button, so it never competes with the ember Start
/// workout below it.
class _MotivationLine extends StatefulWidget {
  const _MotivationLine();

  @override
  State<_MotivationLine> createState() => _MotivationLineState();
}

class _MotivationLineState extends State<_MotivationLine> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  /// One timer to the top of the next hour, re-armed each time — not a
  /// periodic one, which would drift off the hour.
  void _schedule() {
    _timer = Timer(nextMotivationChange(_now).difference(DateTime.now()), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = motivationFor(
      _now,
      Localizations.localeOf(context).languageCode,
    );
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedSwitcher(
      duration: reducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: ShaderMask(
        key: ValueKey(line),
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
          end: rtl ? Alignment.centerLeft : Alignment.centerRight,
          colors: [TrainColors.amber, TrainColors.ember],
        ).createShader(bounds),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              // White under the mask — the gradient supplies the colour.
              child: Icon(AppIcons.streak, size: 17, color: Colors.white),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                line,
                key: const Key('today-motivation'),
                maxLines: 2,
                style:
                    TrainType.ui(
                      size: 16,
                      weight: FontWeight.w800,
                      tracking: -0.01,
                      height: 1.3,
                      color: Colors.white,
                    ).copyWith(
                      // Masked like the glyphs, so this becomes the flame's own
                      // warm glow rather than a grey drop shadow. Dark skin only:
                      // on paper a glow reads as a smudge, not heat.
                      shadows: ZivoTheme.brightness == Brightness.dark
                          ? const [
                              Shadow(color: Color(0x99FFFFFF), blurRadius: 14),
                            ]
                          : null,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A live wall clock (`H:MM` + AM/PM), Today's hero number.
///
/// Ticks on each minute boundary rather than every second — a calm, premium
/// cadence that still stays exactly accurate (the first timer is aligned to
/// the next whole minute, then it repeats every minute). Tabular figures keep
/// the digits from shifting width as the time changes, so the clock never
/// jitters — the whole reason the handoff puts numbers in mono.
class _LiveTime extends StatefulWidget {
  const _LiveTime();

  @override
  State<_LiveTime> createState() => _LiveTimeState();
}

class _LiveTimeState extends State<_LiveTime> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
    _timer = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour;
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final minute = _now.minute.toString().padLeft(2, '0');
    final period = formatDayPeriod(context, _now);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$h12:$minute',
          style: TrainType.mono(
            size: 54,
            weight: FontWeight.w300,
            tracking: -0.045,
            color: TrainColors.ink,
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            period,
            style: TrainType.mono(
              size: 13,
              weight: FontWeight.w500,
              tracking: 0.1,
              color: TrainColors.ink3,
            ),
          ),
        ),
      ],
    );
  }
}

class _GreetingRow extends StatelessWidget {
  const _GreetingRow({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final uid = scope.auth.currentUser?.uid;
    return StreamBuilder<UserProfile?>(
      stream: uid == null ? null : scope.profiles.watchProfile(uid),
      builder: (context, snapshot) {
        return Text(
          greetingFor(now, snapshot.data?.name, l(context)),
          style: TrainType.ui(
            size: 27,
            weight: FontWeight.w800,
            tracking: -0.02,
            height: 1.1,
            color: TrainColors.ink,
          ),
        );
      },
    );
  }
}

/// Always shows the active plan's up-next day, resolved by the SAME
/// `resolveUpNext` (see `up_next_selection.dart`) the Workout tab's own page
/// reads, so the two surfaces can't drift apart. Deliberately does NOT branch
/// on whatever's been logged today (`todaysWorkout`) — that used to show a
/// second, different card once anything was logged, which put Home and the
/// Workout page out of sync (owner-reported, root-caused, fixed). The full
/// history of what was actually done stays reachable via Workout History.
class _TrainingSection extends StatelessWidget {
  const _TrainingSection();

  @override
  Widget build(BuildContext context) {
    return _TrainingUpNext(scope: AppScope.of(context));
  }
}

/// The section's caption row — `NEXT SESSION` on the left, and where that
/// session sits in the split (`WEEK 4 · DAY 2`) on the right. Both are real:
/// the week counts from the split's creation date, the day is its position
/// in the rotation.
class _NextSessionCaption extends StatelessWidget {
  const _NextSessionCaption({this.plan, this.day});

  final WorkoutPlan? plan;
  final WorkoutDay? day;

  @override
  Widget build(BuildContext context) {
    final position = plan == null || day == null
        ? null
        : l(context).todayPlanPosition(
            planWeekNumber(plan!, DateTime.now()),
            planDayNumber(day!),
          );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.section, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TrainCaption(l(context).todayNextSession),
          if (position != null) TrainCaption(position, tracking: 0.08),
        ],
      ),
    );
  }
}

/// The active plan's training card, driven by the live-session repository as
/// the single source of truth for whether a workout is under way. When a
/// session is active for the plan the card mirrors *its* day with a Resume CTA
/// — whichever day it is, and through pause/resume, since a pause keeps the
/// session `active` (see [LiveSession.isPaused]). With nothing running it
/// offers the next-due day with a Start CTA. Finishing a workout advances the
/// plan cursor and clears the active session (see `live_session_page.dart`),
/// so the card falls back to the new next-due day on its own. Falls back to
/// [_EmptySplitCard] when the plan has no days left, and (via
/// [_TrainingEmptyFallback]) to a no-plan card when there's no plan at all.
class _TrainingUpNext extends StatelessWidget {
  const _TrainingUpNext({required this.scope});

  final AppScope scope;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<WorkoutPlan?>(
      stream: scope.workoutPlans.watchActivePlan(),
      initialData: scope.workoutPlans.activePlan,
      builder: (context, planSnapshot) {
        final plan = planSnapshot.data;
        if (plan == null) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_NextSessionCaption(), _TrainingEmptyFallback()],
          );
        }
        // Nested under the plan so the session stream — the source of truth for
        // a running workout — drives the card. Kept inside (not merged with the
        // plan stream) so a session save re-renders the card without waiting on
        // a plan emission.
        return StreamBuilder<LiveSession?>(
          stream: scope.workoutSessions.watchActiveSession(),
          initialData: scope.workoutSessions.activeSession,
          builder: (context, sessionSnapshot) {
            // Shared with the Workout tab's own "up next" card (see
            // `up_next_selection.dart`) so the two surfaces can't drift apart.
            final selection = resolveUpNext(
              plan,
              sessionSnapshot.data,
              // A session left open on Tuesday must not still be offering
              // itself as "resume" on Thursday, in place of the day due.
              now: DateTime.now(),
              maxSessionDuration: AppScope.of(context).maxSessionDuration,
            );
            final day = selection.day;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NextSessionCaption(plan: plan, day: day),
                if (day == null)
                  // A plan whose days were all removed still resolves here —
                  // that's a split to fix, not "nothing logged today".
                  _EmptySplitCard(plan: plan)
                else
                  UpNextWorkoutCard(
                    plan: plan,
                    day: day,
                    resumable: selection.resumable,
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// What Training shows when there's no workout plan but the user already has
/// real data elsewhere (a diet plan or a logged expense) — a proper
/// actionable card, not the bare grey line it replaced ("No training logged
/// yet today.", which also misdescribed the state: nothing about it was
/// about *today*, and the actual gap is that no plan exists yet).
///
/// Reactive: as soon as a diet plan or an expense shows up, this collapses
/// back from [_GetStartedCard] on its own (and disappears entirely once a
/// workout plan exists, since the outer [_TrainingUpNext] stops reaching
/// this branch at all).
class _TrainingEmptyFallback extends StatelessWidget {
  const _TrainingEmptyFallback();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<DietPlan?>(
      stream: scope.diet.watchActivePlan(),
      initialData: scope.diet.activePlan,
      builder: (context, dietSnapshot) {
        if (dietSnapshot.data != null) return const _NoPlanTrainingCard();
        return StreamBuilder<List<Expense>>(
          stream: scope.expenses.watchAll(),
          initialData: scope.expenses.current,
          builder: (context, expenseSnapshot) {
            final expenses = expenseSnapshot.data ?? const <Expense>[];
            if (expenses.isNotEmpty) return const _NoPlanTrainingCard();
            return const _GetStartedCard();
          },
        );
      },
    );
  }
}

/// The Training section's own empty-state card: the same flat glass surface,
/// single-hue icon tile and pill CTA as the rest of Today (and the Workout
/// tab's no-plan state), with both ways forward one tap away.
class _NoPlanTrainingCard extends StatelessWidget {
  const _NoPlanTrainingCard();

  @override
  Widget build(BuildContext context) {
    return RiseIn(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          // The handoff card: a flat glass fill over the screen's own tint
          // with a hairline edge. Depth comes from light, not shadow
          // (identity §5) — this used to be an opaque warm-charcoal plate
          // with a soft drop shadow under it, on a cool screen.
          color: TrainColors.glass,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: TrainColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TrainIconTile(
                  icon: AppIcons.workout,
                  accent: TrainColors.green,
                  size: 44,
                  iconSize: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l(context).todayNoPlanTitle,
                    style: AppText.rowTitle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: TrainColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l(context).todayNoPlanBody,
              style: AppText.body.copyWith(
                color: TrainColors.ink2,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: PillButton(
                label: l(context).todayImportPlan,
                icon: Icons.upload_file_rounded,
                color: TrainColors.green,
                enabled: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  showAddWorkoutSheet(context);
                },
              ),
            ),
            Center(
              child: PressableScale(
                child: TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const WorkoutPlanEditPage(initialPlan: null),
                      ),
                    );
                  },
                  child: Text(
                    l(context).todayBuildManually,
                    style: AppText.meta.copyWith(color: TrainColors.ink2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The active split exists but has no days left (every day was deleted) —
/// previously this collapsed into the generic empty line, which read as
/// "nothing logged today" while the actual fix is editing the split.
class _EmptySplitCard extends StatelessWidget {
  const _EmptySplitCard({required this.plan});

  final WorkoutPlan plan;

  @override
  Widget build(BuildContext context) {
    return RiseIn(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          // The handoff card: a flat glass fill over the screen's own tint
          // with a hairline edge. Depth comes from light, not shadow
          // (identity §5) — this used to be an opaque warm-charcoal plate
          // with a soft drop shadow under it, on a cool screen.
          color: TrainColors.glass,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: TrainColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Green, like the no-plan card directly above this one.
                // These are the same card about the same thing — a training
                // plan you can't start yet — and they were amber and green.
                TrainIconTile(
                  icon: AppIcons.planDoc,
                  accent: TrainColors.green,
                  size: 44,
                  iconSize: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l(context).todayEmptySplitTitle(isolate(plan.name)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.rowTitle.copyWith(
                      fontWeight: FontWeight.w600,
                      color: TrainColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l(context).todayEmptySplitBody,
              style: AppText.body.copyWith(
                color: TrainColors.ink2,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: PillButton(
                label: l(context).todayEditSplit,
                icon: Icons.edit_rounded,
                color: TrainColors.green,
                enabled: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WorkoutPlanEditPage(initialPlan: plan),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Today's first-run card: the two ways into real data, side by side,
/// instead of a bare empty line — two taps to real data, not a wizard.
class _GetStartedCard extends StatelessWidget {
  const _GetStartedCard();

  @override
  Widget build(BuildContext context) {
    return RiseIn(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          // The handoff card: a flat glass fill over the screen's own tint
          // with a hairline edge. Depth comes from light, not shadow
          // (identity §5) — this used to be an opaque warm-charcoal plate
          // with a soft drop shadow under it, on a cool screen.
          color: TrainColors.glass,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: TrainColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l(context).todayGetStarted,
              style: AppText.rowTitle.copyWith(
                fontWeight: FontWeight.w600,
                color: TrainColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l(context).todayGetStartedBody,
              style: AppText.body.copyWith(
                color: TrainColors.ink2,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _GetStartedAction(
                    icon: Icons.upload_file_rounded,
                    label: l(context).todayImportWorkoutPlan,
                    color: TrainColors.green,
                    onTap: () => showAddWorkoutSheet(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _GetStartedAction(
                    icon: Icons.receipt_long_rounded,
                    label: l(context).todayAddExpense,
                    color: TrainColors.amber,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ExpenseCapturePage(),
                        fullscreenDialog: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GetStartedAction extends StatelessWidget {
  const _GetStartedAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // GestureDetector, not InkWell — Today has no Scaffold of its own (it's
    // embedded in HomeShell's), so an InkWell here would depend on that
    // ambient Material ancestor rather than working standalone.
    return PressableScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: TrainColors.raisedStrong,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 8),
              Text(
                label,
                style: AppText.meta.copyWith(
                  color: TrainColors.ink,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DietSection extends StatelessWidget {
  const _DietSection();

  @override
  Widget build(BuildContext context) {
    final diet = AppScope.of(context).diet;
    return StreamBuilder<DietPlan?>(
      stream: diet.watchActivePlan(),
      initialData: diet.activePlan,
      builder: (context, planSnapshot) {
        final plan = planSnapshot.data;
        final now = DateTime.now();
        final day = dayForDate(plan, now);
        // Tertiary tier: silently hides when empty, same rule as Focus above.
        if (day == null) return const SizedBox.shrink();
        return StreamBuilder<NutritionTargets?>(
          stream: diet.watchTargets(),
          initialData: diet.currentTargets,
          builder: (context, targetsSnapshot) {
            final targets = targetsSnapshot.data;
            return StreamBuilder<List<FoodLogEntry>>(
              stream: diet.watchFoodLog(now),
              initialData: const <FoodLogEntry>[],
              builder: (context, logSnapshot) => StreamBuilder<Set<String>>(
                stream: diet.watchConsumed(now),
                initialData: const <String>{},
                builder: (context, consumedSnapshot) {
                  final consumed = consumedSnapshot.data ?? const <String>{};
                  final summary = dietDaySummary(day, consumed);
                  // Measure against the user's own target when they have one,
                  // through the SAME `buildDietState` the Diet screen and the
                  // coach use. Falling back to the plan total is fine;
                  // silently swapping between the two under the same words
                  // would not be.
                  final state = targets == null
                      ? null
                      : buildDietState(
                          dayKey: '',
                          weekday: now.weekday,
                          targets: targets,
                          planName: null,
                          day: day,
                          consumedMealIds: consumed,
                          log: logSnapshot.data ?? const <FoodLogEntry>[],
                        );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeader(l(context).dietTitle),
                      DietGlanceRow(
                        eaten: summary.eaten,
                        total: summary.total,
                        kcalLeft: state?.remainingKcal ?? summary.kcalLeft,
                        kcalEstimated:
                            state?.consumed.estimated ??
                            summary.kcalLeftEstimated,
                        againstTarget: state != null,
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
