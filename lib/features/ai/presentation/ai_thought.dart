import 'package:flutter/widgets.dart';

import '../../../core/theme/train_tokens.dart';
import '../../../l10n/l10n.dart';

/// The kinds of work ZIVO does while it answers, as the user sees them.
///
/// The gateway only ever sends a tool's identifier (`get_diet`); this is where
/// it becomes a human state — "Reading your meal plan…" — so no identifier,
/// function name or implementation detail reaches the screen. Several tools
/// share a kind: what the user cares about is *what ZIVO is doing* (reading
/// their data, analysing it, working out numbers, suggesting options), not
/// which lookup did it.
enum AiThoughtKind {
  thinking,
  reading,
  analyzing,
  calculating,
  searching,
  suggesting,
  preparing,
}

/// A tool name → the kind of work it is. Unknown tools (added server-side
/// after this build) read as [AiThoughtKind.thinking] — never as their name.
AiThoughtKind aiThoughtKindForTool(String tool) => switch (tool) {
  'get_today' ||
  'get_diet' ||
  'get_workouts' ||
  'get_last_workout' ||
  'get_expenses' ||
  'get_sleep_summary' => AiThoughtKind.reading,
  'get_training_analysis' ||
  'get_exercise_analysis' ||
  'get_readiness' ||
  'summarize_week' => AiThoughtKind.analyzing,
  'calculate_meal_nutrition' => AiThoughtKind.calculating,
  'resolve_food' || 'search_food_product' => AiThoughtKind.searching,
  'search_food_alternatives' ||
  'suggest_meal_replacement' => AiThoughtKind.suggesting,
  _ => AiThoughtKind.thinking,
};

/// Whether this build has words for [tool]. An unknown tool still gets a live
/// "Thinking…" line, but is left out of the finished list rather than shown
/// as something it can't name.
bool aiThoughtKnowsTool(String tool) => _labels(tool) != null;

/// The live line while [tool] runs — "Reading your meal plan…".
String aiThoughtLiveLabel(AppLocalizations s, String tool) =>
    _labels(tool)?.call(s).$1 ?? s.askThinking;

/// The same step once it finished — "Read your meal plan". Null for a tool
/// this build doesn't know.
String? aiThoughtDoneLabel(AppLocalizations s, String tool) =>
    _labels(tool)?.call(s).$2;

/// One past-tense verb for the collapsed summary ("Read · Analyzed"). Null
/// for kinds that never finish as a step of their own.
String? aiThoughtVerb(AppLocalizations s, AiThoughtKind kind) => switch (kind) {
  AiThoughtKind.reading => s.askThoughtVerbRead,
  AiThoughtKind.analyzing => s.askThoughtVerbAnalyzed,
  AiThoughtKind.calculating => s.askThoughtVerbCalculated,
  AiThoughtKind.searching => s.askThoughtVerbSearched,
  AiThoughtKind.suggesting => s.askThoughtVerbSuggested,
  AiThoughtKind.thinking || AiThoughtKind.preparing => null,
};

/// The state's tone — one of the muted thought tints, resolved on every call
/// so a skin swap repaints it (never cache a token, ADR-011).
Color aiThoughtTint(AiThoughtKind kind) => switch (kind) {
  AiThoughtKind.thinking => TrainColors.thoughtThink,
  AiThoughtKind.reading => TrainColors.thoughtRead,
  AiThoughtKind.analyzing => TrainColors.thoughtAnalyze,
  AiThoughtKind.calculating => TrainColors.thoughtCalculate,
  AiThoughtKind.searching => TrainColors.thoughtSearch,
  AiThoughtKind.suggesting => TrainColors.thoughtSuggest,
  AiThoughtKind.preparing => TrainColors.thoughtPrepare,
};

(String, String) Function(AppLocalizations)? _labels(String tool) =>
    switch (tool) {
      'get_today' => (s) => (s.askThoughtDay, s.askThoughtDayDone),
      'get_diet' => (s) => (s.askThoughtDiet, s.askThoughtDietDone),
      'get_workouts' => (s) => (s.askThoughtWorkouts, s.askThoughtWorkoutsDone),
      'get_last_workout' => (s) => (
        s.askThoughtLastWorkout,
        s.askThoughtLastWorkoutDone,
      ),
      'get_training_analysis' => (s) => (
        s.askThoughtTraining,
        s.askThoughtTrainingDone,
      ),
      'get_exercise_analysis' => (s) => (
        s.askThoughtExercise,
        s.askThoughtExerciseDone,
      ),
      'get_expenses' => (s) => (s.askThoughtSpending, s.askThoughtSpendingDone),
      'summarize_week' => (s) => (s.askThoughtWeek, s.askThoughtWeekDone),
      'get_readiness' => (s) => (
        s.askThoughtReadiness,
        s.askThoughtReadinessDone,
      ),
      'get_sleep_summary' => (s) => (s.askThoughtSleep, s.askThoughtSleepDone),
      'resolve_food' => (s) => (
        s.askThoughtFoodDetails,
        s.askThoughtFoodDetailsDone,
      ),
      'calculate_meal_nutrition' => (s) => (
        s.askThoughtNutrition,
        s.askThoughtNutritionDone,
      ),
      'search_food_product' => (s) => (
        s.askThoughtProduct,
        s.askThoughtProductDone,
      ),
      'search_food_alternatives' || 'suggest_meal_replacement' => (s) => (
        s.askThoughtAlternatives,
        s.askThoughtAlternativesDone,
      ),
      _ => null,
    };
