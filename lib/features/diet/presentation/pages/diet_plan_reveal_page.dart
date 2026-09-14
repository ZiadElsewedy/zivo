import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/widgets/async_action.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../l10n/l10n.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../workout/domain/body_weight_entry.dart';
import '../../domain/diet_day.dart';
import '../../domain/diet_format.dart';
import '../../domain/diet_plan.dart';
import '../../domain/meal.dart';
import '../../domain/nutrition_targets.dart';
import '../controllers/diet_builder_controller.dart';
import '../diet_labels.dart';
import 'diet_plan_edit_page.dart';

/// The payoff of the Diet Builder: the finished plan, with the daily target now
/// shown as useful context rather than something the user had to work out, a
/// coach note, and a subtle safety line.
///
/// **This screen is the single approval.** Nothing the wizard gathered is saved
/// until Save here — body data, the calculated target and the plan are all
/// written together, honoring ADR-007's rule that a target exists only once the
/// user has accepted one. The number was computed silently and sized the plan;
/// tapping Save is where it becomes theirs.
class DietPlanRevealPage extends StatefulWidget {
  const DietPlanRevealPage({
    super.key,
    required this.plan,
    required this.result,
  });

  final DietPlan plan;
  final DietBuilderResult result;

  @override
  State<DietPlanRevealPage> createState() => _DietPlanRevealPageState();
}

class _DietPlanRevealPageState extends State<DietPlanRevealPage>
    with AsyncAction<DietPlanRevealPage> {
  late DietPlan _plan = widget.plan;

  NutritionTargets get _targets => widget.result.proposal.targets;

  /// The day the reveal shows — the first every-day template if there is one,
  /// else the first day. A generated plan is normally one every-day template.
  DietDay get _day => _plan.days.firstWhere(
        (d) => d.weekday == null,
        orElse: () => _plan.days.first,
      );

  Future<void> _edit() async {
    final edited = await Navigator.of(context).push<DietPlan>(
      MaterialPageRoute(
        // autosave:false — the editor returns the edited plan without writing
        // it, because Save on THIS screen is still the one commit.
        builder: (_) => DietPlanEditPage(initialPlan: _plan, autosave: false),
      ),
    );
    if (edited != null && mounted) setState(() => _plan = edited);
  }

  void _save() => runAction(#save, _commitSave, once: true);

  Future<void> _commitSave() async {
    final scope = AppScope.of(context);
    final navigator = Navigator.of(context);
    final result = widget.result;

    // Body data first — it's the basis the target and every later verdict rest
    // on, and it's what the user just confirmed.
    await scope.diet.saveBodyProfile(result.profile);
    final newWeight = result.newWeightKg;
    if (newWeight != null && scope.bodyWeight != null) {
      await scope.bodyWeight!.save(
        BodyWeightEntry(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          weightKg: newWeight,
          loggedAt: DateTime.now(),
        ),
      );
    }
    // The target the plan was sized to, now approved.
    await scope.diet.saveTargets(_targets);
    // The plan itself — active, which archives any previous active in the
    // repository's batched write (its invariant, not the caller's).
    await scope.diet.savePlan(_plan);

    if (!mounted) return;
    HapticFeedback.mediumImpact();
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final belowFloor = widget.result.proposal.belowSafetyFloor;
    final meals = regularMeals(_day.meals);
    final supplements = supplementMeals(_day.meals);

    return TrainScreen(
      tint: TrainColors.dietTint,
      child: Column(
        children: [
          CaptureTopBar(
            title: l(context).dietBuilderPlanReadyTitle,
            onClose: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ListView(
              key: const Key('reveal-list'),
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
              children: [
                Text(
                  l(context).dietBuilderPlanReadySubtitle,
                  style: AppText.body.copyWith(
                    color: TrainColors.ink2,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                _TargetCard(targets: _targets),
                if (belowFloor) ...[
                  const SizedBox(height: 12),
                  _SafetyFloorNote(calories: _targets.calories),
                ],
                const SizedBox(height: 24),
                TrainSectionLabel(_day.label),
                const SizedBox(height: 12),
                for (final meal in meals) ...[
                  _MealRow(meal: meal),
                  const SizedBox(height: 12),
                ],
                if (supplements.isNotEmpty) ...[
                  for (final meal in supplements) ...[
                    _MealRow(meal: meal),
                    const SizedBox(height: 12),
                  ],
                ],
                const SizedBox(height: 12),
                _CoachNote(),
                const SizedBox(height: 14),
                Text(
                  l(context).dietBuilderSafetyNote,
                  key: const Key('reveal-safety-note'),
                  style: AppText.meta.copyWith(
                    color: TrainColors.ink3,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),
                PillButton(
                  key: const Key('reveal-save'),
                  label: l(context).dietBuilderSavePlan,
                  icon: Icons.check_rounded,
                  enabled: !actionInFlight,
                  busy: isRunning(#save),
                  onTap: _save,
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    key: const Key('reveal-edit'),
                    onPressed: actionInFlight ? null : _edit,
                    child: Text(
                      l(context).dietBuilderEditPlan,
                      style: AppText.meta.copyWith(color: TrainColors.ink2),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l(context).dietNothingSavedUntilReview,
                  style: AppText.meta.copyWith(color: TrainColors.ink3),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The daily target, now shown because it's useful context rather than
/// something the user had to figure out. Calories big, macros beneath.
class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.targets});

  final NutritionTargets targets;

  @override
  Widget build(BuildContext context) {
    return TrainCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l(context).dietDailyTarget.toUpperCase(),
            style: TrainType.caption(size: 9, tracking: 0.16),
          ),
          const SizedBox(height: 8),
          Text(
            ltrFor(context, l(context).dietKcalValue(targets.calories)),
            key: const Key('reveal-target-kcal'),
            style: TrainType.mono(size: 30, weight: FontWeight.w600),
          ),
          if (_macros(context) case final line?) ...[
            const SizedBox(height: 8),
            Text(
              ltrFor(context, line),
              key: const Key('reveal-target-macros'),
              style: AppText.meta.copyWith(color: TrainColors.ink2),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            targetSourceText(context, targets.source),
            style: AppText.meta.copyWith(color: TrainColors.ink3),
          ),
        ],
      ),
    );
  }

  /// "165g protein · 240g carbs · 65g fat", or null when no macro is set.
  String? _macros(BuildContext context) {
    final p = targets.proteinG;
    final c = targets.carbsG;
    final f = targets.fatG;
    if (p == null && c == null && f == null) return null;
    return l(context).dietBuilderMacros(
      p == null ? '—' : trimNumber(p),
      c == null ? '—' : trimNumber(c),
      f == null ? '—' : trimNumber(f),
    );
  }
}

/// One meal, as the reveal shows it: its name, its foods, and its calories.
class _MealRow extends StatelessWidget {
  const _MealRow({required this.meal});

  final Meal meal;

  @override
  Widget build(BuildContext context) {
    final kcal = mealCalories(meal);
    final estimated = mealEstimated(meal);
    final foods = meal.items.map((i) => i.name).where((n) => n.isNotEmpty);
    return TrainCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(isolate(meal.label), style: AppText.rowTitle),
              ),
              if (kcal != null) ...[
                const SizedBox(width: 12),
                Text(
                  ltrFor(
                    context,
                    '${approx(estimated)}${l(context).dietKcalValue(kcal)}',
                  ),
                  style: AppText.meta.copyWith(color: TrainColors.ink2),
                ),
              ],
            ],
          ),
          if (foods.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              isolate(foods.join('  ·  ')),
              style: AppText.meta.copyWith(
                color: TrainColors.ink3,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The coach's framing — this is a starting point, adjust as you go.
class _CoachNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TrainCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l(context).dietBuilderCoachNote,
            style: TrainType.caption(size: 9, tracking: 0.16),
          ),
          const SizedBox(height: 6),
          Text(
            l(context).dietBuilderCoachNoteBody,
            style: AppText.body.copyWith(color: TrainColors.ink2, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Shown when the computed target lands under the safety floor — the same
/// deterministic warning the Targets page uses, so it can't depend on the model
/// choosing to mention it.
class _SafetyFloorNote extends StatelessWidget {
  const _SafetyFloorNote({required this.calories});

  final int calories;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('reveal-below-floor'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: TrainColors.ember.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TrainColors.ember.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 17, color: TrainColors.ember),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              l(context).dietBelowSafeWarning(calories, kMinimumSafeCalories),
              style: AppText.meta.copyWith(color: TrainColors.ink2, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
