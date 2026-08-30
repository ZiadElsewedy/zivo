/// The deterministic coaching engine: `DietState` in, typed findings out.
///
/// **This is where the coach's decisions live.** Not in the model — here, in
/// code that can be read, tested, and pointed at. The model's job downstream is
/// to phrase what this decided, which is what makes a recommendation
/// explainable ("why is this being said?" → the finding's `evidence`) and what
/// gives the Phase 7 validator something correct to fall back to when a
/// generated reply is rejected.
///
/// Pure and total: same state in, same findings out, in the same order.
///
/// Rules only fire when they have something real to say. The negatives matter
/// as much as the positives — a protein target that is met must produce no
/// shortfall, an empty day must produce no overshoot — and the tests assert
/// both directions.
library;

import '../diet_goal.dart';
import '../diet_state.dart';
import '../nutrition_targets.dart';
import 'finding.dart';

/// How many findings a turn may carry.
///
/// Three. A coach who lists six things has told you nothing: the point of
/// ranking by severity is that the one that matters arrives first and the rest
/// wait for another day. Rule sprawl is the failure mode this cap exists to
/// prevent.
const int kMaxFindings = 3;

/// Protein shortfall smaller than this isn't worth a recommendation — it's
/// inside the noise of any real day's eating.
const double _kMinProteinShortfallG = 15;

/// The calorie budget is "running out" below this share of the target. Used to
/// decide whether a protein gap is still comfortably closable or is becoming a
/// real squeeze.
const double _kBudgetTightFraction = 0.35;

/// The hour after which an empty log stops being "the day is young".
const int _kEveningHour = 18;

/// Builds the coaching findings for [state], best-first, capped at
/// [kMaxFindings].
///
/// [localHour] is the user's own hour of day (0–23) when known. It is a
/// property of *now*, not of the day being summarised, which is why it's a
/// parameter here rather than a field on the state. Rules that need it simply
/// don't fire when it's null — a coach that doesn't know whether it's breakfast
/// or bedtime should say less, not guess.
List<CoachingFinding> coachingFindings(DietState state, {int? localHour}) {
  final findings = <CoachingFinding>[
    ..._safety(state),
    ..._blockers(state, localHour),
    ..._progress(state),
    ..._wins(state),
    ..._provenance(state),
  ];

  // Severity first, then the order the rules produced them — which is
  // deliberate and stable, so the same state always yields the same three.
  final ranked = [...findings]
    ..sort((a, b) => b.severity.index.compareTo(a.severity.index));
  return ranked.take(kMaxFindings).toList();
}

/// Things that could do harm. These outrank everything and are never capped
/// out: a target below the safety floor matters more than any progress note.
List<CoachingFinding> _safety(DietState state) {
  final targets = state.targets;
  if (targets == null) return const [];
  if (!targetIsBelowSafetyFloor(targets.calories)) return const [];
  return [
    CoachingFinding(
      code: 'target_below_safety_floor',
      kind: FindingKind.warning,
      severity: FindingSeverity.urgent,
      text:
          'The daily target is set to ${targets.calories} kcal, below the '
          '$kMinimumSafeCalories kcal floor ZIVO will coach to. Eating this '
          'low is worth talking through with a doctor or a registered '
          'dietitian first.',
      evidence: const ['targets.calories'],
    ),
  ];
}

/// The state is too thin to coach from. Saying so IS the coaching — it is the
/// honest alternative to producing advice that only sounds specific.
List<CoachingFinding> _blockers(DietState state, int? localHour) {
  final findings = <CoachingFinding>[];

  if (state.quality.targetsUnset) {
    findings.add(
      const CoachingFinding(
        code: 'targets_unset',
        kind: FindingKind.clarification,
        severity: FindingSeverity.important,
        text:
            "No daily target is set, so there's nothing to measure today "
            'against. Setting a goal and a calorie target is what turns this '
            'from a food diary into coaching.',
        evidence: ['quality.targetsUnset'],
      ),
    );
  }

  if (state.quality.nothingLogged) {
    // An empty log means nothing was RECORDED. Before evening that is
    // unremarkable; after it, it's worth a nudge — but it is never reported as
    // "you haven't eaten".
    final late = localHour != null && localHour >= _kEveningHour;
    findings.add(
      CoachingFinding(
        code: 'nothing_logged',
        kind: FindingKind.clarification,
        severity: late ? FindingSeverity.notable : FindingSeverity.info,
        text: late
            ? "Nothing's been logged today. Anything recorded now still counts "
                  '— and without it there are no numbers to work from.'
            : "Nothing's logged yet today, so there's nothing to read into the "
                  'zero.',
        evidence: const ['quality.nothingLogged', 'consumed.basis'],
      ),
    );
  }

  return findings;
}

/// Where the user stands against their objective, and what to do about it.
List<CoachingFinding> _progress(DietState state) {
  final targets = state.targets;
  final remaining = state.remaining;
  if (targets == null || remaining == null) return const [];
  if (state.quality.nothingLogged) return const [];

  final findings = <CoachingFinding>[
    CoachingFinding(
      code: 'calories_consumed',
      kind: FindingKind.observation,
      severity: FindingSeverity.info,
      text:
          '${state.consumed.kcal} of ${targets.calories} kcal so far '
          '(${consumedBasisLabel(state.consumed.basis)}).',
      evidence: const ['consumed.kcal', 'targets.calories', 'consumed.basis'],
    ),
  ];

  if (remaining.overTarget) {
    findings.add(
      CoachingFinding(
        code: 'calories_over_target',
        kind: FindingKind.analysis,
        severity: FindingSeverity.important,
        text:
            "That's ${-remaining.kcal} kcal past the "
            '${dietGoalLabel(targets.goal).toLowerCase()} target of '
            '${targets.calories}.',
        evidence: const ['remaining.kcal', 'targets.calories', 'targets.goal'],
      ),
    );
  } else {
    findings.add(
      CoachingFinding(
        code: 'calories_remaining',
        kind: FindingKind.analysis,
        severity: FindingSeverity.info,
        text:
            '${remaining.kcal} kcal left against the '
            '${dietGoalLabel(targets.goal).toLowerCase()} target.',
        evidence: const ['remaining.kcal', 'targets.goal'],
      ),
    );
  }

  final protein = _proteinShortfall(state, targets, remaining);
  if (protein != null) findings.add(protein);

  return findings;
}

/// The recommendation the original brief used as its worked example: protein
/// short while the calorie budget is running out.
///
/// It fires only when both halves are true. A protein gap at breakfast is not
/// a problem — there is a whole day to close it — and saying so would be the
/// generic nagging this engine exists to replace. It becomes actionable when
/// the room to fix it is running out.
CoachingFinding? _proteinShortfall(
  DietState state,
  NutritionTargets targets,
  RemainingTotals remaining,
) {
  final target = targets.proteinG;
  final short = remaining.proteinG;
  if (target == null || short == null || short <= _kMinProteinShortfallG) {
    return null;
  }
  // Is the calorie budget tight enough that this is now a squeeze?
  final budgetLeft = remaining.kcal;
  final tight = budgetLeft <= targets.calories * _kBudgetTightFraction;
  if (!tight) return null;

  final overBudget = budgetLeft <= 0;
  return CoachingFinding(
    code: 'protein_shortfall',
    kind: FindingKind.recommendation,
    severity: FindingSeverity.important,
    text: overBudget
        ? '${short.round()}g short of the ${target.round()}g protein target '
              'with the calorie budget already spent — worth prioritising '
              'protein earlier tomorrow.'
        : '${short.round()}g short of the ${target.round()}g protein target, '
              'with $budgetLeft kcal left. A lean protein source closes most '
              "of that gap without using much of what's left.",
    evidence: const [
      'remaining.proteinG',
      'targets.proteinG',
      'remaining.kcal',
      'targets.calories',
    ],
  );
}

/// Real wins, stated because they happened. Never filler: an encouragement
/// that fires on a day nothing went right is worse than silence.
List<CoachingFinding> _wins(DietState state) {
  final targets = state.targets;
  final remaining = state.remaining;
  if (targets == null || remaining == null) return const [];
  if (state.quality.nothingLogged) return const [];

  final findings = <CoachingFinding>[];

  final proteinTarget = targets.proteinG;
  final proteinLeft = remaining.proteinG;
  if (proteinTarget != null && proteinLeft != null && proteinLeft <= 0) {
    findings.add(
      CoachingFinding(
        code: 'protein_met',
        kind: FindingKind.encouragement,
        severity: FindingSeverity.notable,
        text:
            'Protein is already at ${state.consumed.proteinG.round()}g against '
            'a ${proteinTarget.round()}g target — that part of the day is done.',
        evidence: const ['consumed.proteinG', 'targets.proteinG'],
      ),
    );
  }

  return findings;
}

/// What the numbers rest on. These are quiet by design — they qualify the
/// findings above rather than competing with them — but they must exist, so
/// the coach never presents an assumption as a measurement.
List<CoachingFinding> _provenance(DietState state) {
  final findings = <CoachingFinding>[];

  if (state.quality.consumedIsAssumed) {
    findings.add(
      const CoachingFinding(
        code: 'consumption_assumed',
        kind: FindingKind.clarification,
        // Notable, not info: a qualifier that says the numbers are assumptions
        // must never be dropped by the cap in favour of a readout of those
        // same numbers. Being wrong about what a figure MEANS is worse than
        // omitting the figure.
        severity: FindingSeverity.notable,
        text:
            "Today's totals come from the meals ticked off the plan, not from "
            'food that was weighed — so they say what the plan expected, not '
            'what was actually eaten.',
        evidence: ['consumed.basis', 'quality.consumedIsAssumed'],
      ),
    );
  }

  if (state.quality.hasEstimatedValues) {
    findings.add(
      const CoachingFinding(
        code: 'estimated_values',
        kind: FindingKind.clarification,
        // Notable for the same reason as `consumption_assumed`.
        severity: FindingSeverity.notable,
        text:
            "Some of today's figures were estimated when the plan was "
            'imported rather than measured, so treat them as approximate.',
        evidence: ['quality.hasEstimatedValues', 'consumed.estimated'],
      ),
    );
  }

  final untracked = state.quality.untrackedMacros;
  if (untracked.isNotEmpty && !state.quality.targetsUnset) {
    findings.add(
      CoachingFinding(
        code: 'untracked_macros',
        kind: FindingKind.clarification,
        severity: FindingSeverity.info,
        text:
            'No target set for ${untracked.join(', ')} — there is nothing to '
            'be over or under on there.',
        evidence: const ['quality.untrackedMacros'],
      ),
    );
  }

  return findings;
}
