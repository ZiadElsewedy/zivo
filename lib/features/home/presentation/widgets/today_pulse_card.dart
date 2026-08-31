import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../diet/domain/diet_plan.dart';
import '../../../diet/domain/diet_summary.dart';
import '../../../diet/presentation/today_diet.dart';
import '../../../expenses/domain/expense.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../workout/domain/live_session.dart';
import '../../../workout/domain/session_estimate.dart';
import '../../../workout/domain/session_status.dart';
import '../../../workout/domain/training_volume.dart';
import '../../domain/today_pulse.dart';
import 'common.dart';
import '../../../../l10n/l10n.dart';

/// The Today dashboard's living sections — the answer layer on top of real
/// data. Three sections live here:
///
/// * [TodayPulseSection] — "What have I done today?" three rings — trained,
///   steps, volume — over the day's signals.
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
        Padding(
          padding: const EdgeInsets.only(top: 30, bottom: 12),
          child: TrainCaption(l(context).pulseToday),
        ),
        TrainCard(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 6),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _TrainedRing(scope: scope)),
                const _RingDivider(),
                Expanded(child: _StepsRing(scope: scope)),
                const _RingDivider(),
                Expanded(child: _VolumeRing(scope: scope)),
              ],
            ),
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
    margin: const EdgeInsets.symmetric(vertical: 2),
    color: TrainColors.hairline,
  );
}

// ---------------------------------------------------------------------------
// Trained — did a workout complete today, and what was it?
// ---------------------------------------------------------------------------

class _TrainedRing extends StatelessWidget {
  const _TrainedRing({required this.scope});

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
        final done = trainedTodaySummary(sessions, now);
        final midSession = done == null
            ? sessions
                  .where(
                    (s) =>
                        s.status == SessionStatus.active &&
                        DateTime(
                              s.startedAt.year,
                              s.startedAt.month,
                              s.startedAt.day,
                            ) ==
                            today,
                  )
                  .firstOrNull
            : null;

        final String sub;
        if (done != null) {
          sub =
              '${done.label.toUpperCase()} · '
              '${done.duration.inMinutes} MIN';
        } else if (midSession != null) {
          sub = '${midSession.dayLabel.toUpperCase()} · UNDER WAY';
        } else {
          sub = l(context).pulseNotYetToday;
        }

        return TrainMetricRing(
          progress: done != null ? 1 : (midSession?.progress ?? 0),
          color: TrainColors.green,
          label: l(context).pulseTrained,
          sub: sub,
          subColor: done != null || midSession != null
              ? TrainColors.green.withValues(alpha: 0.7)
              : null,
          glyph: const Icon(
            AppIcons.workout,
            size: 24,
            color: TrainColors.green,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Steps — device steps toward the daily goal
// ---------------------------------------------------------------------------

class _StepsRing extends StatelessWidget {
  const _StepsRing({required this.scope});

  final AppScope scope;

  /// The daily step goal, as a caption. Not a `static const` any more — the
  /// label is localized, so it belongs to a build, not to the class.
  String _goalLabel(BuildContext context) => l(context).pulseOfGoal('8K');

  @override
  Widget build(BuildContext context) {
    final counter = scope.stepCounter;
    if (counter == null) {
      // No step sensor on this host — an honest dash, never a fake number.
      return TrainMetricRing(
        progress: 0,
        color: TrainColors.inkPlain,
        label: l(context).pulseSteps,
        sub: l(context).pulseNoSensor,
        value: '–',
      );
    }
    return StreamBuilder<int>(
      stream: counter.watchStepsToday(),
      builder: (context, snapshot) {
        final steps = snapshot.data;
        if (steps == null) {
          return TrainMetricRing(
            progress: 0,
            color: TrainColors.inkPlain,
            label: l(context).pulseSteps,
            sub: _goalLabel(context),
            value: '…',
          );
        }
        final parts = formatStepsParts(steps);
        return TrainMetricRing(
          progress: (steps / kDefaultStepGoal).clamp(0.0, 1.0),
          color: TrainColors.inkPlain,
          label: l(context).pulseSteps,
          sub: _goalLabel(context),
          value: parts.value,
          unit: parts.unit,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Volume — tonnage moved this week, and where it's heading
// ---------------------------------------------------------------------------

class _VolumeRing extends StatelessWidget {
  const _VolumeRing({required this.scope});

  final AppScope scope;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LiveSession>>(
      stream: scope.workoutSessions.watchAll(),
      initialData: scope.workoutSessions.current,
      builder: (context, snapshot) {
        final trend = weeklyVolume(
          snapshot.data ?? const <LiveSession>[],
          DateTime.now(),
        );
        if (trend.isEmpty) {
          return TrainMetricRing(
            progress: 0,
            color: TrainColors.green,
            label: l(context).pulseVolume,
            sub: l(context).pulseNoSetsYet,
            value: '–',
          );
        }
        final parts = formatVolume(trend.thisWeekKg);
        final change = trend.changePercent;
        // The ring reads as "this week against last" — full when you have
        // matched last week, over-full clamped when you have beaten it.
        final progress = trend.lastWeekKg <= 0
            ? 1.0
            : (trend.thisWeekKg / trend.lastWeekKg).clamp(0.0, 1.0);
        return TrainMetricRing(
          progress: progress,
          color: TrainColors.green,
          label: l(context).pulseVolume,
          sub: change == null
              ? l(context).pulseFirstWeek
              : '${change >= 0 ? '+' : ''}${change.round()}% WoW',
          subColor: change == null
              ? null
              : TrainColors.ember.withValues(alpha: 0.75),
          value: parts.value,
          unit: parts.unit,
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

/// The same number split for the ring's core, where the unit is always
/// smaller and dimmer than the value it belongs to: 5400 → ("5.4", "K").
({String value, String unit}) formatStepsParts(int steps) {
  if (steps < 1000) return (value: '$steps', unit: '');
  final tenths = (steps / 100).round();
  return (
    value: tenths % 10 == 0 ? '${tenths ~/ 10}' : '${tenths / 10}',
    unit: 'K',
  );
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
        final hasWeight = scope.bodyWeight?.current.isNotEmpty ?? false;
        if (sessions.isEmpty && !hasWeight) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(l(context).pulseMomentum),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
              decoration: BoxDecoration(
                gradient: TrainColors.cardGradient,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: TrainColors.hairline),
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
                    const Divider(height: 1, color: TrainColors.hairline),
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
    final hasStreak = streak >= 2;
    return Row(
      children: [
        // The left slot always renders. It used to appear only once a streak
        // existed, so a real week with one session showed a blank half-row
        // and read as something failing to load rather than as a life with
        // one session in it. Dimmed, and short: the right-hand caption is
        // already a caption, and two long ones on one line collide.
        Icon(
          AppIcons.streak,
          size: 16,
          color: hasStreak ? TrainColors.ember : TrainColors.ink4,
        ),
        const SizedBox(width: 7),
        // Both halves are Flexible: this is a one-line row with two
        // independent captions in it, so on a narrow screen (or at a large
        // text scale) they have to give way rather than run past the edge.
        Flexible(
          child: hasStreak
              ? Text(
                  '$streak-day streak',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TrainType.ui(
                    size: 14.5,
                    weight: FontWeight.w700,
                    color: TrainColors.ink,
                    height: 1,
                  ),
                )
              : Text(
                  l(context).pulseNoStreakYet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TrainType.caption(
                    size: 9,
                    tracking: 0.1,
                    color: TrainColors.ink4,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        const Spacer(),
        Flexible(
          child: Text(
            weekTotal == 0
                ? l(context).pulseNoSessionsYet
                : '$weekTotal SESSION${weekTotal == 1 ? '' : 'S'} · LAST 7 DAYS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TrainType.caption(
              size: 9,
              tracking: 0.1,
              color: TrainColors.ink4,
            ),
          ),
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
    final maxWorkouts = activity.fold<int>(
      0,
      (m, d) => math.max(m, d.workouts),
    );
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
    // Green for a trained day, ember for today (the "current position"
    // marker the identity doc reserves it for), hairline for a rest day so
    // the week still reads as seven days.
    final hue = count == 0
        ? const Color(0x14FFFFFF)
        : (isToday
              ? TrainColors.ember
              : TrainColors.green.withValues(alpha: 0.55));
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
        const SizedBox(height: 7),
        Text(
          letter,
          style: TrainType.caption(
            size: 9,
            tracking: 0.1,
            weight: isToday ? FontWeight.w700 : FontWeight.w500,
            color: isToday ? TrainColors.ink2 : TrainColors.ink4,
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
    final entries = AppScope.of(
      context,
    ).requireBodyWeight.current.map((e) => (e.loggedAt, e.weightKg)).toList();
    final trend = weightTrend(entries);
    if (trend == null) return const SizedBox.shrink();
    final down = trend.deltaKg < 0;
    final kg = trend.deltaKg.abs().toStringAsFixed(1);

    // Track the polyline's own end point while building it — no metrics pass.
    var lastPoint = Offset.zero;
    final points = <Offset>[];
    final weights = trend.samples.map((s) => s.$2).toList();
    final minW = weights.reduce(math.min);
    final spanW = math.max(
      maxDouble(weights.reduce(math.max) - minW, 0.05),
      0.05,
    );
    for (var i = 0; i < trend.samples.length; i++) {
      final x = 92.0 * i / (trend.samples.length - 1);
      final y = 30.0 - 3 - (30.0 - 6) * ((trend.samples[i].$2 - minW) / spanW);
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
          '${down ? '−' : '+'}$kg',
          style: TrainType.mono(
            size: 15,
            tracking: -0.02,
            color: down ? TrainColors.green : TrainColors.ember,
          ),
        ),
        const SizedBox(width: 5),
        // A delta always states its own baseline (identity §7), and the unit
        // stays smaller and dimmer than the value it belongs to.
        Text(
          'KG · ${trend.spanDays}D',
          style: TrainType.caption(
            size: 9,
            tracking: 0.12,
            color: TrainColors.ink4,
          ),
        ),
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
      ..color = TrainColors.ink3;
    canvas.drawPath(path, paint);
    canvas.drawCircle(end, 2.5, Paint()..color = TrainColors.ink);
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
    _stepsSub ??= AppScope.of(context).stepCounter?.watchStepsToday().listen((
      steps,
    ) {
      if (mounted) setState(() => _steps = steps);
    });
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
            final summary = dietDaySummary(
              day,
              consumedSnapshot.data ?? const <String>{},
            );
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
    final weightEntries =
        scope.bodyWeight?.current
            .map((e) => (e.loggedAt, e.weightKg))
            .toList() ??
        const <(DateTime, double)>[];
    final insights = buildInsights(
      strings: l(context),
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
        SectionHeader(l(context).pulseWorthKnowing),
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
        color: TrainColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.chip * 2),
        border: Border.all(color: TrainColors.hairline),
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
                    color: TrainColors.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  insight.body,
                  style: AppText.body.copyWith(
                    fontSize: 12.5,
                    height: 1.3,
                    color: TrainColors.ink2,
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
