/// Turning a finding's evidence paths into the figures they actually name.
///
/// Every [CoachingFinding] carries an `evidence` list of `DietState` paths —
/// the fields it was derived from. That list is what makes "why is this being
/// said?" answerable, but only once it is *resolved*: `remaining.proteinG` is
/// a promise, "35 g short of a 160 g target" is the answer.
///
/// So this reads the state back, one path at a time, and reports what each
/// one says right now. Nothing here re-derives or re-phrases the finding — it
/// only fetches. A "why" that computed its own numbers could disagree with the
/// sentence it is explaining, which would be worse than showing nothing.
///
/// Pure, and deliberately unforgiving: a path this doesn't know is **dropped**,
/// never rendered as a blank or a "null". A row that can't say what it holds
/// isn't evidence.
library;

import '../diet_format.dart';
import '../diet_goal.dart';
import '../diet_state.dart';

/// One resolved evidence field: the state path, what to call it, and what it
/// says.
class EvidenceValue {
  const EvidenceValue({
    required this.path,
    required this.label,
    required this.value,
  });

  /// The `DietState` path this came from, e.g. `remaining.proteinG`. Kept so a
  /// row can be traced back to the field the rule actually read.
  final String path;

  /// The field in the user's words — "Protein target", not `targets.proteinG`.
  final String label;

  /// What that field says right now, formatted and united.
  final String value;
}

/// Resolves [paths] against [state], in order, dropping the ones that resolve
/// to nothing.
///
/// Deduplicated by [EvidenceValue.label], first occurrence wins: several paths
/// describe the same fact from different angles (`consumed.basis` and
/// `quality.consumedIsAssumed` are one row, not two), and repeating a line
/// makes a three-row explanation look like a six-row one.
List<EvidenceValue> evidenceFor(DietState state, List<String> paths) {
  final resolved = <EvidenceValue>[];
  final seen = <String>{};
  for (final path in paths) {
    final value = _resolve(state, path);
    if (value == null) continue;
    if (!seen.add(value.label)) continue;
    resolved.add(value);
  }
  return resolved;
}

String _grams(double v) => '${trimNumber(v)} g';

EvidenceValue? _resolve(DietState state, String path) {
  final targets = state.targets;
  final consumed = state.consumed;
  final remaining = state.remaining;
  final quality = state.quality;

  EvidenceValue at(String label, String value) =>
      EvidenceValue(path: path, label: label, value: value);

  // A macro target, or the honest "you didn't set one" — never a 0.
  EvidenceValue macroTarget(String label, double? grams) =>
      at(label, grams == null ? 'not set' : _grams(grams));

  // What's left of a macro target. Null target means there is nothing to be
  // short of, so the row doesn't exist at all.
  EvidenceValue? macroLeft(String macro, double? left) {
    if (left == null) return null;
    return left < 0
        ? at('$macro over by', _grams(-left))
        : at('$macro left', _grams(left));
  }

  switch (path) {
    case 'targets.goal':
      return targets == null ? null : at('Goal', dietGoalLabel(targets.goal));

    case 'targets.calories':
    case 'quality.targetsUnset':
      return at(
        'Daily target',
        targets == null ? 'not set' : '${targets.calories} kcal',
      );

    case 'targets.proteinG':
      return macroTarget('Protein target', targets?.proteinG);
    case 'targets.carbsG':
      return macroTarget('Carbs target', targets?.carbsG);
    case 'targets.fatG':
      return macroTarget('Fat target', targets?.fatG);

    case 'consumed.kcal':
      // Carries the "~" for the same reason every other total does: a figure
      // resting on an imported plan's guesses is not a measurement.
      return at(
        'Eaten today',
        '${approx(consumed.estimated)}${consumed.kcal} kcal',
      );
    case 'consumed.proteinG':
      return at('Protein eaten', _grams(consumed.proteinG));
    case 'consumed.carbsG':
      return at('Carbs eaten', _grams(consumed.carbsG));
    case 'consumed.fatG':
      return at('Fat eaten', _grams(consumed.fatG));

    case 'consumed.basis':
    case 'quality.consumedIsAssumed':
      return at('Where that comes from', consumedBasisLabel(consumed.basis));

    case 'consumed.estimated':
    case 'quality.hasEstimatedValues':
      return at(
        'Estimated figures',
        consumed.estimated
            ? 'some came from the imported plan, not from measurement'
            : 'none — every figure was looked up or logged',
      );

    case 'remaining.kcal':
      if (remaining == null) return null;
      return remaining.overTarget
          ? at('Over target by', '${-remaining.kcal} kcal')
          : at('Calories left', '${remaining.kcal} kcal');

    case 'remaining.proteinG':
      return macroLeft('Protein', remaining?.proteinG);
    case 'remaining.carbsG':
      return macroLeft('Carbs', remaining?.carbsG);
    case 'remaining.fatG':
      return macroLeft('Fat', remaining?.fatG);

    case 'quality.nothingLogged':
      return at(
        'Food log',
        quality.nothingLogged
            ? 'nothing logged yet'
            : '${state.log.length} ${state.log.length == 1 ? 'entry' : 'entries'}',
      );

    case 'quality.noPlanForDay':
      return at(
        'Plan for today',
        quality.noPlanForDay
            ? 'no day of your plan applies'
            : (state.dayLabel ?? state.planName ?? 'set'),
      );

    case 'quality.untrackedMacros':
      final untracked = quality.untrackedMacros;
      return at(
        'Untracked macros',
        untracked.isEmpty ? 'none' : untracked.join(', '),
      );

    default:
      // An unknown path is a rule that outgrew this map. Dropping it keeps a
      // wrong row off the screen; the finding still shows, with the evidence
      // that did resolve.
      return null;
  }
}
