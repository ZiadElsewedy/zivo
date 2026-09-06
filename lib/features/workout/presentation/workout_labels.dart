/// The localized, direction-safe way to say what a planned set *is*.
///
/// The pure formatters in `domain/workout_plan_format.dart` build these lines
/// out of English words, which made them wrong twice over in Arabic: the words
/// were untranslated, and — the part no `.arb` key fixes — the numeric skeleton
/// they hang on was reordered by the paragraph. `3 × 8–10 · rest 1:30` came out
/// as `rest 1:30 · 10–8 × 3`, advertising a rep range of **10–8**.
///
/// So each function here does two jobs: it reads its words through
/// `l(context)`, and it pins every composed numeric run with [ltrFor] so the
/// bidirectional algorithm cannot rearrange a spec into a different spec (a
/// no-op in English, so the English lines are byte-for-byte what they were).
/// The
/// split mirrors `diet_labels.dart`: arithmetic and formatting stay in
/// `domain/`, anything a reader sees lives in `presentation/` and takes a
/// [BuildContext].
library;

import 'package:flutter/widgets.dart';

import '../../../core/util/bidi.dart';
import '../../../l10n/l10n.dart';
import '../domain/planned_exercise.dart';
import '../domain/rep_target.dart';
import '../domain/workout_day.dart';
import '../domain/workout_plan_format.dart';
import '../domain/workout_set.dart';
import 'workout_format.dart';


/// "8–10", "10", or the localized "To failure".
///
/// A range is isolated: `8–10` is digits either side of a neutral dash, so
/// without pinning it renders reversed in Arabic.
String repTargetText(BuildContext context, RepTarget target) =>
    target.kind == RepTargetKind.toFailure
    ? l(context).workoutToFailure
    : ltrFor(context, repTargetFigure(target));

/// "rest 1:30" — the clock figure pinned, the word translated.
String restText(BuildContext context, int seconds) =>
    l(context).workoutRestFor(ltrFor(context, restLabel(seconds)));

/// "10 reps · 60kg · rest 2:00" — one planned set, in full.
String setSummaryText(BuildContext context, PlannedSet set) {
  final reps = set.repTarget.kind == RepTargetKind.toFailure
      ? l(context).workoutToFailure
      : l(context).workoutRepsSpec(repTargetText(context, set.repTarget));
  return [
    reps,
    if (set.targetWeightKg != null) ltrFor(context, weightText(set.targetWeightKg!)),
    restText(context, set.restSeconds),
  ].join(' · ');
}

/// One line per distinct set spec — "3 × 8–10 · 60kg · rest 1:30".
///
/// The grouping itself is domain logic and stays there
/// ([collapsedSetGroups]); this only puts words and direction on the result.
List<String> collapsedSetSummaryTexts(
  BuildContext context,
  List<PlannedSet> sets,
) => [
  for (final group in collapsedSetGroups(sets))
    [
      l(context).workoutSetsBy(
        group.length,
        repTargetText(context, group.first.repTarget),
      ),
      if (group.first.targetWeightKg != null)
        ltrFor(context, weightText(group.first.targetWeightKg!)),
      restText(context, group.first.restSeconds),
    ].join(' · '),
];

/// "4 sets · Chest" — the muscle group dropped when unset.
String plannedExerciseMetaText(BuildContext context, PlannedExercise e) {
  final sets = l(context).workoutSetCount(e.setCount);
  final group = e.muscleGroup;
  if (group == null) return sets;
  return l(context).workoutExerciseMeta(sets, group);
}

/// "6 exercises" — the one-line meta beneath a workout day.
String workoutDayMetaText(BuildContext context, WorkoutDay day) =>
    l(context).workoutExerciseCount(day.exerciseCount);
