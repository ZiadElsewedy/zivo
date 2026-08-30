import 'diet_goal.dart';
import 'nutrition/food_log_entry.dart';
import 'nutrition_targets.dart';

/// Where a day's consumed figures came from. The single most important
/// qualifier on any number the coach says out loud.
enum ConsumedBasis {
  /// The user recorded these foods. Safe to say "you ate".
  logged,

  /// Materialised from planned meals the user ticked. These are the PLAN's
  /// figures, not a measurement — "your plan values what you ticked at N".
  tickedPlanMeals,

  /// Nothing was recorded. **Not the same as "they ate nothing"** — treating
  /// an empty log as a measured zero is how a coach ends up telling someone to
  /// eat when they already have.
  nothingLogged,
}

/// How the basis should be described, in the app and by the coach.
String consumedBasisLabel(ConsumedBasis basis) => switch (basis) {
  ConsumedBasis.logged => 'logged by you',
  ConsumedBasis.tickedPlanMeals => 'from the meals you ticked, not weighed',
  ConsumedBasis.nothingLogged => 'nothing logged yet',
};

/// One macro's target-versus-consumed reading, for a progress row.
class MacroProgress {
  const MacroProgress({
    required this.label,
    required this.target,
    required this.consumed,
    required this.estimated,
  });

  final String label;

  /// Grams targeted, or null when the user set no target for this macro —
  /// "absent" never reads as 0.
  final double? target;

  /// Grams consumed so far.
  final double consumed;

  /// Whether [consumed] rests on any AI-estimated figure.
  final bool estimated;

  /// Grams still to eat, or null with no target. Negative when the target is
  /// passed — the UI shows "over", it doesn't clamp the number away.
  double? get remaining => target == null ? null : target! - consumed;

  /// 0..1 for a progress bar; null with no target. Unclamped: callers clamp
  /// for drawing, the value itself stays honest.
  double? get fraction =>
      target == null || target! <= 0 ? null : consumed / target!;
}

/// One planned meal, as the state reports it.
class MealState {
  const MealState({
    required this.id,
    required this.label,
    required this.eaten,
    required this.kcal,
    required this.estimated,
    required this.isSupplement,
  });

  final String id;
  final String label;
  final bool eaten;

  /// Null when the plan states no calories for this meal — absent, not zero.
  final int? kcal;
  final bool estimated;
  final bool isSupplement;
}

/// Consumed totals plus the qualifier that makes them honest.
class ConsumedTotals {
  const ConsumedTotals({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.basis,
    required this.estimated,
    required this.entryCount,
    required this.loggedCount,
  });

  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  final ConsumedBasis basis;

  /// True when any contributing figure was AI-estimated at plan-import time.
  final bool estimated;

  final int entryCount;
  final int loggedCount;

  static const ConsumedTotals none = ConsumedTotals(
    kcal: 0,
    proteinG: 0,
    carbsG: 0,
    fatG: 0,
    basis: ConsumedBasis.nothingLogged,
    estimated: false,
    entryCount: 0,
    loggedCount: 0,
  );
}

/// What's left of the user's targets. Null components mean the user set no
/// target for that macro — never zero.
class RemainingTotals {
  const RemainingTotals({
    required this.kcal,
    this.proteinG,
    this.carbsG,
    this.fatG,
  });

  /// Negative when the target has been passed. Never clamped: "over" is a
  /// state a coach has to be able to name.
  final int kcal;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;

  bool get overTarget => kcal < 0;
}

/// A compact read on the recent past, so the coach can say "third day under"
/// without being handed every entry of every day.
class DietHistorySummary {
  const DietHistorySummary({
    required this.days,
    required this.daysWithLog,
    required this.averageKcal,
  });

  /// How many days back this covers (not how many had data).
  final int days;

  /// Days in the window that had anything recorded at all.
  final int daysWithLog;

  /// Mean kcal across the days that had something, or null when none did —
  /// averaging zeros for days nobody logged would invent a trend.
  final int? averageKcal;

  static const DietHistorySummary empty = DietHistorySummary(
    days: 0,
    daysWithLog: 0,
    averageKcal: null,
  );
}

/// What the app knows it doesn't know. Computed, not narrated: the coach is
/// handed these rather than left to infer them, and the UI reads the same
/// flags.
class DietQuality {
  const DietQuality({
    required this.targetsUnset,
    required this.noPlanForDay,
    required this.nothingLogged,
    required this.consumedIsAssumed,
    required this.hasEstimatedValues,
    required this.untrackedMacros,
  });

  /// The user has set no objective. Everything "remaining" is unavailable.
  final bool targetsUnset;

  /// No plan day resolves for this date.
  final bool noPlanForDay;

  final bool nothingLogged;

  /// Every consumed figure came from ticking planned meals rather than from
  /// something the user logged.
  final bool consumedIsAssumed;

  /// Some contributing figure was AI-estimated at plan-import time.
  final bool hasEstimatedValues;

  /// Macros the user set no target for — 'protein', 'carbs', 'fat'.
  final List<String> untrackedMacros;

  /// True when nothing is missing or assumed: a fully-known day.
  bool get isComplete => !targetsUnset && !nothingLogged && !consumedIsAssumed;
}

/// **The structured picture of the user's diet right now.**
///
/// One object, built once, from one function. The Diet screen renders it and
/// the coach is handed it — that identity is the whole point: two surfaces
/// deriving "how am I doing" independently is how they end up disagreeing, and
/// a coach that contradicts the screen is worse than no coach.
///
/// It answers, in code rather than in prose, the questions the audit set out:
/// what is the user's goal, what is their target, what have they consumed,
/// what remains, what is off-target, and — through [quality] — how much of
/// that is actually known versus assumed.
class DietState {
  const DietState({
    required this.dayKey,
    required this.weekday,
    required this.targets,
    required this.planName,
    required this.dayLabel,
    required this.meals,
    required this.consumed,
    required this.remaining,
    required this.log,
    required this.history,
    required this.quality,
  });

  /// The user's local calendar day, 'yyyy-MM-dd'.
  final String dayKey;

  /// 1 = Monday .. 7 = Sunday, in the user's own timezone.
  final int weekday;

  /// Null when the user has set no objective — a real state, never defaulted.
  final NutritionTargets? targets;

  DietGoal? get goal => targets?.goal;

  final String? planName;
  final String? dayLabel;
  final List<MealState> meals;

  final ConsumedTotals consumed;

  /// Null when [targets] is null: there is nothing to have left.
  final RemainingTotals? remaining;

  final List<FoodLogEntry> log;
  final DietHistorySummary history;
  final DietQuality quality;

  /// The day's planned energy total (supplements excluded), or null when the
  /// plan states none. Reported separately from [targets] and never conflated
  /// with it — a plan's sum is not a goal anyone chose.
  int? get plannedKcal {
    final stated = meals
        .where((m) => !m.isSupplement)
        .map((m) => m.kcal)
        .whereType<int>();
    if (stated.isEmpty) return null;
    return stated.fold<int>(0, (sum, k) => sum + k);
  }

  int get mealsEaten => meals.where((m) => !m.isSupplement && m.eaten).length;
  int get mealsTotal => meals.where((m) => !m.isSupplement).length;

  MacroProgress get protein =>
      _macro('Protein', targets?.proteinG, consumed.proteinG);
  MacroProgress get carbs => _macro('Carbs', targets?.carbsG, consumed.carbsG);
  MacroProgress get fat => _macro('Fat', targets?.fatG, consumed.fatG);

  /// The macros the user actually set a target for, in display order. A macro
  /// with no target gets no row at all — better a missing row than one
  /// silently measured against a different yardstick than its neighbours.
  List<MacroProgress> get trackedMacros =>
      [protein, carbs, fat].where((m) => m.target != null).toList();

  MacroProgress _macro(String label, double? target, double consumedG) =>
      MacroProgress(
        label: label,
        target: target,
        consumed: consumedG,
        estimated: consumed.estimated,
      );

  /// Calories left against the user's target. Zero when no target is set —
  /// callers must check [DietQuality.targetsUnset] first, which is why this is
  /// deliberately not nullable-looking sugar over [remaining].
  int get remainingKcal => remaining?.kcal ?? 0;

  bool get overTarget => remaining != null && remaining!.overTarget;

  /// 0..1 of the calorie target consumed. Unclamped.
  double get calorieFraction {
    final target = targets?.calories ?? 0;
    return target <= 0 ? 0 : consumed.kcal / target;
  }
}
