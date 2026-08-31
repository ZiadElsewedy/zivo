import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/analysis/plan_verdict.dart';
import '../../domain/body_measures.dart';
import '../../domain/diet_format.dart';
import '../../domain/diet_plan.dart';
import '../../domain/diet_plan_status.dart';
import '../../domain/diet_source.dart';
import '../widgets/body_measures_builder.dart';
import '../widgets/add_diet_sheet.dart';

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
        semanticLabel: 'Add a diet',
        onTap: () => showAddDietSheet(context),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 12, 22, 0),
            child: TrainPageHeader(title: 'Your plans'),
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
                            ? 'One plan. Import or write another and you can '
                                  'switch between them without losing either.'
                            : '${plans.length} plans. One is in force at a '
                                  'time — the Diet screen always shows that '
                                  'one.',
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
        'No plans yet.',
        key: const Key('plans-empty'),
        style: AppText.aside,
        textAlign: TextAlign.center,
      ),
    ),
  );
}

/// One plan in the library: what it is, what it adds up to, what it would do
/// to the user, and the two things they can do with it.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.measures});

  final DietPlan plan;

  /// Null when body data is incomplete — the card then simply doesn't carry a
  /// verdict line, rather than showing a guessed one. The Diet screen is where
  /// the ask for that data lives; repeating it on every card would be nagging.
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: TrainColors.raised,
        title: Text('Delete this plan?', style: AppText.rowTitle),
        content: Text(
          'This removes ${plan.name} for good. Archiving keeps it and takes '
          'it off the Diet screen just the same.',
          style: AppText.meta.copyWith(color: TrainColors.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: AppText.meta.copyWith(color: TrainColors.ink2),
            ),
          ),
          TextButton(
            key: const Key('confirm-delete-plan'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Delete',
              style: AppText.meta.copyWith(color: TrainColors.ember),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await diet.deletePlan(plan.id);
  }

  @override
  Widget build(BuildContext context) {
    final measures = this.measures;
    final verdict = measures == null
        ? null
        : analysePlan(plan: plan, measures: measures);
    final energy = planDailyEnergy(plan);

    return TrainCard(
      key: Key('plan-card-${plan.id}'),
      radius: 20,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TrainType.ui(
                    size: 15.5,
                    weight: FontWeight.w700,
                    color: TrainColors.inkPlain,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _StatusPill(status: plan.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [
              dietSourceLabel(plan.source).toUpperCase(),
              '${plan.days.length} ${plan.days.length == 1 ? "DAY" : "DAYS"}',
              if (energy.kcalPerDay != null)
                '${approx(energy.estimated)}${energy.kcalPerDay} KCAL/DAY',
            ].join(' · '),
            style: TrainType.mono(
              size: 10.5,
              tracking: 0.06,
              color: TrainColors.ink4,
            ),
          ),
          if (verdict != null) ...[
            const SizedBox(height: 8),
            Text(
              verdictHeadline(verdict),
              key: Key('plan-verdict-${plan.id}'),
              style: AppText.meta.copyWith(color: TrainColors.ink2),
            ),
          ],
          const SizedBox(height: 13),
          Row(
            children: [
              if (!_isActive)
                Expanded(
                  child: PillButton(
                    key: Key('activate-${plan.id}'),
                    label: 'Follow this plan',
                    icon: Icons.check_rounded,
                    enabled: true,
                    onTap: () => _activate(context),
                  ),
                )
              else
                Expanded(
                  child: _QuietAction(
                    actionKey: Key('archive-${plan.id}'),
                    label: 'Stop following',
                    onTap: () => _archive(context),
                  ),
                ),
              const SizedBox(width: 8),
              _QuietAction(
                actionKey: Key('delete-${plan.id}'),
                label: 'Delete',
                color: TrainColors.ember,
                onTap: () => _delete(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
        DietPlanStatus.active => 'FOLLOWING',
        DietPlanStatus.archived => 'ARCHIVED',
        DietPlanStatus.draft => 'DRAFT',
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
  });

  final Key actionKey;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => TextButton(
    key: actionKey,
    onPressed: onTap,
    style: TextButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14),
    ),
    child: Text(
      label,
      style: AppText.meta.copyWith(color: color ?? TrainColors.ink2),
    ),
  );
}
