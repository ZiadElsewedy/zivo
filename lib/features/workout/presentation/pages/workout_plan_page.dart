import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/reactive_state_views.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../data/ziad_workout_plan.dart';
import '../../domain/live_session.dart';
import '../../domain/planned_exercise.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../../domain/workout_plan_format.dart';
import '../widgets/staggered_reveal.dart';
import 'live_session_page.dart';
import 'workout_history_page.dart';
import 'workout_plan_edit_page.dart';

/// The Workout Plan page — the rotating-cycle template ("what I SHOULD do").
/// Shows the day that's up next (the cycle cursor) prominently, then the whole
/// cycle browsable below. Read-only in this phase: guided execution, rest
/// timers, and actual-set logging arrive with the session engine (P3). History
/// ("what I did") stays one tap away via the AppBar. A Pulse surface, sibling
/// hue to Diet.
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
        final loading = plan == null && snapshot.connectionState == ConnectionState.waiting;
        return Scaffold(
          backgroundColor: AppColors.ground,
          appBar: AppBar(
            backgroundColor: AppColors.ground,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            title: Text('Workout', style: AppText.cardTitle),
            actions: [
              IconButton(
                tooltip: 'History',
                icon: const Icon(Icons.history_rounded, color: AppColors.ink2),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WorkoutHistoryPage()),
                ),
              ),
            ],
          ),
          floatingActionButton: loading || snapshot.hasError
              ? null
              : FloatingActionButton(
                  backgroundColor: AppColors.pulseText,
                  elevation: 2,
                  tooltip: plan == null ? 'Create plan' : 'Edit plan',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => WorkoutPlanEditPage(initialPlan: plan)),
                  ),
                  child: Icon(
                    plan == null ? Icons.add_rounded : Icons.edit_rounded,
                    color: Colors.white,
                  ),
                ),
          body: snapshot.hasError
              ? const ErrorStateView()
              : loading
              ? const LoadingStateView()
              : plan == null
              ? const _WorkoutPlanEmptyState()
              : _PlanBody(plan: plan),
        );
      },
    );
  }
}

/// The empty state — no active plan yet. Offers a one-tap import of the owner's
/// ingested split straight into storage (the FAB still opens the blank editor
/// for building one from scratch).
class _WorkoutPlanEmptyState extends StatelessWidget {
  const _WorkoutPlanEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fitness_center_rounded, size: 30, color: AppColors.ink3),
          const SizedBox(height: 12),
          Text('No workout plan yet.', style: AppText.aside),
          const SizedBox(height: 18),
          SizedBox(
            width: 220,
            child: PillButton(
              label: 'Import my split',
              icon: Icons.download_rounded,
              color: AppColors.pulseText,
              enabled: true,
              onTap: () => AppScope.of(context).workoutPlans.savePlan(ziadWorkoutPlan()),
            ),
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
    final days = [...plan.days]..sort((a, b) => a.order.compareTo(b.order));
    final today = plan.nextDay;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 110),
      children: [
        Text(plan.name, style: AppText.rowTitle.copyWith(color: AppColors.ink2)),
        const SizedBox(height: 18),
        if (today == null)
          Text('No day up next.', style: AppText.aside)
        else
          _TodaySection(day: today, plan: plan),
        const SizedBox(height: 30),
        Text(
          'Full cycle',
          style: AppText.meta.copyWith(color: AppColors.pulseText, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        for (final (i, day) in days.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: StaggeredReveal(
              index: i,
              child: _BrowseDayCard(day: day, isNext: day.id == today?.id),
            ),
          ),
      ],
    );
  }
}

/// The prominent "up next" block: an eyebrow, the day title, its meta, and each
/// planned exercise with its sets.
class _TodaySection extends StatelessWidget {
  const _TodaySection({required this.day, required this.plan});

  final WorkoutDay day;
  final WorkoutPlan plan;

  @override
  Widget build(BuildContext context) {
    final exercises = [...day.exercises]..sort((a, b) => a.order.compareTo(b.order));
    final sessions = AppScope.of(context).workoutSessions;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 10), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        decoration: BoxDecoration(
          color: AppColors.pulseWash,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: AppColors.pulse, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  'UP NEXT',
                  style: AppText.meta.copyWith(
                    color: AppColors.pulseText,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(_dayTitle(day), style: AppText.cardTitle.copyWith(fontSize: 26)),
            const SizedBox(height: 4),
            Text(workoutDayMeta(day), style: AppText.meta.copyWith(color: AppColors.ink3)),
            const SizedBox(height: 16),
            StreamBuilder<LiveSession?>(
              stream: sessions.watchActiveSession(),
              initialData: sessions.activeSession,
              builder: (context, snapshot) {
                final active = snapshot.data;
                // Only resume the session this card is actually showing — an
                // active session for a different plan/day (however that could
                // happen) is left alone rather than seeding the wrong exercises.
                final resumable =
                    active != null && active.planId == plan.id && active.dayId == day.id
                    ? active
                    : null;
                return PillButton(
                  label: resumable == null ? 'Start workout' : 'Resume workout',
                  icon: Icons.play_arrow_rounded,
                  color: AppColors.pulseText,
                  enabled: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LiveSessionPage(day: day, plan: plan, resume: resumable),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            for (final (i, exercise) in exercises.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: StaggeredReveal(index: i, child: _ExerciseCard(exercise: exercise)),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.name,
                  style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                plannedExerciseMeta(exercise),
                style: AppText.meta.copyWith(color: AppColors.pulseText),
              ),
            ],
          ),
          if (exercise.notes != null) ...[
            const SizedBox(height: 6),
            Text(
              exercise.notes!,
              style: AppText.body.copyWith(fontSize: 13, color: AppColors.ink2),
            ),
          ],
          const SizedBox(height: 10),
          for (final set in sets)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  _SetDot(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      setSummary(set),
                      style: AppText.meta.copyWith(color: AppColors.ink2, fontSize: 13),
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
      decoration: const BoxDecoration(color: AppColors.pulse, shape: BoxShape.circle),
    );
  }
}

/// A read-only, tap-to-expand card for one day in the cycle. Collapsed it shows
/// the day title, its exercise count, and a "Next up" marker when it's the day
/// the cursor points at; expanded it lists the day's exercises.
class _BrowseDayCard extends StatefulWidget {
  const _BrowseDayCard({required this.day, required this.isNext});

  final WorkoutDay day;
  final bool isNext;

  @override
  State<_BrowseDayCard> createState() => _BrowseDayCardState();
}

class _BrowseDayCardState extends State<_BrowseDayCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final exercises = [...day.exercises]..sort((a, b) => a.order.compareTo(b.order));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _dayTitle(day),
                      style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (widget.isNext) ...[
                    const _NextUpBadge(),
                    const SizedBox(width: 10),
                  ],
                  Text(workoutDayMeta(day), style: AppText.meta.copyWith(color: AppColors.ink3)),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: AppColors.ink3,
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        exercise.name,
                                        style: AppText.body.copyWith(
                                          fontSize: 14,
                                          color: AppColors.ink2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      plannedExerciseMeta(exercise),
                                      style: AppText.meta.copyWith(
                                        color: AppColors.ink3,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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

class _NextUpBadge extends StatelessWidget {
  const _NextUpBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.pulse.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Next up',
        style: AppText.meta.copyWith(
          color: AppColors.pulseText,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// "Day A · Push" — the slot and label composed into one title.
String _dayTitle(WorkoutDay day) => 'Day ${day.slot} · ${day.label}';
