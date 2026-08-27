import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../diet/domain/diet_plan.dart';
import '../../../diet/domain/diet_summary.dart';
import '../../../diet/presentation/today_diet.dart';
import '../../../expenses/domain/expense.dart';
import '../../../workout/domain/live_session.dart';
import '../../../workout/domain/session_status.dart';
import '../../domain/today_pulse.dart';
import 'common.dart';

/// The Today dashboard's living sections — the answer layer on top of real
/// data. Three sections live here:
///
/// * [TodayPulseSection] — "What have I done today?" three thin rings
///   (train / fuel / move) over the day's signals.
/// * [MomentumSection] — "How am I doing?" streak, trailing-7-day bars,
///   weight trend.
/// * [InsightsSection] — "What should I know right now?" computed nudges.
///
/// Everything is driven by the SAME repositories every other surface reads,
/// so the dashboard can never disagree with the tabs. No looping animation
/// anywhere: these are calm surfaces that repaint only when data changes.
class TodayPulseSection extends StatelessWidget {
  const TodayPulseSection({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Today'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              Expanded(child: _TrainRing(scope: scope)),
              const _RingDivider(),
              Expanded(child: _FuelRing(scope: scope)),
              const _RingDivider(),
              Expanded(child: _MoveRing(scope: scope)),
            ],
          ),
        ),
      ],
    );
  }
}

class _RingDivider extends StatelessWidget {
  const _RingDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 52,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: AppColors.hairline,
      );
}

// ---------------------------------------------------------------------------
// Train ring — did a workout complete today?
// ---------------------------------------------------------------------------

class _TrainRing extends StatelessWidget {
  const _TrainRing({required this.scope});

  final AppScope scope;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LiveSession>>(
      stream: scope.workoutSessions.watchAll(),
      initialData: scope.workoutSessions.current,
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const <LiveSession>[];
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final done = trainedToday(sessions, now);
        final midSession = !done &&
            sessions.any(
              (s) =>
                  s.status == SessionStatus.active &&
                  DateTime(s.startedAt.year, s.startedAt.month,
                          s.startedAt.day) ==
                      today,
            );
        return PulseRing(
          progress: done ? 1 : (midSession ? 0.5 : 0),
          hue: AppColors.pulse,
          icon: AppIcons.workout,
          centerLabel: midSession ? '…' : null,
          label: done ? 'Trained' : (midSession ? 'Mid-set' : 'Train'),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Fuel ring — meals eaten vs planned today
// ---------------------------------------------------------------------------

class _FuelRing extends StatelessWidget {
  const _FuelRing({required this.scope});

  final AppScope scope;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DietPlan?>(
      stream: scope.diet.watchActivePlan(),
      initialData: scope.diet.activePlan,
      builder: (context, planSnapshot) {
        final plan = planSnapshot.data;
        final now = DateTime.now();
        final day = plan == null ? null : dayForDate(plan, now);
        if (day == null) {
          return const PulseRing(
            progress: 0,
            hue: AppColors.solar,
            icon: AppIcons.diet,
            centerLabel: '–',
            label: 'No plan',
            muted: true,
          );
        }
        return StreamBuilder<Set<String>>(
          stream: scope.diet.watchConsumed(now),
          initialData: const <String>{},
          builder: (context, consumedSnapshot) {
            final summary =
                dietDaySummary(day, consumedSnapshot.data ?? const <String>{});
            return PulseRing(
              progress:
                  summary.total == 0 ? 0 : summary.eaten / summary.total,
              hue: AppColors.solar,
              icon: AppIcons.diet,
              centerLabel: '${summary.eaten}/${summary.total}',
              label: 'Meals',
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Move ring — device steps toward the daily goal
// ---------------------------------------------------------------------------

class _MoveRing extends StatelessWidget {
  const _MoveRing({required this.scope});

  final AppScope scope;

  @override
  Widget build(BuildContext context) {
    final counter = scope.stepCounter;
    if (counter == null) {
      // No step sensor on this host — an honest dash, never a fake number.
      return const PulseRing(
        progress: 0,
        hue: AppColors.iris,
        icon: AppIcons.bolt,
        centerLabel: '–',
        label: 'Steps',
        muted: true,
      );
    }
    return StreamBuilder<int>(
      stream: counter.watchStepsToday(),
      builder: (context, snapshot) {
        final steps = snapshot.data;
        if (steps == null) {
          return const PulseRing(
            progress: 0,
            hue: AppColors.iris,
            icon: AppIcons.bolt,
            centerLabel: '…',
            label: 'Steps',
            muted: true,
          );
        }
        return PulseRing(
          progress: (steps / kDefaultStepGoal).clamp(0.0, 1.0),
          hue: AppColors.iris,
          icon: AppIcons.bolt,
          centerLabel: formatSteps(steps),
          label: 'of ${kDefaultStepGoal ~/ 1000}k steps',
        );
      },
    );
  }
}

/// 12400 → "12.4k", 8000 → "8k"; below 1000 stays exact.
String formatSteps(int steps) {
  if (steps < 1000) return '$steps';
  final tenths = (steps / 100).round();
  return tenths % 10 == 0 ? '${tenths ~/ 10}k' : '${tenths / 10}k';
}

// ---------------------------------------------------------------------------
// The shared ring primitive
// ---------------------------------------------------------------------------

/// One thin progress arc with a glyph/number core and a caption beneath — the
/// dashboard's unit of "at a glance".
class PulseRing extends StatelessWidget {
  const PulseRing({
    super.key,
    required this.progress,
    required this.hue,
    required this.icon,
    required this.centerLabel,
    required this.label,
    this.muted = false,
  });

  final double progress;
  final Color hue;
  final IconData icon;

  /// Text in the ring's core (e.g. "2/3" or "8.2k"); null centers [icon].
  final String? centerLabel;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final effectiveHue = muted ? AppColors.ink3 : hue;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 62,
          height: 62,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _RingPainter(
                    progress: muted ? 0 : progress,
                    color: effectiveHue,
                  ),
                ),
              ),
              if (centerLabel != null)
                Text(
                  centerLabel!,
                  style: AppText.heroNumber.copyWith(
                    fontSize: centerLabel!.length > 3 ? 12.5 : 15,
                    letterSpacing: -0.2,
                    color: muted ? AppColors.ink3 : AppColors.ink,
                  ),
                )
              else
                Icon(icon, size: 20, color: effectiveHue),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: AppText.meta.copyWith(
            fontSize: 10.5,
            letterSpacing: 0.3,
            color: muted ? AppColors.ink3 : AppColors.ink2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.5;
    final inset = stroke / 2 + 1;
    final arcRect = (Offset.zero & size).deflate(inset);
    final startAngle = -math.pi / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.hairline2;
    canvas.drawArc(arcRect, startAngle, math.pi * 2, false, track);

    if (progress <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      arcRect,
      startAngle,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

// ---------------------------------------------------------------------------
// Momentum — "How am I doing?"
// ---------------------------------------------------------------------------

/// Streak flame + trailing-7-day training bars + body-weight trend. Hides
/// itself until there's at least one completed session or weigh-in — a
/// dashboard must never bluff about an empty life.
class MomentumSection extends StatelessWidget {
  const MomentumSection({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<LiveSession>>(
      stream: scope.workoutSessions.watchAll(),
      initialData: scope.workoutSessions.current,
      builder: (context, sessionsSnapshot) {
        final sessions = sessionsSnapshot.data ?? const <LiveSession>[];
        final hasWeight =
            scope.bodyWeight?.current.isNotEmpty ?? false;
        if (sessions.isEmpty && !hasWeight) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('Momentum'),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 13, 18, 15),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.hairline),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StreakRow(sessions: sessions),
                  if (sessions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    WeekActivityBars(sessions: sessions),
                  ],
                  if (hasWeight) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AppColors.hairline),
                    const SizedBox(height: 10),
                    const _WeightRow(),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StreakRow extends StatelessWidget {
  const _StreakRow({required this.sessions});

  final List<LiveSession> sessions;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final streak = trainingStreakDays(sessions, now);
    final weekTotal = weekActivity(
      sessions,
      now,
    ).fold<int>(0, (s, d) => s + d.workouts);
    return Row(
      children: [
        if (streak >= 2) ...[
          const Icon(AppIcons.streak, size: 17, color: AppColors.ember),
          const SizedBox(width: 6),
          Text(
            '$streak-day streak',
            style: AppText.rowTitle.copyWith(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
        const Spacer(),
        Text(
          weekTotal == 0
              ? 'no sessions yet'
              : '$weekTotal session${weekTotal == 1 ? '' : 's'} · last 7 days',
          style: AppText.meta.copyWith(color: AppColors.ink3),
        ),
      ],
    );
  }
}

/// Seven slim bars, oldest → newest (today last, highlighted), weekday
/// initials beneath. Height is proportional to that day's completed
/// sessions; a resting day keeps a visible stub so the week reads as a week.
class WeekActivityBars extends StatelessWidget {
  const WeekActivityBars({super.key, required this.sessions});

  final List<LiveSession> sessions;

  @override
  Widget build(BuildContext context) {
    final activity = weekActivity(sessions, DateTime.now());
    final maxWorkouts =
        activity.fold<int>(0, (m, d) => math.max(m, d.workouts));
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    // Height must clear the tallest bar (8 + 38 = 46) plus the label gap (6)
    // and the weekday initial's own line box (~14 at 10sp) — 66 in all. The
    // old 62 clipped that by 4px, tripping a bottom-overflow stripe on the
    // day with the tallest bar; 68 leaves a hair of headroom.
    return SizedBox(
      height: 68,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < activity.length; i++)
            Expanded(
              child: _DayBar(
                count: activity[i].workouts,
                isToday: i == activity.length - 1,
                maxCount: math.max(maxWorkouts, 1),
                letter: weekdays[activity[i].day.weekday - 1],
              ),
            ),
        ],
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.count,
    required this.isToday,
    required this.maxCount,
    required this.letter,
  });

  final int count;
  final bool isToday;
  final int maxCount;
  final String letter;

  @override
  Widget build(BuildContext context) {
    final fraction = count == 0 ? 0.0 : (count / maxCount).clamp(0.35, 1.0);
    final hue = count == 0
        ? AppColors.surfaceRaised
        : (isToday
            ? AppColors.pulse
            : AppColors.pulse.withValues(alpha: 0.45));
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 14,
          height: 8 + 38 * fraction,
          decoration: BoxDecoration(
            color: hue,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          letter,
          style: AppText.meta.copyWith(
            fontSize: 10,
            color: isToday ? AppColors.ink2 : AppColors.ink3,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _WeightRow extends StatelessWidget {
  const _WeightRow();

  @override
  Widget build(BuildContext context) {
    final entries = AppScope.of(context)
        .requireBodyWeight
        .current
        .map((e) => (e.loggedAt, e.weightKg))
        .toList();
    final trend = weightTrend(entries);
    if (trend == null) return const SizedBox.shrink();
    final down = trend.deltaKg < 0;
    final kg = trend.deltaKg.abs().toStringAsFixed(1);

    // Track the polyline's own end point while building it — no metrics pass.
    var lastPoint = Offset.zero;
    final points = <Offset>[];
    final weights = trend.samples.map((s) => s.$2).toList();
    final minW = weights.reduce(math.min);
    final spanW = math.max(maxDouble(weights.reduce(math.max) - minW, 0.05), 0.05);
    for (var i = 0; i < trend.samples.length; i++) {
      final x = 92.0 * i / (trend.samples.length - 1);
      final y = 30.0 -
          3 -
          (30.0 - 6) * ((trend.samples[i].$2 - minW) / spanW);
      lastPoint = Offset(x, y);
      points.add(lastPoint);
    }

    return Row(
      children: [
        SizedBox(
          width: 92,
          height: 30,
          child: CustomPaint(
            painter: _SparklinePainter(points: points, end: lastPoint),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '${down ? '−' : '+'}$kg kg',
          style: AppText.rowTitle.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: down ? AppColors.pulseText : AppColors.solarText,
          ),
        ),
        const SizedBox(width: 6),
        Text('· ${trend.spanDays}d',
            style: AppText.meta.copyWith(color: AppColors.ink3)),
      ],
    );
  }
}

double maxDouble(double a, double b) => a > b ? a : b;

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.points, required this.end});

  final List<Offset> points;
  final Offset end;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.ink2;
    canvas.drawPath(path, paint);
    canvas.drawCircle(end, 2.5, Paint()..color = AppColors.ink);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.points != points || old.end != end;
}

// ---------------------------------------------------------------------------
// Insights — "What should I know right now?"
// ---------------------------------------------------------------------------

/// Up to three computed nudges drawn from live data — quiet rows, never
/// banners: each names the situation and points at the next small step.
/// Hides itself when nothing has enough signal to say anything honest.
class InsightsSection extends StatelessWidget {
  const InsightsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<LiveSession>>(
      stream: scope.workoutSessions.watchAll(),
      initialData: scope.workoutSessions.current,
      builder: (context, sessionsSnapshot) {
        return StreamBuilder<List<Expense>>(
          stream: scope.expenses.watchAll(),
          initialData: scope.expenses.current,
          builder: (context, expensesSnapshot) {
            return _InsightsInputs(
              sessions: sessionsSnapshot.data ?? const [],
              expenses: expensesSnapshot.data ?? const [],
            );
          },
        );
      },
    );
  }
}

/// Collects the remaining async inputs (diet summary, device steps) and then
/// renders whatever [buildInsights] has to say.
class _InsightsInputs extends StatefulWidget {
  const _InsightsInputs({required this.sessions, required this.expenses});

  final List<LiveSession> sessions;
  final List<Expense> expenses;

  @override
  State<_InsightsInputs> createState() => _InsightsInputsState();
}

class _InsightsInputsState extends State<_InsightsInputs> {
  StreamSubscription<int>? _stepsSub;
  int? _steps;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stepsSub ??= AppScope.of(context).stepCounter?.watchStepsToday().listen(
          (steps) {
            if (mounted) setState(() => _steps = steps);
          },
        );
  }

  @override
  void dispose() {
    _stepsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<DietPlan?>(
      stream: scope.diet.watchActivePlan(),
      initialData: scope.diet.activePlan,
      builder: (context, planSnapshot) {
        final plan = planSnapshot.data;
        final now = DateTime.now();
        final day = plan == null ? null : dayForDate(plan, now);
        if (day == null) return _render(kcalLeft: null, mealsLeft: null);
        return StreamBuilder<Set<String>>(
          stream: scope.diet.watchConsumed(now),
          initialData: const <String>{},
          builder: (context, consumedSnapshot) {
            final summary =
                dietDaySummary(day, consumedSnapshot.data ?? const <String>{});
            return _render(
              kcalLeft: summary.kcalLeft,
              mealsLeft: summary.total - summary.eaten,
            );
          },
        );
      },
    );
  }

  Widget _render({required int? kcalLeft, required int? mealsLeft}) {
    final scope = AppScope.of(context);
    final weightEntries = scope.bodyWeight?.current
            .map((e) => (e.loggedAt, e.weightKg))
            .toList() ??
        const <(DateTime, double)>[];
    final insights = buildInsights(
      sessions: widget.sessions,
      expenses: widget.expenses,
      kcalLeft: kcalLeft,
      mealsLeft: mealsLeft,
      stepsToday: _steps,
      weight: weightTrend(weightEntries),
      now: DateTime.now(),
    );
    if (insights.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Worth knowing'),
        const SizedBox(height: 2),
        for (final insight in insights)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _InsightRow(insight: insight),
          ),
      ],
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.insight});

  final PulseInsight insight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.chip * 2),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: insight.hue.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(insight.icon, size: 15, color: insight.hue),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: AppText.rowTitle.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  insight.body,
                  style: AppText.body.copyWith(
                    fontSize: 12.5,
                    height: 1.3,
                    color: AppColors.ink2,
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
