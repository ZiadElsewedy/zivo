import 'package:flutter/material.dart';
import '../../../domain/logged_set.dart';
import '../../../domain/progress_comparison.dart';
import '../../../domain/workout_day.dart';
import '../../../../../l10n/l10n.dart';
import '../../workout_format.dart';

export '../../workout_format.dart' show trimWeight;

/// "Day A · Push". Takes a context because the separator and the word order
/// belong to the translator, not to this function.
String dayTitle(BuildContext context, WorkoutDay day) =>
    l(context).workoutDayLabel(day.slot, day.label);

/// "4:05" under an hour, "1:04:05" past one — the "time in workout" label.
String formatElapsed(Duration d) {
  final totalSeconds = d.inSeconds < 0 ? 0 : d.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final mm = minutes.toString().padLeft(2, '0');
    return '$hours:$mm:$ss';
  }
  return '$minutes:$ss';
}

/// "+2.5kg from your previous set" / "+2 reps from your previous set" — a
/// literal same-session delta against [previous] (the exercise's
/// immediately-preceding COMPLETED set this session), distinct from the
/// cross-session [SetProgressComparison] badge (which judges against last
/// week). Weight wins when both changed — the more meaningful signal on a
/// loaded exercise — reps only when weight didn't change or isn't tracked.
/// Null when there's no previous set yet, or nothing actually changed.
/// How what you're about to log compares to your OWN previous set in this
/// exercise, today.
///
/// Null only when there is no previous set in the session to compare against
/// (the first working set) — otherwise it always says something, including
/// when nothing has changed. That "matching" case used to return null, which
/// meant the chip popped into existence the moment you tapped +2.5 and popped
/// back out when you undid it: the goal card changed height under your thumb,
/// shunting the whole layout, for the smallest edit on the screen. Present
/// from set two onward keeps the card one height while you step, and
/// "matching your previous set" is worth saying on its own.
({String label, bool changed})? intraSessionDeltaLabel({
  required AppLocalizations strings,
  required LoggedSet? previous,
  required int? actualReps,
  required double? actualWeightKg,
}) {
  if (previous == null) return null;
  final prevWeight = previous.actualWeightKg;
  if (prevWeight != null &&
      actualWeightKg != null &&
      actualWeightKg != prevWeight) {
    final delta = actualWeightKg - prevWeight;
    return (
      label: strings.liveDeltaWeight(
        '${delta > 0 ? '+' : ''}${trimWeight(delta)}',
      ),
      changed: true,
    );
  }
  final prevReps = previous.actualReps;
  if (prevReps != null && actualReps != null && actualReps != prevReps) {
    final delta = actualReps - prevReps;
    return (
      label: strings.liveDeltaReps('${delta > 0 ? '+' : ''}$delta'),
      changed: true,
    );
  }
  return (label: strings.liveMatchingPrevious, changed: false);
}

/// "60kg × 8" — omits either half when unset; "First time" when there's no
/// previous performance to show at all (never trained, or never logged).
String formatLastTime(AppLocalizations strings, LoggedSet? previous) {
  // Reps first, then load — the same reading order as the set chips and the
  // goal card's hero, so the eye never has to re-orient between them.
  final reps = previous?.actualReps;
  final weight = previous?.actualWeightKg;
  if (reps == null && weight == null) return strings.liveFirstTime;
  if (reps == null) return strings.liveWeightValue(trimWeight(weight!));
  if (weight == null) return strings.liveRepsValue(reps);
  return strings.liveRepsByWeight(reps, trimWeight(weight));
}

/// "60kg × 8" for a set's OWN actuals — omits either half when unset, "—"
/// when neither was recorded. Distinct from [formatLastTime]'s "First
/// time": that means "no prior performance to compare against"; this means
/// "nothing was typed on this set itself" (the review list's skipped-with-
/// nothing-typed case).
String formatSetActuals(LoggedSet set) {
  final parts = <String>[
    if (set.actualWeightKg != null) '${trimWeight(set.actualWeightKg!)}kg',
    if (set.actualReps != null) '× ${set.actualReps}',
  ];
  return parts.isEmpty ? '—' : parts.join(' ');
}

/// A restrained, low-opacity lift for the Goal/Warm-up cards on dark — the
/// shared [TrainColors.actionGlow(TrainColors.green)]/[TrainColors.actionGlow(TrainColors.ember)] (tuned for light-mode pill
/// buttons) read as a bright neon halo against near-black, which isn't the
/// premium feel this screen wants. This is a much softer glow paired with a
/// plain neutral hairline border, so the color reads as a subtle accent
/// rather than the card's whole edge.
List<BoxShadow> cardGlow(Color color) => [
  BoxShadow(
    color: color.withValues(alpha: 0.08),
    blurRadius: 24,
    spreadRadius: -6,
    offset: const Offset(0, 8),
  ),
];

/// "2:00" / "45s" — a rest window at a glance.
String formatRest(int seconds) {
  if (seconds <= 0) return '—';
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

/// Splits [remaining] into the premium countdown's two-tier display: the
/// bold whole-second part ("1:54" at/above a minute, "45" under it) and a
/// quieter ".CC" hundredths suffix — a common stopwatch convention that
/// reads as precise without the decimals overwhelming the big numeral.
({String whole, String centis}) restTimeParts(Duration remaining) {
  final clamped = remaining.isNegative ? Duration.zero : remaining;
  final totalCentis = clamped.inMilliseconds ~/ 10;
  final minutes = totalCentis ~/ 6000;
  final seconds = (totalCentis % 6000) ~/ 100;
  final centis = totalCentis % 100;
  final whole = minutes > 0
      ? '$minutes:${seconds.toString().padLeft(2, '0')}'
      : seconds.toString().padLeft(2, '0');
  return (whole: whole, centis: '.${centis.toString().padLeft(2, '0')}');
}
