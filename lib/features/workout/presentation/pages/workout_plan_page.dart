import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/reactive_state_views.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../domain/live_session.dart';
import '../../domain/planned_exercise.dart';
import '../../domain/session_status.dart';
import '../../domain/up_next_selection.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../workout_labels.dart';
import '../widgets/staggered_reveal.dart';
import '../../../../core/widgets/train_surfaces.dart';
import 'live_session_page.dart';
import 'split_management_page.dart';
import 'workout_analysis_page.dart';
import 'workout_history_page.dart';
import 'workout_plan_edit_page.dart';
import '../../../../l10n/l10n.dart';

/// The Workout Plan page — the rotating-cycle template ("what I SHOULD do").
/// Shows the day that's up next (the cycle cursor) prominently, then the whole
/// cycle browsable below. Read-only in this phase: guided execution, rest
/// timers, and actual-set logging arrive with the session engine (P3).
///
/// ## Why the chrome changed
///
/// This was the last workout screen on a Material `AppBar`, and it carried
/// **three** trailing icon actions where [TrainPageHeader] carries one. That
/// toolbar was also duplicate navigation: Splits, Analysis and History are all
/// offered by [WorkoutProgressPage], the only page that pushes this one. They
/// keep their place here — as labelled rows at the foot of the scroll, which
/// is the house drill-down pattern and the only version of them that says what
/// the icons meant — and the header's single action is the plan editor the
/// floating action button used to hold.
class WorkoutPlanPage extends StatelessWidget {
  const WorkoutPlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final plans = AppScope.of(context).workoutPlans;
    return StreamBuilder<WorkoutPlan?>(
      stream: plans.watchActivePlan(),
      initialData: plans.activePlan,
      builder: (context, snapshot) {
        final plan = snapshot.data;
        final loading =
            plan == null && snapshot.connectionState == ConnectionState.waiting;
        return TrainScreen(
          tint: TrainColors.hubTint,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  12,
                  AppSpacing.screen,
                  0,
                ),
                child: TrainPageHeader(
                  title: l(context).workoutTitle,
                  action: loading || snapshot.hasError
                      ? null
                      : TrainHeaderAction(
                          icon: plan == null ? AppIcons.add : AppIcons.edit,
                          semanticLabel: plan == null
                              ? l(context).workoutCreatePlan
                              : l(context).workoutEditPlan,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  WorkoutPlanEditPage(initialPlan: plan),
                            ),
                          ),
                        ),
                ),
              ),
              Expanded(
                child: snapshot.hasError
                    ? const _PlanErrorState()
                    : loading
                    ? const _PlanLoadingState()
                    : plan == null
                    ? const _WorkoutPlanEmptyState()
                    : _PlanBody(plan: plan),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The Lottie loading mark renders in a dark ink tone of its own — nearly
/// invisible directly on [TrainColors.base] — so it's recolored to the
/// dark palette's muted ink via a color filter, then given a touch of a
/// lighter (but still dark) backdrop for extra contrast.
class _PlanLoadingState extends StatelessWidget {
  const _PlanLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          color: TrainColors.glassStrong,
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.all(10),
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(
            TrainColors.ink2,
            BlendMode.srcIn,
          ),
          child: Lottie.asset('assets/loading.json', fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// The plan page's read failed.
///
/// This used to be a hand-written copy of [ErrorStateView] — same icon, same
/// two lines, same layout, two ink steps darker — written when the shared one
/// was still dressed for the deleted light theme. It isn't any more, so the
/// copy is gone and a failed read reads the same here as everywhere else.
class _PlanErrorState extends StatelessWidget {
  const _PlanErrorState();

  @override
  Widget build(BuildContext context) => const ErrorStateView();
}

/// The empty state — no active plan yet.
///
/// It used to be an icon and one italic line, with the only way forward a
/// bare `+` floating in the corner: an empty screen that named the problem and
/// pointed at nothing. An empty screen is an invitation to act, so the action
/// is on it.
class _WorkoutPlanEmptyState extends StatelessWidget {
  const _WorkoutPlanEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.l * 2,
          0,
          AppSpacing.l * 2,
          AppSpacing.l * 2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TrainIconTile(
              icon: AppIcons.planDoc,
              accent: TrainColors.green,
              size: 46,
              iconSize: 26,
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              l(context).workoutNoPlanYet,
              textAlign: TextAlign.center,
              style: AppText.aside(context).copyWith(color: TrainColors.ink2),
            ),
            const SizedBox(height: AppSpacing.l),
            TrainPrimaryButton(
              label: l(context).workoutCreatePlan,
              icon: const Icon(
                AppIcons.add,
                size: 18,
                color: Color(0xFF04140D),
              ),
              color: TrainColors.green,
              labelColor: const Color(0xFF04140D),
              height: 54,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const WorkoutPlanEditPage(initialPlan: null),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.plan});

  final WorkoutPlan plan;

  @override
  Widget build(BuildContext context) {
    final sessions = AppScope.of(context).workoutSessions;
    final days = [...plan.days]..sort((a, b) => a.order.compareTo(b.order));
    final nextInRotation = plan.nextDay;
    return StreamBuilder<LiveSession?>(
      stream: sessions.watchActiveSession(),
      initialData: sessions.activeSession,
      builder: (context, sessionSnapshot) {
        // Shared with the Home page's "up next" card (see
        // `up_next_selection.dart`) so the two surfaces can't drift apart —
        // a session running on a different day than the rotation's `nextDay`
        // (e.g. the plan changed mid-session) shows its own day here too.
        final selection = resolveUpNext(plan, sessionSnapshot.data);
        final today = selection.day;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screen,
            14,
            AppSpacing.screen,
            TrainBottomInset.of(context),
          ),
          children: [
            // The plan's own name — a mono caption, because it qualifies the
            // title above it rather than competing with it. It used to be a
            // 16.5px Manrope line directly under a 24px one, which read as a
            // second, dimmer heading.
            Text(
              isolate(plan.name).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TrainType.caption(
                size: 10,
                tracking: 0.18,
                color: TrainColors.ink3,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            if (today == null)
              Text(
                l(context).workoutNoDayUpNext,
                style: AppText.aside(context).copyWith(color: TrainColors.ink2),
              )
            else
              _TodaySection(
                day: today,
                plan: plan,
                resumable: selection.resumable,
              ),
            const SizedBox(height: AppSpacing.section),
            TrainSectionLabel(
              l(context).workoutFullCycle,
              trailing: ltrFor(context, '${days.length}'),
            ),
            const SizedBox(height: 6),
            Text(
              l(context).workoutAnyDayNote,
              style: AppText.meta.copyWith(
                color: TrainColors.ink4,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            // One card, one row per day — not one card per day. Five stacked
            // bordered boxes said "five separate things"; the cycle is a
            // single list, and it reads as one now.
            _CycleCard(
              children: [
                for (final (i, day) in days.indexed)
                  StaggeredReveal(
                    index: i,
                    child: _BrowseDayRow(
                      day: day,
                      isNext: day.id == nextInRotation?.id,
                      plan: plan,
                      resumable:
                          sessionSnapshot.data?.dayId == day.id &&
                              sessionSnapshot.data?.status ==
                                  SessionStatus.active
                          ? sessionSnapshot.data
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.section),
            // Splits, Analysis and History used to be three bare icons in an
            // app bar — a toolbar the design system has no room for (the page
            // header carries exactly one action). They are labelled rows now,
            // which is both the house drill-down pattern and the only version
            // of this that says what the icons meant.
            TrainSectionLabel(l(context).workoutMoreSection),
            const SizedBox(height: AppSpacing.m),
            TrainListCard(
              rows: [
                TrainListRow(
                  icon: AppIcons.splits,
                  accent: TrainColors.green,
                  label: l(context).workoutSplits,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SplitManagementPage(),
                    ),
                  ),
                ),
                TrainListRow(
                  icon: AppIcons.analysis,
                  accent: TrainColors.green,
                  label: l(context).workoutAnalysis,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WorkoutAnalysisPage(),
                    ),
                  ),
                ),
                TrainListRow(
                  icon: AppIcons.history,
                  accent: TrainColors.green,
                  label: l(context).workoutHistory,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WorkoutHistoryPage(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The "up next" block — the one card on this page that earns being a card:
/// the eyebrow, the day, what it holds, and the single action that starts it.
///
/// It used to be a card **containing** one bordered, rounded, tinted box per
/// exercise — cards inside a card, each repeating the same frame around
/// different words. The exercises are rows now, separated by the hairline the
/// rest of the app separates rows with, and the card keeps its border for
/// itself.
class _TodaySection extends StatelessWidget {
  const _TodaySection({
    required this.day,
    required this.plan,
    required this.resumable,
  });

  final WorkoutDay day;
  final WorkoutPlan plan;

  /// A same plan/day active session to resume into, or null to start fresh.
  final LiveSession? resumable;

  @override
  Widget build(BuildContext context) {
    final exercises = [...day.exercises]
      ..sort((a, b) => a.order.compareTo(b.order));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 10),
          child: child,
        ),
      ),
      child: TrainCard(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: TrainColors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  l(context).workoutUpNext.toUpperCase(),
                  style: TrainType.caption(
                    size: 9.5,
                    tracking: 0.2,
                    weight: FontWeight.w600,
                    color: TrainColors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            // Manrope, not `AppText.heroNumber` — a day's name is prose, and
            // the mono face is for numbers (ADR-009).
            Text(
              isolate(_dayTitle(context, day)),
              style: TrainType.ui(
                size: 26,
                weight: FontWeight.w800,
                tracking: -0.025,
                color: TrainColors.ink,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              ltrFor(context, workoutDayMetaText(context, day)),
              style: TrainType.mono(
                size: 11.5,
                tracking: 0.04,
                color: TrainColors.ink4,
              ),
            ),
            const SizedBox(height: 16),
            TrainPrimaryButton(
              label: resumable == null
                  ? l(context).workoutStart
                  : l(context).workoutResume,
              icon: const Icon(
                Icons.play_arrow_rounded,
                size: 20,
                color: Color(0xFF04140D),
              ),
              color: TrainColors.green,
              labelColor: const Color(0xFF04140D),
              height: 54,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      LiveSessionPage(day: day, plan: plan, resume: resumable),
                ),
              ),
            ),
            if (exercises.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final (i, exercise) in exercises.indexed)
                StaggeredReveal(
                  index: i,
                  child: _ExerciseRow(exercise: exercise, first: i == 0),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One planned exercise inside the up-next card: name, its set spec on the
/// right, then one line per distinct set below.
class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise, required this.first});

  final PlannedExercise exercise;

  /// The first row carries no rule above it — the button already separates it
  /// from the card's head.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final sets = [...exercise.sets]..sort((a, b) => a.order.compareTo(b.order));
    final setLines = collapsedSetSummaryTexts(context, sets);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!first)
          Divider(height: 1, thickness: 1, color: TrainColors.hairline),
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      isolate(exercise.name),
                      style: TrainType.ui(
                        size: 15,
                        weight: FontWeight.w600,
                        color: TrainColors.inkPlain,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    ltrFor(context, plannedExerciseMetaText(context, exercise)),
                    style: TrainType.mono(
                      size: 11.5,
                      tracking: 0.03,
                      color: TrainColors.green,
                    ),
                  ),
                ],
              ),
              if (exercise.notes != null) ...[
                const SizedBox(height: 5),
                Text(
                  isolate(exercise.notes!),
                  style: AppText.body.copyWith(
                    fontSize: 13,
                    color: TrainColors.ink3,
                  ),
                ),
              ],
              // Collapsed to one line per distinct set spec — a 3-set
              // exercise with identical sets reads as "3 × 8–10 · rest 1:30",
              // not three repeated lines; only genuinely different sets get
              // their own line.
              for (final line in setLines)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SetDot(),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          ltrFor(context, line),
                          style: TrainType.mono(
                            size: 11.5,
                            tracking: 0.02,
                            color: TrainColors.ink3,
                            height: 1.35,
                          ),
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
}

class _SetDot extends StatelessWidget {
  const _SetDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 4,
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: TrainColors.green.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// The cycle: one hairline card holding every day as a row.
class _CycleCard extends StatelessWidget {
  const _CycleCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: TrainColors.hairline,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A read-only-browse, tap-to-expand row for one day in the cycle. Collapsed
/// it shows the day title, its exercise count, and a "next" marker when it's
/// the day the cursor points at; expanded it lists the day's exercises AND
/// offers Start — the recommendation leads (the cursor's day is marked
/// everywhere), but the user is never locked out of choosing a different day
/// when life doesn't follow the rotation.
class _BrowseDayRow extends StatefulWidget {
  const _BrowseDayRow({
    required this.day,
    required this.isNext,
    required this.plan,
    required this.resumable,
  });

  final WorkoutDay day;
  final bool isNext;
  final WorkoutPlan plan;

  /// A same-day active session to resume into, or null to start fresh.
  final LiveSession? resumable;

  @override
  State<_BrowseDayRow> createState() => _BrowseDayRowState();
}

class _BrowseDayRowState extends State<_BrowseDayRow> {
  bool _expanded = false;

  void _start() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveSessionPage(
          day: widget.day,
          plan: widget.plan,
          resume: widget.resumable,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final exercises = [...day.exercises]
      ..sort((a, b) => a.order.compareTo(b.order));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _expanded = !_expanded);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(17, 14, 13, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      isolate(_dayTitle(context, day)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TrainType.ui(
                        size: 15,
                        weight: FontWeight.w600,
                        color: widget.isNext
                            ? TrainColors.ink
                            : TrainColors.inkPlain,
                        height: 1.1,
                      ),
                    ),
                  ),
                  // The cursor's day is marked by the house caption, not by a
                  // filled chip. A tinted, rounded badge on every list is the
                  // most generic thing a dark UI can do, and this list only
                  // ever has one thing to say — which day is next.
                  if (widget.isNext) ...[
                    const SizedBox(width: 9),
                    Text(
                      l(context).workoutNextUp.toUpperCase(),
                      style: TrainType.caption(
                        size: 8.5,
                        tracking: 0.18,
                        weight: FontWeight.w600,
                        color: TrainColors.green,
                      ),
                    ),
                  ],
                  const Spacer(),
                  const SizedBox(width: 10),
                  Text(
                    ltrFor(context, workoutDayMetaText(context, day)),
                    style: TrainType.mono(
                      size: 11,
                      tracking: 0.04,
                      color: TrainColors.ink4,
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: reducedMotion(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: Color(0x4DF4F4F0),
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: reducedMotion(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !_expanded
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final exercise in exercises)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        isolate(exercise.name),
                                        style: TrainType.ui(
                                          size: 13.5,
                                          weight: FontWeight.w500,
                                          color: TrainColors.ink2,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      ltrFor(
                                        context,
                                        plannedExerciseMetaText(
                                          context,
                                          exercise,
                                        ),
                                      ),
                                      style: TrainType.mono(
                                        size: 11,
                                        tracking: 0.03,
                                        color: TrainColors.ink4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (exercises.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              // The choice affordance — any day can run.
                              // Resuming an in-progress session for THIS day
                              // reads "Resume", mirroring the up-next card's
                              // language.
                              _StartDayButton(
                                label: widget.resumable == null
                                    ? l(context).workoutStartThisDay
                                    : l(context).workoutResume,
                                onTap: _start,
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The secondary "start this day instead" control. A ghost pill, because the
/// screen's one green filled action belongs to the day the rotation actually
/// recommends — two identical green pills on one screen said the two choices
/// were equally the plan, which is the opposite of what the cycle means.
class _StartDayButton extends StatelessWidget {
  const _StartDayButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: PressableScale(
        child: Material(
          color: TrainColors.greenWash,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 11,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 16,
                    color: TrainColors.green,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TrainType.ui(
                      size: 13.5,
                      weight: FontWeight.w700,
                      color: TrainColors.green,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Day A · Push" — the slot and label composed into one title. Takes a
/// context because the separator and word order are the translator's, not
/// this function's.
String _dayTitle(BuildContext context, WorkoutDay day) =>
    l(context).workoutDayLabel(day.slot, day.label);
