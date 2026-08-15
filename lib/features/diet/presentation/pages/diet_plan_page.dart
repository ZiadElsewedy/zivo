import 'package:flutter/material.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/diet_day.dart';
import '../../domain/diet_format.dart';
import '../../domain/diet_plan.dart';
import '../../domain/meal.dart';
import '../today_diet.dart';
import 'diet_plan_edit_page.dart';

/// The Diet Plan page — today's meals with an eaten checkbox, a running
/// "meals eaten · kcal left" summary, and the full week browsable below. A
/// Pulse surface, Diet's sibling hue to Workout.
class DietPlanPage extends StatelessWidget {
  const DietPlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final diet = AppScope.of(context).diet;
    return StreamBuilder<DietPlan?>(
      stream: diet.watchActivePlan(),
      initialData: diet.activePlan,
      builder: (context, planSnapshot) {
        final plan = planSnapshot.data;
        return Scaffold(
          backgroundColor: AppColors.ground,
          appBar: AppBar(
            backgroundColor: AppColors.ground,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            title: Text('Diet', style: AppText.cardTitle),
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: AppColors.pulseText,
            elevation: 2,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DietPlanEditPage(initialPlan: plan)),
            ),
            child: const Icon(Icons.edit_rounded, color: Colors.white),
          ),
          body: plan == null
              ? _EmptyState(
                  onCreate: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const DietPlanEditPage())),
                )
              : _PlanBody(plan: plan),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.restaurant_rounded, size: 30, color: AppColors.ink3),
          const SizedBox(height: 12),
          Text('No diet plan yet.', style: AppText.aside),
          const SizedBox(height: 18),
          SizedBox(
            width: 200,
            child: PillButton(
              label: 'Create plan',
              icon: Icons.add_rounded,
              color: AppColors.pulseText,
              enabled: true,
              onTap: onCreate,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.plan});

  final DietPlan plan;

  @override
  Widget build(BuildContext context) {
    final diet = AppScope.of(context).diet;
    final now = DateTime.now();
    final today = dayForDate(plan, now);
    return StreamBuilder<Set<String>>(
      stream: diet.watchConsumed(now),
      initialData: const <String>{},
      builder: (context, consumedSnapshot) {
        final consumed = consumedSnapshot.data ?? const <String>{};
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 110),
          children: [
            Text(plan.name, style: AppText.rowTitle.copyWith(color: AppColors.ink2)),
            const SizedBox(height: 18),
            if (today == null)
              Text('No plan for today.', style: AppText.aside)
            else ...[
              _TodayHeader(day: today),
              const SizedBox(height: 12),
              for (final meal in [...today.meals]..sort((a, b) => a.order.compareTo(b.order)))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MealCard(
                    meal: meal,
                    eaten: consumed.contains(meal.id),
                    onToggle: () => diet.setMealEaten(
                      mealId: meal.id,
                      day: now,
                      eaten: !consumed.contains(meal.id),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              _SummaryLine(day: today, consumed: consumed),
            ],
            const SizedBox(height: 30),
            Text(
              'Full plan',
              style: AppText.meta.copyWith(color: AppColors.pulseText, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            for (final day in plan.days)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: _DaySummaryCard(day: day)),
          ],
        );
      },
    );
  }
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({required this.day});

  final DietDay day;

  @override
  Widget build(BuildContext context) {
    final kcal = dayCalories(day);
    final parts = ['Today', day.label, if (kcal != null) '$kcal kcal'];
    return Text(
      parts.join(' · '),
      style: AppText.cardTitle.copyWith(fontSize: 20),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.eaten, required this.onToggle});

  final Meal meal;
  final bool eaten;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final kcal = mealCalories(meal);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CheckBox(checked: eaten),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meal.label,
                          style: AppText.rowTitle.copyWith(
                            fontWeight: FontWeight.w600,
                            color: eaten ? AppColors.ink3 : AppColors.ink,
                            decoration: eaten ? TextDecoration.lineThrough : TextDecoration.none,
                            decorationColor: AppColors.ink3,
                          ),
                        ),
                      ),
                      if (kcal != null)
                        Text('$kcal kcal', style: AppText.meta.copyWith(color: AppColors.pulseText)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final item in meal.items)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body.copyWith(fontSize: 14, color: AppColors.ink2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            [foodQtyLabel(item), ?macroLabel(item)].join(' · '),
                            style: AppText.meta.copyWith(color: AppColors.ink3, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: checked ? AppColors.pulse : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: checked ? AppColors.pulse : AppColors.hairline2, width: 1.6),
      ),
      child: checked ? const Icon(Icons.check_rounded, size: 13, color: Colors.white) : null,
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.day, required this.consumed});

  final DietDay day;
  final Set<String> consumed;

  @override
  Widget build(BuildContext context) {
    final total = day.meals.length;
    final eatenCount = day.meals.where((m) => consumed.contains(m.id)).length;
    final kcalLeft = day.meals
        .where((m) => !consumed.contains(m.id))
        .map(mealCalories)
        .whereType<int>()
        .fold<int>(0, (sum, c) => sum + c);
    return Text(
      '$eatenCount of $total meals eaten · $kcalLeft kcal left',
      style: AppText.meta.copyWith(color: AppColors.ink2),
    );
  }
}

class _DaySummaryCard extends StatelessWidget {
  const _DaySummaryCard({required this.day});

  final DietDay day;

  @override
  Widget build(BuildContext context) {
    final kcal = dayCalories(day);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(day.label, style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (kcal != null)
                Text('$kcal kcal', style: AppText.meta.copyWith(color: AppColors.pulseText)),
            ],
          ),
          const SizedBox(height: 6),
          for (final meal in [...day.meals]..sort((a, b) => a.order.compareTo(b.order)))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${meal.label}: ${meal.items.map((i) => i.name).join(', ')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.meta.copyWith(color: AppColors.ink2),
              ),
            ),
        ],
      ),
    );
  }
}
