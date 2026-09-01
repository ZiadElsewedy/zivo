import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/analysis/plan_verdict.dart';
import '../../domain/diet_format.dart';
import '../../domain/diet_goal.dart';
import '../../domain/diet_plan.dart';
import '../../domain/nutrition_targets.dart';
import '../../../../l10n/l10n.dart';

/// Adopting the plan's own numbers as the daily target — the shortest honest
/// route from "I have a plan" to "the app can tell me how I'm doing".
///
/// It is a sheet rather than a single tap because a target is a **goal plus
/// numbers**, and the numbers alone don't say what they're for: the same 2,400
/// kcal is a cut for one person and a bulk for another, and every piece of
/// coaching downstream reads the goal. So ZIVO supplies the figures the plan
/// already states and asks for the one thing only the user knows.
///
/// The result is stored as [TargetSource.planDerived], which says exactly
/// this: not calculated, not typed from scratch — accepted from the plan.
///
/// Returns true when a target was saved.
Future<bool> showAdoptPlanTargetSheet(
  BuildContext context, {
  required DietPlan plan,
}) async {
  final energy = planDailyEnergy(plan);
  if (energy.kcalPerDay == null) return false;
  final saved = await showZivoSheet<bool>(
    context: context,
    builder: (_) => _AdoptSheet(plan: plan, energy: energy),
  );
  return saved ?? false;
}

typedef _Energy = ({
  int? kcalPerDay,
  double? proteinG,
  double? carbsG,
  double? fatG,
  int daysCounted,
  int daysWithoutCalories,
  bool estimated,
});

class _AdoptSheet extends StatefulWidget {
  const _AdoptSheet({required this.plan, required this.energy});

  final DietPlan plan;
  final _Energy energy;

  @override
  State<_AdoptSheet> createState() => _AdoptSheetState();
}

class _AdoptSheetState extends State<_AdoptSheet> {
  DietGoal? _goal;
  bool _saving = false;

  int get _calories => widget.energy.kcalPerDay!;

  Future<void> _save() async {
    final goal = _goal;
    if (goal == null || _saving) return;
    setState(() => _saving = true);
    final diet = AppScope.of(context).diet;
    final navigator = Navigator.of(context);
    await diet.saveTargets(
      NutritionTargets(
        goal: goal,
        calories: _calories,
        // The plan's own macros come along: "use my plan's numbers" means all
        // of them, and a macro the plan doesn't state stays null rather than
        // becoming a zero the user never chose.
        proteinG: _round1(widget.energy.proteinG),
        carbsG: _round1(widget.energy.carbsG),
        fatG: _round1(widget.energy.fatG),
        source: TargetSource.planDerived,
        updatedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    HapticFeedback.lightImpact();
    navigator.pop(true);
  }

  static double? _round1(double? v) => v == null ? null : (v * 10).round() / 10;

  @override
  Widget build(BuildContext context) {
    final energy = widget.energy;
    final tilde = approx(energy.estimated);
    return Container(
      decoration: const BoxDecoration(
        color: TrainColors.raised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 22,
        right: 22,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Use your plan's numbers", style: AppText.rowTitle),
            const SizedBox(height: 4),
            Text(
              energy.daysCounted > 1
                  ? '$tilde$_calories kcal a day, averaged over the '
                        '${energy.daysCounted} days of ${widget.plan.name}.'
                  : '$tilde$_calories kcal a day, from ${widget.plan.name}.',
              key: const Key('adopt-summary'),
              style: AppText.meta.copyWith(
                color: TrainColors.ink3,
                height: 1.45,
              ),
            ),
            if (energy.daysWithoutCalories > 0) ...[
              const SizedBox(height: 6),
              Text(
                '${energy.daysWithoutCalories} '
                '${energy.daysWithoutCalories == 1 ? "day has" : "days have"} '
                'no calorie figures and are not in that average.',
                style: AppText.meta.copyWith(color: TrainColors.ink3),
              ),
            ],
            const SizedBox(height: 20),
            const TrainSectionLabel('What is it for?'),
            const SizedBox(height: 11),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final goal in DietGoal.values)
                  SelectChip(
                    key: Key('adopt-goal-${goal.name}'),
                    label: dietGoalLabel(goal),
                    selected: _goal == goal,
                    onTap: () => setState(() => _goal = goal),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _goal == null
                  // Said plainly: this is the one thing the plan cannot tell
                  // ZIVO, and every piece of coaching downstream reads it.
                  ? 'The same calories mean different things depending on what '
                        "you're doing. ZIVO needs this to say how you're doing "
                        'against them.'
                  : dietGoalDescription(_goal!),
              style: AppText.meta.copyWith(color: TrainColors.ink3),
            ),
            if (targetIsBelowSafetyFloor(_calories)) ...[
              const SizedBox(height: 14),
              Text(
                'This plan averages under $kMinimumSafeCalories kcal a day. '
                'Adopting it as a target is worth talking through with a '
                'doctor or a registered dietitian first.',
                key: const Key('adopt-safety-floor'),
                style: AppText.meta.copyWith(
                  color: TrainColors.ember,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 22),
            PillButton(
              key: const Key('adopt-save'),
              label: l(context).adoptSaveAsTarget,
              icon: Icons.check_rounded,
              enabled: _goal != null && !_saving,
              onTap: _save,
            ),
          ],
        ),
      ),
    );
  }
}
