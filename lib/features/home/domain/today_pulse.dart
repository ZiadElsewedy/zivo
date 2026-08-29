import 'package:flutter/material.dart';

import '../../../core/theme/train_tokens.dart';
import '../../../core/theme/app_icons.dart';
import '../../expenses/domain/expense.dart';
import '../../workout/domain/live_session.dart';
import '../../workout/domain/session_status.dart';

/// The Today dashboard's brain: pure, testable computations that turn the
/// app's real signals — logged sessions, meals, spends, weigh-ins, device
/// steps — into the three answers Home exists to give:
///
/// * "What have I done today?"  → the day pulse (train / fuel / move).
/// * "How am I doing?"          → momentum: streak, week bars, weight trend.
/// * "What should I know now?"  → [buildInsights] nudges, most useful first.

/// One day's completed-workout count in the trailing-7-day window.
class DayActivity {
  const DayActivity({required this.day, required this.workouts});

  final DateTime day;
  final int workouts;
}

/// A body-weight trend over a window: first/last entries plus the delta.
class WeightTrend {
  const WeightTrend({
    required this.samples,
    required this.deltaKg,
    required this.spanDays,
  });

  /// (day, kg) pairs, oldest → newest, already thinned for drawing.
  final List<(DateTime, double)> samples;

  /// Last minus first, kilograms. Negative = lighter.
  final double deltaKg;

  final int spanDays;
}

/// One computed "worth knowing" nudge for the insights strip.
class PulseInsight {
  const PulseInsight({
    required this.icon,
    required this.hue,
    required this.title,
    required this.body,
  });

  final IconData icon;

  /// Which of ZIVO's hue families this belongs to — training green, money
  /// gold, alert red, Ask iris — so the strip stays on-brand without new
  /// colors.
  final Color hue;

  final String title;
  final String body;
}

/// Completed sessions grouped per calendar day over the last [days] days,
/// oldest first, always [days] entries (today last). Abandoned sessions don't
/// count; an active session counts its START day once it completes — until
/// then it isn't history yet.
List<DayActivity> weekActivity(
  List<LiveSession> sessions,
  DateTime now, {
  int days = 7,
}) {
  final counts = List<int>.filled(days, 0);
  final start = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: days - 1));
  for (final s in sessions) {
    if (s.status != SessionStatus.completed) continue;
    final done = s.completedAt ?? s.startedAt;
    final day = DateTime(done.year, done.month, done.day);
    final i = day.difference(start).inDays;
    if (i >= 0 && i < days) counts[i]++;
  }
  return [
    for (var i = 0; i < days; i++)
      DayActivity(
        day: start.add(Duration(days: i)),
        workouts: counts[i],
      ),
  ];
}

/// Consecutive days with at least one completed workout, ending today (or
/// yesterday if today's session hasn't happened yet — a streak never reads
/// as broken before the day is over).
int trainingStreakDays(List<LiveSession> sessions, DateTime now) {
  final active = weekActivity(
    sessions,
    now,
    days: 400,
  ).reversed.toList(); // newest first
  var i = 0;
  if (active.isNotEmpty && active.first.workouts == 0) i = 1;
  var streak = 0;
  for (; i < active.length; i++) {
    if (active[i].workouts > 0) {
      streak++;
    } else {
      break;
    }
  }
  return streak;
}

/// Whether any workout COMPLETED today (the Train ring's filled state).
bool trainedToday(List<LiveSession> sessions, DateTime now) =>
    weekActivity(sessions, now, days: 1).first.workouts > 0;

/// Body-weight trend across the last [span] days, or null when there aren't
/// at least two weigh-ins to compare. At most ~14 samples are returned so
/// the sparkline draws from bounded data regardless of history size.
WeightTrend? weightTrend(List<(DateTime, double)> entries, {int span = 14}) {
  if (entries.length < 2) return null;
  final sorted = List.of(entries)..sort((a, b) => a.$1.compareTo(b.$1));
  final end = sorted.last.$1;
  final start = end.subtract(Duration(days: span));
  final window = sorted.where((e) => e.$1.isAfter(start)).toList();
  if (window.length < 2) return null;

  // Thin to at most 14 points, keeping first and last.
  final step = (window.length / 14).ceil();
  final samples = <(DateTime, double)>[];
  for (var i = 0; i < window.length; i += step) {
    samples.add(window[i]);
  }
  if (samples.last != window.last) samples.add(window.last);

  return WeightTrend(
    samples: samples,
    deltaKg: window.last.$2 - window.first.$2,
    spanDays: span,
  );
}

/// Total spent (minor units) between [from] (inclusive) and [to] (exclusive).
int spendBetween(List<Expense> items, DateTime now, {required Duration ago}) {
  final to = DateTime(now.year, now.month, now.day);
  final from = to.subtract(ago);
  return items.fold<int>(0, (sum, e) {
    final d = DateTime(e.spentAt.year, e.spentAt.month, e.spentAt.day);
    if (!d.isBefore(from) && d.isBefore(to)) return sum + e.amountMinor;
    return sum;
  });
}

/// The default daily step goal the Move ring measures against. Deliberately
/// a fixed, honest number — not gamified upward — and the single place to
/// make it personal later.
const kDefaultStepGoal = 8000;

/// Computes today's insight rows, most useful first, capped at [max].
///
/// Every rule is deliberately conservative: it only speaks when it has real
/// signal, it never scolds, and it always points somewhere ("…and here's the
/// next small step") rather than just reporting.
List<PulseInsight> buildInsights({
  required List<LiveSession> sessions,
  required List<Expense> expenses,
  required int? kcalLeft,
  required int? mealsLeft,
  required int? stepsToday,
  required WeightTrend? weight,
  required DateTime now,
  int max = 3,
}) {
  final result = <PulseInsight>[];

  // -- Training ------------------------------------------------------------
  final activity = weekActivity(sessions, now);
  final streak = trainingStreakDays(sessions, now);
  final lastDone = activity.lastWhere(
    (d) => d.workouts > 0,
    orElse: () => activity.last,
  );
  final gapDays = now.difference(lastDone.day).inDays;
  if (streak >= 3) {
    result.add(
      PulseInsight(
        icon: AppIcons.streak,
        hue: TrainColors.green,
        title: '$streak-day training streak',
        body: 'Momentum is real right now — protect it with today\'s session.',
      ),
    );
  } else if (gapDays >= 3) {
    result.add(
      PulseInsight(
        icon: AppIcons.timer,
        hue: TrainColors.amber,
        title: 'Rest has stretched to $gapDays days',
        body: 'No guilt — just the next small session whenever you\'re ready.',
      ),
    );
  }

  // -- Diet ------------------------------------------------------------------
  if (mealsLeft != null && mealsLeft > 0 && now.hour >= 19) {
    result.add(
      PulseInsight(
        icon: AppIcons.diet,
        hue: TrainColors.green,
        title: 'Evening check-in',
        body: mealsLeft == 1
            ? 'One meal still open today'
                  '${kcalLeft != null ? ' (~$kcalLeft kcal)' : ''} — worth '
                  'closing it out.'
            : '$mealsLeft meals still open today'
                  '${kcalLeft != null ? ' (~$kcalLeft kcal left)' : ''}.',
      ),
    );
  }

  // -- Money -----------------------------------------------------------------
  final thisWeek = spendBetween(expenses, now, ago: const Duration(days: 7));
  final lastWeekSameSpan = spendBetween(
    expenses,
    now.subtract(const Duration(days: 7)),
    ago: const Duration(days: 7),
  );
  if (thisWeek > 0 && lastWeekSameSpan > 0) {
    final ratio = thisWeek / lastWeekSameSpan;
    if (ratio >= 1.25) {
      final pct = ((ratio - 1) * 100).round();
      result.add(
        PulseInsight(
          icon: AppIcons.expenses,
          hue: TrainColors.amber,
          title: 'Spending is running ~$pct% hot',
          body: 'This week vs the same stretch last week — worth a glance.',
        ),
      );
    }
  }

  // -- Movement ----------------------------------------------------------------
  if (stepsToday != null && now.hour >= 16 && stepsToday < kDefaultStepGoal) {
    final left = kDefaultStepGoal - stepsToday;
    result.add(
      PulseInsight(
        icon: AppIcons.bolt,
        hue: TrainColors.violet,
        title: 'Steps are behind today',
        body: left <= 2000
            ? 'Only $left steps from the goal — an easy walk closes it.'
            : '$left steps to go — even ten minutes helps.',
      ),
    );
  }

  // -- Weight ------------------------------------------------------------------
  if (weight != null && weight.deltaKg.abs() >= 0.3) {
    final dir = weight.deltaKg < 0 ? 'down' : 'up';
    final kg = weight.deltaKg.abs().toStringAsFixed(1);
    result.add(
      PulseInsight(
        icon: AppIcons.scale,
        hue: TrainColors.green,
        title: 'Weight $dir ${kg}kg over ${weight.spanDays} days',
        body: dir == 'down'
            ? 'Steady progress — keep eating enough to train hard.'
            : 'Nothing dramatic — watch the trend, not any single day.',
      ),
    );
  }

  return result.take(max).toList();
}
