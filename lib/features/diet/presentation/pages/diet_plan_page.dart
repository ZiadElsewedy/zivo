import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/back_chip.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/reactive_state_views.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/diet_day.dart';
import '../../domain/diet_format.dart';
import '../../domain/diet_plan.dart';
import '../../domain/diet_summary.dart';
import '../../domain/meal.dart';
import '../today_diet.dart';
import 'diet_pdf_import_page.dart';
import 'diet_plan_edit_page.dart';
import 'grocery_list_page.dart';
import 'meal_detail_page.dart';

/// The Diet Plan page — today's meals as tactile completion cards under a
/// calorie-ring hero summary, and the full week browsable below. A Pulse
/// surface, Diet's sibling hue to Workout.
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
        final loading =
            plan == null &&
            planSnapshot.connectionState == ConnectionState.waiting;
        return Scaffold(
          backgroundColor: AppColors.ground,
          appBar: AppBar(
            backgroundColor: AppColors.ground,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            // Pushed from the Hub — the house back chip, matching Workout.
            automaticallyImplyLeading: false,
            leadingWidth: 56,
            leading: const BackChip(),
            title: Text('Diet', style: AppText.cardTitle),
            actions: [
              if (plan != null && !planSnapshot.hasError)
                IconButton(
                  tooltip: 'Groceries',
                  icon: const Icon(Icons.shopping_basket_rounded),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroceryListPage(plan: plan),
                    ),
                  ),
                ),
            ],
          ),
          floatingActionButton: loading || planSnapshot.hasError
              ? null
              : FloatingActionButton(
                  backgroundColor: AppColors.pulseText,
                  elevation: 2,
                  tooltip: plan == null ? 'Create plan' : 'Edit plan',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DietPlanEditPage(initialPlan: plan),
                    ),
                  ),
                  child: const Icon(Icons.edit_rounded, color: Colors.white),
                ),
          body: planSnapshot.hasError
              ? const ErrorStateView()
              : loading
              ? const LoadingStateView()
              : plan == null
              ? _EmptyState(
                  onImport: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DietPdfImportPage(),
                    ),
                  ),
                  onCreate: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DietPlanEditPage()),
                  ),
                )
              : _PlanBody(plan: plan),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport, required this.onCreate});

  final VoidCallback onImport;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.restaurant_rounded,
              size: 30,
              color: AppColors.ink3,
            ),
            const SizedBox(height: 12),
            Text('No diet plan yet.', style: AppText.aside),
            const SizedBox(height: 6),
            Text(
              "Import a PDF or photo and I'll estimate calories and macros "
              'for you, or build one from scratch.',
              style: AppText.meta.copyWith(color: AppColors.ink3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 220,
              child: PillButton(
                label: 'Import a plan',
                icon: Icons.upload_file_rounded,
                color: AppColors.pulseText,
                enabled: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onImport();
                },
              ),
            ),
            const SizedBox(height: 10),
            PressableScale(
              child: TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onCreate();
                },
                child: Text(
                  'Create plan manually instead',
                  style: AppText.meta.copyWith(color: AppColors.ink2),
                ),
              ),
            ),
          ],
        ),
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
        final consumedLoading =
            consumedSnapshot.connectionState == ConnectionState.waiting;
        return ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 110),
          children: [
            Text(
              plan.name,
              style: AppText.rowTitle.copyWith(color: AppColors.ink2),
            ),
            const SizedBox(height: 18),
            if (today == null)
              Text('No plan for today.', style: AppText.aside)
            else ...[
              _DietHero(
                day: today,
                consumed: consumed,
                loading: consumedLoading,
              ),
              const SizedBox(height: 14),
              // Real meals only — the supplements block renders separately
              // below, so "Meal 1..N" stays about food.
              for (final meal in [
                ...regularMeals(today.meals),
              ]..sort((a, b) => a.order.compareTo(b.order)))
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
              // Supplements are NOT meals: their own quiet checklist, their
              // own hue, zero influence on meal counts or kcal left.
              if (supplementMeals(today.meals).isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Supplements',
                  style: AppText.meta.copyWith(
                    color: AppColors.solarText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                for (final meal in [
                  ...supplementMeals(today.meals),
                ]..sort((a, b) => a.order.compareTo(b.order)))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SupplementCard(
                      meal: meal,
                      taken: consumed.contains(meal.id),
                      onToggle: () => diet.setMealEaten(
                        mealId: meal.id,
                        day: now,
                        eaten: !consumed.contains(meal.id),
                      ),
                    ),
                  ),
              ],
            ],
            const SizedBox(height: 30),
            Text(
              'Full plan',
              style: AppText.meta.copyWith(
                color: AppColors.pulseText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            for (final day in plan.days)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DaySummaryCard(day: day),
              ),
          ],
        );
      },
    );
  }
}

/// The Diet Today hero: a calorie-ring progress readout (kcal eaten vs the
/// day's planned total), meals-eaten count, and consumed/target macro chips.
/// Degrades calmly when the plan carries no calorie or macro data yet — see
/// [dayCalories]/[macroTotals]'s null-means-absent semantics.
class _DietHero extends StatefulWidget {
  const _DietHero({
    required this.day,
    required this.consumed,
    required this.loading,
  });

  final DietDay day;
  final Set<String> consumed;
  final bool loading;

  @override
  State<_DietHero> createState() => _DietHeroState();
}

class _DietHeroState extends State<_DietHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    value: _target(),
  );

  double _target() {
    final total = dayCalories(widget.day);
    if (total == null || total <= 0) return 0;
    final kcalLeft = dietDaySummary(widget.day, widget.consumed).kcalLeft;
    return ((total - kcalLeft) / total).clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(covariant _DietHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _target();
    if ((target - _progress.value).abs() < 0.0005) return;
    if (reducedMotion(context)) {
      _progress.value = target;
    } else {
      _progress.springTo(target, spring: AppSprings.standard);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final totalKcal = dayCalories(day);
    final summary = dietDaySummary(day, widget.consumed);
    final targetMacros = macroTotals(day.meals.expand((m) => m.items));
    final consumedMacros = macroTotals(
      day.meals
          .where((m) => widget.consumed.contains(m.id))
          .expand((m) => m.items),
    );
    final hasMacros =
        targetMacros.proteinG != null ||
        targetMacros.carbsG != null ||
        targetMacros.fatG != null;

    // While consumption is still loading, don't state an eaten count/macro
    // split that might be wrong the moment it resolves.
    String consumedGrams(double? v) =>
        widget.loading ? '–' : '${(v ?? 0).round()}';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (totalKcal != null) ...[
            SizedBox(
              width: 84,
              height: 84,
              child: AnimatedBuilder(
                animation: _progress,
                builder: (context, _) => Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(84, 84),
                      painter: _CalorieRingPainter(progress: _progress.value),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.loading ? '…' : '${summary.kcalLeft}',
                          style: AppText.heroNumber.copyWith(
                            fontSize: 20,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          'kcal left',
                          style: AppText.meta.copyWith(
                            fontSize: 10,
                            color: AppColors.ink3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.loading
                      ? 'Today'
                      : '${summary.eaten} of ${summary.total} meals eaten',
                  style: AppText.rowTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (totalKcal == null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'No calorie data yet',
                    style: AppText.meta.copyWith(color: AppColors.ink3),
                  ),
                ],
                if (hasMacros) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      if (targetMacros.proteinG != null)
                        _MacroChip(
                          label: 'P',
                          value:
                              '${consumedGrams(consumedMacros.proteinG)}/${targetMacros.proteinG!.round()}g',
                        ),
                      if (targetMacros.carbsG != null)
                        _MacroChip(
                          label: 'C',
                          value:
                              '${consumedGrams(consumedMacros.carbsG)}/${targetMacros.carbsG!.round()}g',
                        ),
                      if (targetMacros.fatG != null)
                        _MacroChip(
                          label: 'F',
                          value:
                              '${consumedGrams(consumedMacros.fatG)}/${targetMacros.fatG!.round()}g',
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CalorieRingPainter extends CustomPainter {
  const _CalorieRingPainter({required this.progress});

  /// 0.0 = no calories eaten yet, 1.0 = the day's planned total is eaten.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 5;
    final track = Paint()
      ..color = AppColors.hairline2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;
    final sweep = Paint()
      ..color = AppColors.pulse
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * clamped,
      false,
      sweep,
    );
  }

  @override
  bool shouldRepaint(covariant _CalorieRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// A meal card kept deliberately CLEAN: completion state, name, kcal, macro
/// chips and a "View" affordance — nothing else. The item-by-item breakdown
/// lives in [MealDetailPage] (opened by View), not on the plan screen.
/// Tapping the card body toggles eaten, as before.
class _MealCard extends StatefulWidget {
  const _MealCard({
    required this.meal,
    required this.eaten,
    required this.onToggle,
  });

  final Meal meal;
  final bool eaten;
  final VoidCallback onToggle;

  @override
  State<_MealCard> createState() => _MealCardState();
}

class _MealCardState extends State<_MealCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    value: widget.eaten ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _MealCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eaten == widget.eaten) return;
    final target = widget.eaten ? 1.0 : 0.0;
    if (reducedMotion(context)) {
      _t.value = target;
      return;
    }
    _t.springTo(
      target,
      spring: widget.eaten ? AppSprings.bounce : AppSprings.standard,
    );
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.eaten) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    widget.onToggle();
  }

  void _openDetail() {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealDetailPage(meal: widget.meal, isSupplement: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meal = widget.meal;
    final kcal = mealCalories(meal);
    final macros = kcal == null ? null : macroTotals(meal.items);
    // AI-imported items that weren't in the source's stated numbers carry a
    // "~" onto the meal's total — the whole point of estimation is visible
    // here, not buried in the edit screen only.
    final hasEstimate = meal.items.any((i) => i.estimated);
    return PressableScale(
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final tc = _t.value.clamp(0.0, 1.0);
          return InkWell(
            onTap: _handleTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Color.lerp(AppColors.hairline, AppColors.pulse, tc)!,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: tc,
                        child: const ColoredBox(color: AppColors.pulseWash),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          _CompletionMark(t: _t.value),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  meal.label,
                                  style: AppText.rowTitle.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  [
                                    '${meal.items.length} '
                                        'item${meal.items.length == 1 ? '' : 's'}',
                                    if (kcal != null)
                                      '${hasEstimate ? '~' : ''}$kcal kcal',
                                  ].join(' · '),
                                  style: AppText.meta.copyWith(
                                    color: AppColors.ink3,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (macros != null &&
                              macros.proteinG != null) ...[
                            const SizedBox(width: 8),
                            _MacroChip(
                              label: 'P',
                              value:
                                  '${macros.proteinG!.round()}g',
                            ),
                          ],
                          const SizedBox(width: 6),
                          // The dedicated view affordance — one tap opens
                          // exactly what's inside this meal and nothing else.
                          PressableScale(
                            child: Material(
                              color: AppColors.surfaceRaised,
                              borderRadius: BorderRadius.circular(999),
                              child: InkWell(
                                onTap: _openDetail,
                                borderRadius: BorderRadius.circular(999),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 7, 10, 7),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'View',
                                        style: AppText.meta.copyWith(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.pulseText,
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 15,
                                        color: AppColors.pulseText,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One supplement entry — compact checkable row in its own solar-hued block,
/// visually distinct from meals by design (they are not food).
class _SupplementCard extends StatelessWidget {
  const _SupplementCard({
    required this.meal,
    required this.taken,
    required this.onToggle,
  });

  final Meal meal;
  final bool taken;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: AppColors.card.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onToggle();
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: taken
                    ? AppColors.solar.withValues(alpha: 0.4)
                    : AppColors.hairline,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: reducedMotion(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: taken ? AppColors.solar : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: taken ? AppColors.solar : AppColors.hairline2,
                      width: 1.6,
                    ),
                  ),
                  child: taken
                      ? const Icon(Icons.check_rounded,
                          size: 13, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    meal.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: taken ? AppColors.ink3 : AppColors.ink,
                      decoration:
                          taken ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (meal.items.length > 1) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${meal.items.length} items',
                    style: AppText.meta.copyWith(
                      fontSize: 11.5,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'View details',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MealDetailPage(
                        meal: meal,
                        isSupplement: true,
                      ),
                    ),
                  ),
                  icon: const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.ink3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The meal card's completion dot: fill/border lerp hairline→pulse, and the
/// check draws in at the raw (unclamped) spring value so the one earned
/// overshoot on completion reads as a small pop — same idea as the workout
/// session's completion checkmark.
class _CompletionMark extends StatelessWidget {
  const _CompletionMark({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final tc = t.clamp(0.0, 1.0);
    return Container(
      width: 20,
      height: 20,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: Color.lerp(Colors.transparent, AppColors.pulse, tc),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: Color.lerp(AppColors.hairline2, AppColors.pulse, tc)!,
          width: 1.6,
        ),
      ),
      child: tc > 0.01
          ? Center(
              child: Transform.scale(
                scale: t,
                child: Opacity(
                  opacity: tc,
                  child: const Icon(
                    Icons.check_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

/// A neutral typographic macro readout — "P 42/120g" — no per-macro color;
/// ZIVO's hues each carry one life-domain meaning, so protein/carbs/fat stay
/// ink2 label / ink3 value and let the letters carry the distinction.
class _MacroChip extends StatelessWidget {
  const _MacroChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: AppText.meta.copyWith(
              color: AppColors.ink2,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: value,
            style: AppText.meta.copyWith(color: AppColors.ink3),
          ),
        ],
      ),
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
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  day.label,
                  style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (kcal != null)
                Text(
                  '$kcal kcal',
                  style: AppText.meta.copyWith(color: AppColors.pulseText),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final meal in [
            ...day.meals,
          ]..sort((a, b) => a.order.compareTo(b.order)))
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
