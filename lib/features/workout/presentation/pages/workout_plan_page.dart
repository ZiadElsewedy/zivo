import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/back_chip.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/live_session.dart';
import '../../domain/planned_exercise.dart';
import '../../domain/session_status.dart';
import '../../domain/up_next_selection.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_plan_format.dart';
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
/// timers, and actual-set logging arrive with the session engine (P3). History
/// ("what I did") stays one tap away via the AppBar.
///
/// Dark, immersive body — matching the live session screens on the
/// app-wide [TrainColors] theme.
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
        return Scaffold(
          backgroundColor: TrainColors.base,
          appBar: AppBar(
            backgroundColor: TrainColors.base,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            // Pushed from the Hub — the house back chip, not Material's
            // default arrow, so every drill-down reads as one system.
            automaticallyImplyLeading: false,
            leadingWidth: 56,
            leading: const BackChip(),
            title: Text(
              l(context).workoutTitle,
              style: AppText.cardTitle.copyWith(color: TrainColors.ink),
            ),
            actions: [
              PressableScale(
                child: IconButton(
                  tooltip: l(context).workoutSplits,
                  icon: const Icon(
                    Icons.layers_rounded,
                    color: TrainColors.ink2,
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SplitManagementPage(),
                      ),
                    );
                  },
                ),
              ),
              PressableScale(
                child: IconButton(
                  tooltip: l(context).workoutAnalysis,
                  icon: const Icon(
                    Icons.trending_up_rounded,
                    color: TrainColors.ink2,
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WorkoutAnalysisPage(),
                      ),
                    );
                  },
                ),
              ),
              PressableScale(
                child: IconButton(
                  tooltip: l(context).workoutHistory,
                  icon: const Icon(
                    Icons.history_rounded,
                    color: TrainColors.ink2,
                  ),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WorkoutHistoryPage(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          floatingActionButton: loading || snapshot.hasError
              ? null
              : FloatingActionButton(
                  backgroundColor: TrainColors.green,
                  elevation: 2,
                  tooltip: plan == null
                      ? l(context).workoutCreatePlan
                      : l(context).workoutEditPlan,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WorkoutPlanEditPage(initialPlan: plan),
                    ),
                  ),
                  child: Icon(
                    plan == null ? Icons.add_rounded : Icons.edit_rounded,
                    color: Colors.white,
                  ),
                ),
          body: snapshot.hasError
              ? const _PlanErrorState()
              : loading
              ? const _PlanLoadingState()
              : plan == null
              ? const _WorkoutPlanEmptyState()
              : _PlanBody(plan: plan),
        );
      },
    );
  }
}

/// A restrained, low-opacity lift for the plan's dark cards — a plain
/// neutral hairline border does the structural work; this is just enough
/// colored glow to read as "elevated," not a neon halo. Matches the live
/// session screens' `_cardGlow` treatment (Phase 5A) so the two dark
/// surfaces feel like one system.
List<BoxShadow> _cardGlow(Color color) => [
  BoxShadow(
    color: color.withValues(alpha: 0.08),
    blurRadius: 24,
    spreadRadius: -6,
    offset: const Offset(0, 8),
  ),
];

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
        decoration: const BoxDecoration(
          color: TrainColors.glassStrong,
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.all(10),
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(
            TrainColors.ink2,
            BlendMode.srcIn,
          ),
          child: Lottie.asset('assets/loading.json', fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _PlanErrorState extends StatelessWidget {
  const _PlanErrorState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 30,
              color: TrainColors.ink4,
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load this.",
              style: AppText.aside.copyWith(color: TrainColors.ink2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              l(context).errorCheckConnection,
              style: AppText.meta.copyWith(color: TrainColors.ink4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The empty state — no active plan yet. Building one is via the FAB (blank
/// editor) or the AI PDF import, both reachable from elsewhere in the app.
class _WorkoutPlanEmptyState extends StatelessWidget {
  const _WorkoutPlanEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.fitness_center_rounded,
            size: 30,
            color: TrainColors.ink4,
          ),
          const SizedBox(height: 12),
          Text(
            l(context).workoutNoPlanYet,
            style: AppText.aside.copyWith(color: TrainColors.ink2),
          ),
        ],
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
            22,
            8,
            22,
            TrainBottomInset.forScaffold(context, hasFab: true),
          ),
          children: [
            Text(
              plan.name,
              style: AppText.rowTitle.copyWith(color: TrainColors.ink2),
            ),
            const SizedBox(height: 18),
            if (today == null)
              Text(
                l(context).workoutNoDayUpNext,
                style: AppText.aside.copyWith(color: TrainColors.ink2),
              )
            else
              _TodaySection(
                day: today,
                plan: plan,
                resumable: selection.resumable,
              ),
            const SizedBox(height: 30),
            Text(
              l(context).workoutFullCycle,
              style: AppText.meta.copyWith(
                color: TrainColors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l(context).workoutAnyDayNote,
              style: AppText.meta.copyWith(
                color: TrainColors.ink4,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            for (final (i, day) in days.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: StaggeredReveal(
                  index: i,
                  child: _BrowseDayCard(
                    day: day,
                    isNext: day.id == nextInRotation?.id,
                    plan: plan,
                    resumable:
                        sessionSnapshot.data?.dayId == day.id &&
                            sessionSnapshot.data?.status == SessionStatus.active
                        ? sessionSnapshot.data
                        : null,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The prominent "up next" block: an eyebrow, the day title, its meta, and each
/// planned exercise with its sets.
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
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 10),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        decoration: BoxDecoration(
          color: const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: TrainColors.hairline),
          boxShadow: _cardGlow(TrainColors.green),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: TrainColors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l(context).workoutUpNext,
                  style: AppText.meta.copyWith(
                    color: TrainColors.green,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _dayTitle(context, day),
              style: AppText.heroNumber.copyWith(
                fontSize: 30,
                color: TrainColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              workoutDayMeta(day),
              style: AppText.meta.copyWith(color: TrainColors.ink4),
            ),
            const SizedBox(height: 18),
            PillButton(
              label: resumable == null
                  ? l(context).workoutStart
                  : l(context).workoutResume,
              icon: Icons.play_arrow_rounded,
              color: TrainColors.green,
              enabled: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      LiveSessionPage(day: day, plan: plan, resume: resumable),
                ),
              ),
            ),
            const SizedBox(height: 18),
            for (final (i, exercise) in exercises.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: StaggeredReveal(
                  index: i,
                  child: _ExerciseCard(exercise: exercise),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise});

  final PlannedExercise exercise;

  @override
  Widget build(BuildContext context) {
    final sets = [...exercise.sets]..sort((a, b) => a.order.compareTo(b.order));
    final setLines = collapsedSetSummaries(sets);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TrainColors.glassStrong,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.name,
                  style: AppText.rowTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: TrainColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                plannedExerciseMeta(exercise),
                style: AppText.meta.copyWith(color: TrainColors.green),
              ),
            ],
          ),
          if (exercise.notes != null) ...[
            const SizedBox(height: 6),
            Text(
              exercise.notes!,
              style: AppText.body.copyWith(
                fontSize: 13,
                color: TrainColors.ink2,
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Collapsed to one line per distinct set spec — a 3-set exercise
          // with identical sets reads as "3 × 8–10 · rest 1:30", not three
          // repeated lines; only genuinely different sets get their own line.
          for (final line in setLines)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  _SetDot(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      line,
                      style: AppText.meta.copyWith(
                        color: TrainColors.ink2,
                        fontSize: 13,
                      ),
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

class _SetDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      margin: const EdgeInsets.only(top: 2),
      decoration: const BoxDecoration(
        color: TrainColors.green,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// A read-only-browse, tap-to-expand card for one day in the cycle. Collapsed
/// it shows the day title, its exercise count, and a "Next up" marker when
/// it's the day the cursor points at; expanded it lists the day's exercises
/// AND offers Start — the recommendation leads (the cursor's day is marked
/// "Next up" everywhere), but the user is never locked out of choosing a
/// different day when life doesn't follow the rotation.
class _BrowseDayCard extends StatefulWidget {
  const _BrowseDayCard({
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
  State<_BrowseDayCard> createState() => _BrowseDayCardState();
}

class _BrowseDayCardState extends State<_BrowseDayCard> {
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
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _expanded = !_expanded);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x08FFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.isNext
                    ? TrainColors.green.withValues(alpha: 0.28)
                    : TrainColors.hairline,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _dayTitle(context, day),
                        style: AppText.rowTitle.copyWith(
                          fontWeight: FontWeight.w600,
                          color: TrainColors.ink,
                        ),
                      ),
                    ),
                    if (widget.isNext) ...[
                      const _NextUpBadge(),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      workoutDayMeta(day),
                      style: AppText.meta.copyWith(color: TrainColors.ink4),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      child: const Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: TrainColors.ink4,
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: !_expanded
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final exercise in exercises)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          exercise.name,
                                          style: AppText.body.copyWith(
                                            fontSize: 14,
                                            color: TrainColors.ink2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        plannedExerciseMeta(exercise),
                                        style: AppText.meta.copyWith(
                                          color: TrainColors.ink4,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (exercises.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                // The choice affordance — any day can run.
                                // Resuming an in-progress session for THIS
                                // day reads "Resume", mirroring the Today
                                // card's language.
                                PillButton(
                                  label: widget.resumable == null
                                      ? l(context).workoutStartThisDay
                                      : l(context).workoutResume,
                                  icon: Icons.play_arrow_rounded,
                                  color: TrainColors.green,
                                  enabled: true,
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
      ),
    );
  }
}

class _NextUpBadge extends StatelessWidget {
  const _NextUpBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: TrainColors.green.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        l(context).workoutNextUp,
        style: AppText.meta.copyWith(
          color: TrainColors.green,
          fontSize: 11,
          fontWeight: FontWeight.w600,
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
