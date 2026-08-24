import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
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
            title: Text('Diet', style: AppText.cardTitle),
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
              "Import a PDF and I'll estimate calories and macros for you, "
              'or build one from scratch.',
              style: AppText.meta.copyWith(color: AppColors.ink3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 220,
              child: PillButton(
                label: 'Import from PDF',
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
              for (final meal in [
                ...today.meals,
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

/// A meal card whose eaten/un-eaten states are two designed treatments, not
/// text decoration: completing fills the card with a pulse wash, draws in a
/// check, and springs with the one earned overshoot on this surface — same
/// rule as a workout set chip completing. Un-completing reverses smoothly,
/// no overshoot.
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
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _CompletionMark(t: _t.value),
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
                                          color: AppColors.ink,
                                        ),
                                      ),
                                    ),
                                    ClipRect(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: tc,
                                        child: Opacity(
                                          opacity: tc,
                                          child: const _DonePill(),
                                        ),
                                      ),
                                    ),
                                    if (kcal != null) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '${hasEstimate ? '~' : ''}$kcal kcal',
                                        style: AppText.meta.copyWith(
                                          color: AppColors.pulseText,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (macros != null &&
                                    (macros.proteinG != null ||
                                        macros.carbsG != null ||
                                        macros.fatG != null)) ...[
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 2,
                                    children: [
                                      if (macros.proteinG != null)
                                        _MacroChip(
                                          label: 'P',
                                          value: '${macros.proteinG!.round()}g',
                                        ),
                                      if (macros.carbsG != null)
                                        _MacroChip(
                                          label: 'C',
                                          value: '${macros.carbsG!.round()}g',
                                        ),
                                      if (macros.fatG != null)
                                        _MacroChip(
                                          label: 'F',
                                          value: '${macros.fatG!.round()}g',
                                        ),
                                    ],
                                  ),
                                ],
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
                                            style: AppText.body.copyWith(
                                              fontSize: 14,
                                              color: AppColors.ink2,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          [
                                            foodQtyLabel(item),
                                            ?macroLabel(item),
                                          ].join(' · '),
                                          style: AppText.meta.copyWith(
                                            color: AppColors.ink3,
                                            fontSize: 12,
                                          ),
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

class _DonePill extends StatelessWidget {
  const _DonePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.pulseWash,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'Done',
        style: AppText.meta.copyWith(
          color: AppColors.pulseText,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
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
