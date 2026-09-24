import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/widgets/zivo_confirm.dart';
import '../../domain/analysis/plan_verdict.dart';
import '../../domain/body_measures.dart';
import '../../domain/diet_format.dart';
import '../../domain/diet_goal.dart';
import '../../domain/meal.dart';
import '../../domain/diet_plan.dart';
import '../../domain/diet_plan_status.dart';
import '../widgets/body_measures_builder.dart';
import '../widgets/add_diet_sheet.dart';
import '../../../../l10n/l10n.dart';
import '../diet_labels.dart';

/// The user's **library of plans** — the cut, the bulk, the one their coach
/// wrote — with exactly one in force.
///
/// Archiving rather than deleting is the action offered first, deliberately:
/// a plan is a record of what someone was doing at a time, the consumption log
/// still refers to its meal ids, and "I'm not following this any more" is a
/// different statement from "this never happened". Delete stays available and
/// stays confirmed.
class DietPlansPage extends StatelessWidget {
  const DietPlansPage({super.key});

  @override
  Widget build(BuildContext context) {
    final diet = AppScope.of(context).diet;
    return TrainScreen(
      tint: TrainColors.dietTint,
      floatingActionButton: TrainFab(
        icon: Icons.add_rounded,
        semanticLabel: l(context).dietAddPlan,
        onTap: () => showAddDietSheet(context),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
            child: TrainPageHeader(title: l(context).plansTitle),
          ),
          Expanded(
            child: StreamBuilder<List<DietPlan>>(
              stream: diet.watchPlans(),
              initialData: diet.plans,
              builder: (context, snapshot) {
                final plans = snapshot.data ?? const <DietPlan>[];
                if (plans.isEmpty) return const _NoPlans();
                // One assembly of body data for the whole list, so every card
                // measures its plan against the same maintenance figure.
                return BodyMeasuresBuilder(
                  builder: (context, measures, _) => ListView(
                    key: const Key('plans-list'),
                    padding: EdgeInsets.fromLTRB(
                      22,
                      14,
                      22,
                      TrainBottomInset.of(context),
                    ),
                    children: [
                      Text(
                        plans.length == 1
                            ? l(context).dietOnePlanNote
                            : l(context).dietManyPlansNote(plans.length),
                        style: AppText.meta.copyWith(color: TrainColors.ink3),
                      ),
                      const SizedBox(height: 16),
                      for (final plan in plans)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _PlanCard(
                            plan: plan,
                            measures: measures.measures,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoPlans extends StatelessWidget {
  const _NoPlans();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        l(context).dietNoPlansYet,
        key: const Key('plans-empty'),
        style: AppText.aside(context),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

/// One plan in the library, as a summary rather than a record: what it is,
/// what it's for, what it adds up to, and what it would do to the user — in
/// that order of weight, so two plans can be told apart at a glance. The
/// actions sit quietly underneath; the plan is the subject, not the buttons.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.measures});

  final DietPlan plan;

  /// Null when body data is incomplete — the card then simply doesn't carry a
  /// goal or an outcome line, rather than showing a guessed one. The Diet
  /// screen is where the ask for that data lives; repeating it on every card
  /// would be nagging.
  final BodyMeasures? measures;

  bool get _isActive => plan.status == DietPlanStatus.active;

  Future<void> _activate(BuildContext context) async {
    HapticFeedback.lightImpact();
    await AppScope.of(context).diet.setActivePlan(plan.id);
  }

  Future<void> _archive(BuildContext context) async {
    HapticFeedback.lightImpact();
    await AppScope.of(context).diet.archivePlan(plan.id);
  }

  Future<void> _delete(BuildContext context) async {
    final diet = AppScope.of(context).diet;
    final confirmed = await confirmDestructive(
      context,
      title: l(context).planDeleteTitle,
      body: l(context).dietPlanArchiveHint(plan.name),
      confirmKey: const Key('confirm-delete-plan'),
    );
    if (!confirmed) return;
    await diet.deletePlan(plan.id);
  }

  @override
  Widget build(BuildContext context) {
    final measures = this.measures;
    final verdict = measures == null
        ? null
        : analysePlan(plan: plan, measures: measures);
    final energy = planDailyEnergy(plan);
    final goal = verdict == null ? null : planGoalFor(verdict.direction);
    final meals = typicalMealCount(plan);
    final summary = [
      if (goal != null) dietGoalText(context, goal),
      if (meals != null) l(context).importItemCountMeal(meals),
    ].join(' · ');

    return TrainCard(
      key: Key('plan-card-${plan.id}'),
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    isolate(plan.name),
                    key: Key('plan-name-${plan.id}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TrainType.ui(
                      size: 16,
                      weight: FontWeight.w700,
                      color: TrainColors.inkPlain,
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _StatusPill(status: plan.status),
                ),
              ],
            ),
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              summary,
              key: Key('plan-summary-${plan.id}'),
              style: AppText.meta.copyWith(color: TrainColors.ink3),
            ),
          ],
          if (energy.kcalPerDay != null) ...[
            const SizedBox(height: 12),
            Text.rich(
              key: Key('plan-kcal-${plan.id}'),
              TextSpan(
                children: [
                  TextSpan(
                    text: ltrFor(
                      context,
                      '${approx(energy.estimated)}${energy.kcalPerDay}',
                    ),
                    style: TrainType.mono(
                      size: 20,
                      weight: FontWeight.w600,
                      color: TrainColors.ink,
                    ),
                  ),
                  TextSpan(
                    text: ' ${l(context).plansKcalPerDayUnit}',
                    style: AppText.meta.copyWith(color: TrainColors.ink3),
                  ),
                ],
              ),
            ),
          ],
          if (verdict != null) ...[
            const SizedBox(height: 2),
            Text(
              verdictHeadline(verdict),
              key: Key('plan-verdict-${plan.id}'),
              style: AppText.meta.copyWith(color: TrainColors.ink3),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (!_isActive)
                _QuietAction(
                  actionKey: Key('activate-${plan.id}'),
                  label: l(context).plansFollow,
                  color: TrainColors.ember,
                  emphasis: true,
                  onTap: () => _activate(context),
                )
              else
                _QuietAction(
                  actionKey: Key('archive-${plan.id}'),
                  label: l(context).plansStopFollowing,
                  onTap: () => _archive(context),
                ),
              const Spacer(),
              IconButton(
                key: Key('delete-${plan.id}'),
                tooltip: l(context).actionDelete,
                onPressed: () => _delete(context),
                icon: Icon(AppIcons.trash, size: 18, color: TrainColors.ink4),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What a plan is FOR, read off what it would do to the user's weight — the
/// same deadband verdict as the outcome line, so the two can never disagree.
/// Plans carry no stored goal; this is derived, and only when body data lets
/// the app compare the plan with maintenance at all.
DietGoal planGoalFor(EnergyDirection direction) => switch (direction) {
  EnergyDirection.losing => DietGoal.fatLoss,
  EnergyDirection.holding => DietGoal.maintain,
  EnergyDirection.gaining => DietGoal.muscleGain,
};

/// How many meals a day the plan usually has — the most common count across
/// its days, supplements excluded. Null for a plan with no meals.
int? typicalMealCount(DietPlan plan) {
  final counts = <int, int>{};
  for (final day in plan.days) {
    final n = regularMeals(day.meals).length;
    if (n > 0) counts[n] = (counts[n] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return counts.entries
      .reduce((a, b) => b.value > a.value ||
              (b.value == a.value && b.key > a.key)
          ? b
          : a)
      .key;
}

/// Where a plan stands, as a word rather than a colour alone.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final DietPlanStatus status;

  @override
  Widget build(BuildContext context) {
    // Green is state in this app, and "in force" is a state. Everything else
    // is quiet — an archived plan isn't a warning.
    final active = status == DietPlanStatus.active;
    final color = active ? TrainColors.green : TrainColors.ink4;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(switch (status) {
        DietPlanStatus.active => l(context).dietFollowingCaps,
        DietPlanStatus.archived => l(context).dietArchivedCaps,
        DietPlanStatus.draft => l(context).dietDraftCaps,
      }, style: TrainType.caption(size: 8.5, tracking: 0.14, color: color)),
    );
  }
}

/// A secondary, text-weight action — the identity keeps the filled pill for
/// the one committing action per row.
class _QuietAction extends StatelessWidget {
  const _QuietAction({
    required this.actionKey,
    required this.label,
    required this.onTap,
    this.color,
    this.emphasis = false,
  });

  final Key actionKey;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  /// The card's one committing action (Follow) — same weight as its quiet
  /// neighbours, told apart by ember and a semibold label, not by size.
  final bool emphasis;

  @override
  Widget build(BuildContext context) => TextButton(
    key: actionKey,
    onPressed: onTap,
    style: TextButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: AlignmentDirectional.centerStart,
    ),
    child: Text(
      label,
      style: AppText.meta.copyWith(
        color: color ?? TrainColors.ink2,
        fontWeight: emphasis ? FontWeight.w600 : null,
      ),
    ),
  );
}
