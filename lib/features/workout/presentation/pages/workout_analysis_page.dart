import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/rise_in.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../domain/body_weight_entry.dart';
import '../../domain/day_progress_analysis.dart';
import '../../domain/live_session.dart';
import '../../domain/progress_comparison.dart';
import '../../domain/session_status.dart';
import '../../domain/training_dashboard_stats.dart';
import '../../domain/weight_trend.dart';
import '../../domain/workout_day.dart';
import '../../domain/workout_plan.dart';
import '../widgets/staggered_reveal.dart';
import '../widgets/trend_chart.dart';
import '../widgets/verdict_style.dart';

/// The progressive-overload Analysis page (WORKOUT_SYSTEM.md §3.3, Phase 2).
///
/// Reads as one continuous "how am I progressing" picture with a clear
/// three-act structure, each act carrying its own visual identity instead of
/// a pile of same-weight boxes:
///
/// 1. **Verdict** — wrapping day chips pick the day, a hero headline states
///    that day's verdict in plain language over a soft aura of the verdict's
///    own color, and a [_BasisNote] spells out what the comparison actually
///    is (this day's last session vs the one before).
/// 2. **The big picture** — day-INDEPENDENT signals, each with its own hue so
///    they scan as different instruments: consistency stats (sessions pulse,
///    streak ember, length iris), a last-7-days training rhythm strip, and a
///    solar bodyweight snapshot.
/// 3. **The day's exercises** — every exercise as a row in one sectioned
///    list, its metric deltas color-coded by direction and its trend drawn
///    as a sparkline in the verdict's color.
///
/// Nothing scrolls horizontally. Everything reads from real data —
/// [analyzeDayProgress], [computeTrainingDashboardStats], and
/// [computeWeightTrend] — nothing is a placeholder.
class WorkoutAnalysisPage extends StatefulWidget {
  const WorkoutAnalysisPage({super.key});

  @override
  State<WorkoutAnalysisPage> createState() => _WorkoutAnalysisPageState();
}

class _WorkoutAnalysisPageState extends State<WorkoutAnalysisPage> {
  String? _selectedDayId;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return TrainScreen(
      tint: TrainColors.hubTint,
      child: StreamBuilder<WorkoutPlan?>(
        stream: scope.workoutPlans.watchActivePlan(),
        initialData: scope.workoutPlans.activePlan,
        builder: (context, planSnap) {
          if (planSnap.hasError) return const _AnalysisErrorState();
          final plan = planSnap.data;
          final loading =
              plan == null &&
              planSnap.connectionState == ConnectionState.waiting;
          if (loading) return const _AnalysisLoadingState();
          if (plan == null || plan.days.isEmpty) {
            return const _NoPlanState();
          }

          final days = [...plan.days]
            ..sort((a, b) => a.order.compareTo(b.order));
          final selected = days.firstWhere(
            (d) => d.id == _selectedDayId,
            orElse: () => plan.nextDay ?? days.first,
          );

          return StreamBuilder<List<LiveSession>>(
            stream: scope.workoutSessions.watchAll(),
            initialData: scope.workoutSessions.current,
            builder: (context, sessionsSnap) {
              if (sessionsSnap.hasError) {
                return const _AnalysisErrorState();
              }
              final sessions = sessionsSnap.data ?? const <LiveSession>[];
              final analysis = analyzeDayProgress(
                day: selected,
                planId: plan.id,
                allSessions: sessions,
              );
              final now = DateTime.now();
              final stats = computeTrainingDashboardStats(
                sessions: sessions,
                now: now,
              );

              final bodyWeight = scope.bodyWeight;
              return StreamBuilder<List<BodyWeightEntry>>(
                stream: bodyWeight?.watchAll() ?? const Stream.empty(),
                initialData: bodyWeight?.current ?? const <BodyWeightEntry>[],
                builder: (context, weightSnap) {
                  final weightTrend = computeWeightTrend(
                    entries: weightSnap.data ?? const <BodyWeightEntry>[],
                    now: now,
                  );
                  // One single scroll, no horizontal scrolling
                  // anywhere: the day chips wrap onto as many lines
                  // as they need.
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 48),
                    children: [
                      RiseIn(child: const TrainPageHeader(title: 'Analysis')),
                      const SizedBox(height: 24),
                      RiseIn(
                        delay: const Duration(milliseconds: 40),
                        child: _DayChips(
                          days: days,
                          selectedId: selected.id,
                          onSelect: (id) => setState(() => _selectedDayId = id),
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Keyed by day so switching days replays the
                      // entrance — the section change should read as
                      // a transition, not a silent text swap.
                      RiseIn(
                        delay: const Duration(milliseconds: 80),
                        child: _ProgressHero(
                          key: ValueKey('hero-${selected.id}'),
                          analysis: analysis,
                        ),
                      ),
                      const SizedBox(height: 16),
                      RiseIn(
                        delay: const Duration(milliseconds: 100),
                        child: _BasisNote(dayLabel: selected.label),
                      ),
                      const SizedBox(height: 36),
                      const _SectionLabel('Consistency'),
                      const SizedBox(height: 5),
                      // Called out because, unlike everything above,
                      // these are day-independent — they span every
                      // session.
                      Text(
                        'Across all your training, not just ${selected.label}.',
                        style: AppText.meta.copyWith(
                          color: TrainColors.ink4,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      RiseIn(
                        delay: const Duration(milliseconds: 120),
                        child: _ConsistencyRow(stats: stats),
                      ),
                      const SizedBox(height: 12),
                      RiseIn(
                        delay: const Duration(milliseconds: 140),
                        child: _WeekRhythmStrip(sessions: sessions, now: now),
                      ),
                      if (weightTrend.latest != null) ...[
                        const SizedBox(height: 12),
                        RiseIn(
                          delay: const Duration(milliseconds: 160),
                          child: _WeightSnapshotRow(trend: weightTrend),
                        ),
                      ],
                      const SizedBox(height: 40),
                      _SectionLabel('${selected.label} exercises'),
                      const SizedBox(height: 12),
                      if (analysis.sessionCount == 0)
                        _DayEmptyState(dayLabel: selected.label)
                      else
                        _ExerciseListCard(
                          key: ValueKey('exercises-${selected.id}'),
                          exercises: analysis.exercises,
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: AppText.sectionLabel.copyWith(
      color: TrainColors.ink4,
      letterSpacing: 0.8,
    ),
  );
}

/// The day selector as a [Wrap] of chips — deliberately NOT a horizontal
/// scroller (owner-reported: the sideways scroll was disliked, and it hid days
/// off-screen edge). Wrapping shows every day at once and stays clean from 3
/// to 6+ days, at the cost of a second line on long labels — the right trade
/// when the whole page is about the day you pick. Labels are just the slot +
/// label with no "Day " prefix, so the chips stay narrow.
class _DayChips extends StatelessWidget {
  const _DayChips({
    required this.days,
    required this.selectedId,
    required this.onSelect,
  });

  final List<WorkoutDay> days;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final day in days)
          _DayChip(
            label: '${day.slot} · ${day.label}',
            active: day.id == selectedId,
            onTap: () => onSelect(day.id),
          ),
      ],
    );
  }
}

class _DayChip extends StatefulWidget {
  const _DayChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_DayChip> createState() => _DayChipState();
}

class _DayChipState extends State<_DayChip>
    with SingleTickerProviderStateMixin {
  /// Rest value is always 1.0 — becoming active doesn't leave the chip
  /// permanently bigger, it just "twangs" the spring with a velocity kick
  /// (no target displacement), so the underdamped [AppSprings.bounce] briefly
  /// overshoots past 1.0 and eases back, reading as a tap-earned pop.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant _DayChip old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !reducedMotion(context)) {
      _pop.springTo(1, spring: AppSprings.bounce, velocity: 6);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.active) HapticFeedback.selectionClick();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pop,
      builder: (context, child) =>
          Transform.scale(scale: _pop.value, child: child),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: widget.active
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2BD99B), TrainColors.green],
                )
              : null,
          color: widget.active ? null : const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: widget.active ? Colors.transparent : TrainColors.hairline,
          ),
          boxShadow: widget.active
              ? [
                  BoxShadow(
                    color: TrainColors.green.withValues(alpha: 0.35),
                    blurRadius: 18,
                    spreadRadius: -4,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          // Transparent — the fill above already carries the animated
          // color; this only exists so InkWell's splash has a Material
          // ancestor, and it paints on top of that fill, not under it.
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: InkWell(
            onTap: _handleTap,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              child: Text(
                widget.label,
                style: AppText.meta.copyWith(
                  color: widget.active ? Colors.white : TrainColors.ink2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// States, in plain words, exactly what the numbers above compare — the
/// owner couldn't tell whether this page was per-day or per-week, so it says
/// so outright instead of leaving it to a small grey footnote. The basis is
/// real: [analyzeDayProgress] compares an exercise's two most recent
/// COMPLETED appearances on this day, index-aligning sets.
class _BasisNote extends StatelessWidget {
  const _BasisNote({required this.dayLabel});

  final String dayLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Was TrainColors.violetWash — a *warm* violet wash behind a cool
              // violet glyph, two violets inside one 28px tile.
              color: TrainColors.violetWash,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              AppIcons.info,
              size: 15,
              color: TrainColors.violetGlyph,
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppText.body.copyWith(
                  color: TrainColors.ink2,
                  fontSize: 13.5,
                  height: 1.45,
                ),
                children: [
                  const TextSpan(text: 'Your '),
                  TextSpan(
                    text: 'last $dayLabel',
                    style: TextStyle(
                      color: TrainColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(text: ' vs the '),
                  TextSpan(
                    text: 'one before it',
                    style: TextStyle(
                      color: TrainColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(
                    text:
                        ' — exercise by exercise, comparing reps, top-set weight, '
                        'and volume (reps × weight). Not weekly, and not all workouts mixed together.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The visual anchor of the page — states the selected day's verdict in
/// plain language first (a big display headline, matching the Today page's
/// greeting/aside hierarchy), backed by the exact improved/matched/regressed
/// counts underneath. A soft aura of the verdict's own color pools behind
/// the headline, so the verdict reads as the page's mood at a glance.
/// Everything else on the page supports this one line.
class _ProgressHero extends StatelessWidget {
  const _ProgressHero({required this.analysis, super.key});

  final DayProgressAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final overall = analysis.overallVerdict;
    final (headline, color) = switch (overall) {
      null => (
        analysis.sessionCount == 0 ? "Let's get started" : 'Almost there',
        TrainColors.ink2,
      ),
      ProgressVerdict.progressing => ('Progressing', TrainColors.green),
      ProgressVerdict.matched => ('Holding steady', TrainColors.ink2),
      ProgressVerdict.down => ('Slipping', TrainColors.ember),
    };
    final detail = overall == null
        ? (analysis.sessionCount == 0
              ? 'Log ${analysis.day.label} to start tracking progress.'
              : "Log ${analysis.day.label} once more to see how you're trending.")
        : '${analysis.improvedCount} improved · ${analysis.matchedCount} matched · '
              '${analysis.regressedCount} regressed';

    // Keyed by day + verdict (not just day) so a same-day re-analysis whose
    // verdict actually changed (e.g. a new session lands mid-view) still
    // reads as a change, not a silent text swap — and the label's verdict
    // color, switched in as part of the same subtree, rides along with it
    // instead of snapping ahead of the text.
    return AnimatedSwitcher(
      duration: reducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        // Transform.translate (pixels), not SlideTransition (fractional of
        // the child's own size) — a fixed ~6px reads the same regardless of
        // how tall the headline/detail text wraps to.
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, (1 - animation.value) * 6),
            child: child,
          ),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey('${analysis.day.id}_$overall'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        decoration: BoxDecoration(
          color: const Color(0x08FFFFFF),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.10),
              color.withValues(alpha: 0.02),
            ],
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
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: 0.30),
                        color.withValues(alpha: 0.10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    overall == null
                        ? AppIcons.analysis
                        : switch (overall) {
                            ProgressVerdict.progressing => AppIcons.trendUp,
                            ProgressVerdict.matched => AppIcons.minus,
                            ProgressVerdict.down => AppIcons.trendDown,
                          },
                    size: 16,
                    color: color == TrainColors.ink2 ? TrainColors.ink2 : color,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  analysis.day.label.toUpperCase(),
                  style: AppText.sectionLabel.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              headline,
              style: AppText.cardTitle.copyWith(
                fontSize: 32,
                color: TrainColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              detail,
              style: AppText.aside.copyWith(
                fontSize: 17,
                color: TrainColors.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The day-independent training picture — sessions this week, the current
/// day streak, and average session length — each stat carrying its own
/// identity hue (sessions pulse, streak ember, length iris) so the row scans
/// as three different instruments rather than three identical numbers.
class _ConsistencyRow extends StatelessWidget {
  const _ConsistencyRow({required this.stats});

  final TrainingDashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ConsistencyStat(
              icon: AppIcons.sessions,
              accent: TrainColors.green,
              value: '${stats.sessionsThisWeek}',
              label: 'This week',
            ),
          ),
          const _ConsistencyDivider(),
          Expanded(
            child: _ConsistencyStat(
              icon: AppIcons.streak,
              accent: TrainColors.green,
              value: '${stats.currentStreakDays}',
              label: 'Day streak',
            ),
          ),
          const _ConsistencyDivider(),
          Expanded(
            child: _ConsistencyStat(
              icon: AppIcons.timer,
              accent: TrainColors.green,
              value: stats.averageSessionDuration == null
                  ? '—'
                  : _formatDurationShort(stats.averageSessionDuration!),
              label: 'Avg length',
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsistencyDivider extends StatelessWidget {
  const _ConsistencyDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 38,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: TrainColors.hairline,
  );
}

class _ConsistencyStat extends StatelessWidget {
  const _ConsistencyStat({
    required this.icon,
    required this.accent,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color accent;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.28),
                accent.withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: accent),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppText.rowTitle.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: TrainColors.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppText.meta.copyWith(color: TrainColors.ink4, fontSize: 11),
        ),
      ],
    );
  }
}

/// The last seven days as one quiet rhythm strip — a bar per day, filled
/// with the training hue when a session landed (taller the more sets were
/// completed), a hairline stub when not. The weekday letters run beneath;
/// today's letter carries the ember accent. Purely visual: no numbers, so
/// it adds shape without adding noise.
class _WeekRhythmStrip extends StatelessWidget {
  const _WeekRhythmStrip({required this.sessions, required this.now});

  final List<LiveSession> sessions;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    final counts = List<int>.filled(7, 0);
    for (final s in sessions) {
      if (s.status != SessionStatus.completed) continue;
      final day = DateTime(
        s.startedAt.year,
        s.startedAt.month,
        s.startedAt.day,
      );
      final diff = today.difference(day).inDays;
      if (diff >= 0 && diff < 7) counts[6 - diff] += s.completedSetCount;
    }
    final maxCount = counts.fold(1, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: _RhythmColumn(
                count: counts[i],
                fraction: counts[i] / maxCount,
                letter: _weekdayLetter(today.subtract(Duration(days: 6 - i))),
                isToday: i == 6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _weekdayLetter(DateTime d) =>
      ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1];
}

class _RhythmColumn extends StatelessWidget {
  const _RhythmColumn({
    required this.count,
    required this.fraction,
    required this.letter,
    required this.isToday,
  });

  final int count;
  final double fraction;
  final String letter;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final trained = count > 0;
    return Column(
      children: [
        Container(
          height: 34,
          width: double.infinity,
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            height: trained ? (14 + 20 * fraction.clamp(0.0, 1.0)) : 3,
            decoration: BoxDecoration(
              gradient: trained
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        TrainColors.green,
                        TrainColors.green.withValues(alpha: 0.45),
                      ],
                    )
                  : null,
              color: trained ? null : TrainColors.hairline,
              borderRadius: BorderRadius.circular(5),
              boxShadow: trained
                  ? [
                      BoxShadow(
                        color: TrainColors.green.withValues(alpha: 0.30),
                        blurRadius: 10,
                        spreadRadius: -2,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          letter,
          style: AppText.meta.copyWith(
            color: isToday ? TrainColors.ember : TrainColors.ink4,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

/// A compact bodyweight snapshot — latest reading, its 30-day delta, and a
/// small sparkline — folded in here so "how am I progressing" covers the
/// body, not just the lifts. Omitted entirely when nothing's been logged.
class _WeightSnapshotRow extends StatelessWidget {
  const _WeightSnapshotRow({required this.trend});

  final WeightTrend trend;

  @override
  Widget build(BuildContext context) {
    final latest = trend.latest!;
    final change = trend.changeKgOverWindow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  TrainColors.amber.withValues(alpha: 0.28),
                  TrainColors.amber.withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              AppIcons.scale,
              size: 14,
              color: TrainColors.amber,
            ),
          ),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_trim(latest.weightKg)} kg',
                style: AppText.rowTitle.copyWith(
                  fontWeight: FontWeight.w700,
                  color: TrainColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                change == null
                    ? 'Bodyweight'
                    : '${change > 0 ? '+' : ''}${_trim(change)}kg over 30d',
                style: AppText.meta.copyWith(
                  color: TrainColors.ink4,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (trend.series.length >= 2)
            SizedBox(
              width: 96,
              child: TrendChart(
                values: [for (final e in trend.series) e.weightKg],
                color: TrainColors.amber,
                height: 36,
              ),
            ),
        ],
      ),
    );
  }
}

/// Every exercise for the selected day as one sectioned list — hairline
/// dividers between rows instead of a repeated bordered card per exercise —
/// so a five-exercise day reads as one coherent list, not five identical
/// boxes stacked on top of each other.
class _ExerciseListCard extends StatelessWidget {
  const _ExerciseListCard({required this.exercises, super.key});

  final List<ExerciseProgress> exercises;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        children: [
          for (final (i, exercise) in exercises.indexed) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: TrainColors.hairline,
              ),
            StaggeredReveal(
              index: i,
              child: _ExerciseRow(exercise: exercise),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise});

  final ExerciseProgress exercise;

  @override
  Widget build(BuildContext context) {
    final weights = [for (final p in exercise.trend) p.topWeightKg];
    final hasWeightTrend = weights.any((w) => w != null);
    final series = hasWeightTrend
        ? weights
        : [for (final p in exercise.trend) p.volume];
    final showChart = exercise.appearances >= 2 && series.length >= 2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        exercise.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.rowTitle.copyWith(
                          fontWeight: FontWeight.w600,
                          color: TrainColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (exercise.verdict != null)
                      _VerdictBadge(
                        verdict: exercise.verdict!,
                        label: verdictStyle(exercise.verdict!).$3,
                      )
                    else
                      _NeutralTag(
                        label: exercise.appearances == 0
                            ? 'Not logged'
                            : 'First time',
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                if (exercise.appearances >= 2 &&
                    (exercise.repsChangePercent != null ||
                        exercise.weightChangeKg != null ||
                        exercise.volumeChangePercent != null))
                  // Metric deltas, each colored by its own direction — the
                  // row's story readable at a glance without parsing numbers.
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      if (exercise.repsChangePercent != null)
                        _MetricDelta(
                          label: 'Reps',
                          text: _signedPercent(exercise.repsChangePercent!),
                        ),
                      if (exercise.weightChangeKg != null)
                        _MetricDelta(
                          label: 'Weight',
                          text: _signedKg(exercise.weightChangeKg!),
                        ),
                      if (exercise.volumeChangePercent != null)
                        _MetricDelta(
                          label: 'Volume',
                          text: _signedPercent(exercise.volumeChangePercent!),
                        ),
                    ],
                  )
                else
                  Text(
                    _fallbackSubtitle(exercise),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.meta.copyWith(color: TrainColors.ink4),
                  ),
              ],
            ),
          ),
          if (showChart) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 64,
              child: TrendChart(
                values: series,
                height: 32,
                // Green for Progressing/Matched (the chart's original look);
                // Down borrows the exact red verdictStyle uses for its
                // badge, so a regressing exercise reads as a red line at a
                // glance, not just a red badge.
                color: exercise.verdict == ProgressVerdict.down
                    ? verdictStyle(ProgressVerdict.down).$2
                    : TrainColors.green,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _fallbackSubtitle(ExerciseProgress exercise) {
    if (exercise.appearances == 1) {
      return exercise.lastTopWeightKg == null
          ? 'Logged once — no weight recorded.'
          : 'Last: ${_trim(exercise.lastTopWeightKg!)}kg top set.';
    }
    return 'Not part of a session yet.';
  }

  static String _signedPercent(double v) => '${v > 0 ? '+' : ''}${v.round()}%';
  static String _signedKg(double v) =>
      '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}kg';
}

/// One colored metric delta — label in the quiet ink, value tinted by its
/// direction (pulse up, flare down, ink3 flat).
class _MetricDelta extends StatelessWidget {
  const _MetricDelta({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final value = double.tryParse(text.replaceAll(RegExp(r'[+%kg]'), '')) ?? 0;
    final color = value > 0
        ? TrainColors.green
        : value < 0
        ? TrainColors.ember
        : TrainColors.ink4;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppText.meta.copyWith(
            color: TrainColors.ink4,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppText.meta.copyWith(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// A pill badge for a [ProgressVerdict] — same visual language (icon,
/// pulse/ink3/flare coloring, translucent fill) as the live session's
/// per-set progress badge, so the analysis page's verdicts read as the same
/// system the user already sees mid-workout.
class _VerdictBadge extends StatelessWidget {
  const _VerdictBadge({required this.verdict, required this.label});

  final ProgressVerdict verdict;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (icon, color, _) = verdictStyle(verdict);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.meta.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _NeutralTag extends StatelessWidget {
  const _NeutralTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: TrainColors.ink4.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppText.meta.copyWith(
          color: TrainColors.ink4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AnalysisLoadingState extends StatelessWidget {
  const _AnalysisLoadingState();

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

class _AnalysisErrorState extends StatelessWidget {
  const _AnalysisErrorState();

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
              'Check your connection and try again in a moment.',
              style: AppText.meta.copyWith(color: TrainColors.ink4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPlanState extends StatelessWidget {
  const _NoPlanState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'Create a workout plan to see progress analysis.',
          style: AppText.aside.copyWith(color: TrainColors.ink2),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// No completed sessions for this day yet — nothing to analyze.
class _DayEmptyState extends StatelessWidget {
  const _DayEmptyState({required this.dayLabel});

  final String dayLabel;

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
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  TrainColors.green.withValues(alpha: 0.22),
                  TrainColors.green.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              AppIcons.analysis,
              size: 20,
              color: TrainColors.green,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "You haven't logged $dayLabel yet.",
            style: AppText.rowTitle.copyWith(
              fontWeight: FontWeight.w600,
              color: TrainColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Complete a session to start tracking progress.',
            style: AppText.meta.copyWith(color: TrainColors.ink4),
          ),
        ],
      ),
    );
  }
}

String _trim(double v) =>
    v.truncateToDouble() == v ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _formatDurationShort(Duration d) {
  final totalMinutes = d.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}
