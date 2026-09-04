/// What the user is actually trying to do with their eating — the single most
/// important thing a coach has to know before it says anything at all.
///
/// Before this existed the coach could describe what was on a plan but had no
/// idea what the plan was *for*, which made every recommendation generic by
/// construction ("you should eat more protein") rather than derived from an
/// objective ("you're 35g short of the protein your fat-loss target asks for").
enum DietGoal { fatLoss, maintain, muscleGain, recomp }

/// The goal's name in the **coaching engine's** vocabulary — the English word
/// that gets spliced into a [Finding]'s prose (see `coaching/rules.dart`) and
/// quoted as evidence.
///
/// This is deliberately NOT what the UI renders. `domain/` is Flutter-free, so
/// it cannot reach `AppLocalizations`, and the coach's generated sentences are
/// English end-to-end anyway — a half-translated sentence would read worse than
/// an English one. The screen's word comes from `dietGoalText(context, goal)`
/// in `presentation/diet_labels.dart` instead. Change one, consider the other.
String dietGoalLabel(DietGoal goal) => switch (goal) {
  DietGoal.fatLoss => 'Fat loss',
  DietGoal.maintain => 'Maintain',
  DietGoal.muscleGain => 'Muscle gain',
  DietGoal.recomp => 'Recomposition',
};

/// Parses a stored [DietGoal] name. Returns null — never a default — for an
/// unknown or missing value: a goal the app invented is exactly as untrue as a
/// calorie figure it invented, and "unset" is a state the UI and the coach
/// both know how to say out loud.
DietGoal? dietGoalFromName(String? name) {
  for (final goal in DietGoal.values) {
    if (goal.name == name) return goal;
  }
  return null;
}
