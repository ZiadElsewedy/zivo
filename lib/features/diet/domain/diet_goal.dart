/// What the user is actually trying to do with their eating — the single most
/// important thing a coach has to know before it says anything at all.
///
/// Before this existed the coach could describe what was on a plan but had no
/// idea what the plan was *for*, which made every recommendation generic by
/// construction ("you should eat more protein") rather than derived from an
/// objective ("you're 35g short of the protein your fat-loss target asks for").
enum DietGoal { fatLoss, maintain, muscleGain, recomp }

/// The goal as the user reads it on screen and as the coach should name it.
String dietGoalLabel(DietGoal goal) => switch (goal) {
  DietGoal.fatLoss => 'Fat loss',
  DietGoal.maintain => 'Maintain',
  DietGoal.muscleGain => 'Muscle gain',
  DietGoal.recomp => 'Recomposition',
};

/// One line explaining what choosing this goal means for the numbers — shown
/// under each option so the user is picking an outcome, not a jargon word.
String dietGoalDescription(DietGoal goal) => switch (goal) {
  DietGoal.fatLoss => 'Eat below maintenance to lose fat, keeping protein high.',
  DietGoal.maintain => 'Hold weight steady at roughly maintenance calories.',
  DietGoal.muscleGain => 'Eat above maintenance to support building muscle.',
  DietGoal.recomp => 'Hold calories near maintenance with protein high enough '
      'to build while leaning out.',
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
