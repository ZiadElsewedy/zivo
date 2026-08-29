import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/back_chip.dart';
import '../../domain/diet_format.dart';
import '../../domain/food_item.dart';
import '../../domain/meal.dart';
import '../../../../core/theme/train_tokens.dart';

/// The dedicated view behind a meal card's "View" affordance — everything
/// IN the meal, and nothing else: its items with quantities, calories and
/// macros, the meal's totals, and one big Done/Undo action. The plan page
/// stays a clean list; the detail lives here.
///
/// Subscribes to the day's consumed set itself, so toggling from either
/// surface (card or here) keeps both in sync live.
class MealDetailPage extends StatelessWidget {
  const MealDetailPage({
    super.key,
    required this.meal,
    required this.isSupplement,
  });

  final Meal meal;

  /// Supplements get their own hue treatment so the two never blur together.
  final bool isSupplement;

  @override
  Widget build(BuildContext context) {
    final diet = AppScope.of(context).diet;
    final now = DateTime.now();
    final accent = isSupplement ? TrainColors.amber : TrainColors.green;
    return Scaffold(
      backgroundColor: TrainColors.base,
      appBar: AppBar(
        backgroundColor: TrainColors.base,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 56,
        leading: const BackChip(),
        title: Text(meal.label, style: AppText.cardTitle),
      ),
      body: StreamBuilder<Set<String>>(
        stream: diet.watchConsumed(now),
        initialData: const <String>{},
        builder: (context, snapshot) {
          final eaten = (snapshot.data ?? const <String>{}).contains(meal.id);
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
            children: [
              _MealTotalsCard(
                meal: meal,
                eaten: eaten,
                accent: accent,
                isSupplement: isSupplement,
              ),
              const SizedBox(height: 22),
              Text(
                'What\u2019s in it',
                style: AppText.meta.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              for (final item in meal.items)
                _ItemRow(item: item, accent: accent),
              if (meal.items.isEmpty)
                Text(
                  'No items listed for this meal.',
                  style: AppText.body.copyWith(color: TrainColors.ink3),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The detail hero: totals + the single Done/Undo action.
class _MealTotalsCard extends StatefulWidget {
  const _MealTotalsCard({
    required this.meal,
    required this.eaten,
    required this.accent,
    required this.isSupplement,
  });

  final Meal meal;
  final bool eaten;
  final Color accent;
  final bool isSupplement;

  @override
  State<_MealTotalsCard> createState() => _MealTotalsCardState();
}

class _MealTotalsCardState extends State<_MealTotalsCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    value: widget.eaten ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _MealTotalsCard oldWidget) {
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

  void _toggle() {
    HapticFeedback.mediumImpact();
    AppScope.of(context).diet.setMealEaten(
      mealId: widget.meal.id,
      day: DateTime.now(),
      eaten: !widget.eaten,
    );
  }

  @override
  Widget build(BuildContext context) {
    final kcal = mealCalories(widget.meal);
    final macros = macroTotals(widget.meal.items);
    final hasEstimate = widget.meal.items.any((i) => i.estimated);
    final tc = _t.value.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TrainColors.raised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: Color.lerp(
            TrainColors.hairline,
            widget.isSupplement ? TrainColors.amber : TrainColors.green,
            tc,
          )!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.meal.items.length} '
                  'item${widget.meal.items.length == 1 ? '' : 's'}'
                  '${kcal != null ? '${hasEstimate ? ' · ~' : ' · '}$kcal kcal' : ''}',
                  style: AppText.rowTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: TrainColors.ink,
                  ),
                ),
              ),
              if (macros.proteinG != null)
                _Macro(label: 'P', value: '${macros.proteinG!.round()}g'),
              if (macros.carbsG != null) ...[
                const SizedBox(width: 12),
                _Macro(label: 'C', value: '${macros.carbsG!.round()}g'),
              ],
              if (macros.fatG != null) ...[
                const SizedBox(width: 12),
                _Macro(label: 'F', value: '${macros.fatG!.round()}g'),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: widget.eaten
                  ? TrainColors.raisedStrong
                  : (widget.isSupplement
                        ? TrainColors.amberWash
                        : TrainColors.greenWash),
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                onTap: _toggle,
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: reducedMotion(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          child: Icon(
                            widget.eaten
                                ? Icons.undo_rounded
                                : Icons.check_rounded,
                            key: ValueKey(widget.eaten),
                            size: 17,
                            color: widget.eaten
                                ? TrainColors.ink2
                                : widget.accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.eaten
                              ? 'Mark as not eaten'
                              : 'Done — mark as eaten',
                          style: AppText.button.copyWith(
                            color: widget.eaten
                                ? TrainColors.ink2
                                : widget.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Macro extends StatelessWidget {
  const _Macro({required this.label, required this.value});

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
              color: TrainColors.ink2,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: value,
            style: AppText.meta.copyWith(color: TrainColors.ink3),
          ),
        ],
      ),
    );
  }
}

/// One food item, full width: name on top, quantity · kcal · macros beneath.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.accent});

  final FoodItem item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: TrainColors.raised.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.chip * 2),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: AppText.rowTitle.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: TrainColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [foodQtyLabel(item), ?macroLabel(item)].join('  ·  '),
                  style: AppText.meta.copyWith(
                    color: TrainColors.ink3,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (item.calories != null)
            Text(
              '${item.estimated ? '~' : ''}${item.calories}',
              style: AppText.rowTitle.copyWith(fontSize: 13.5, color: accent),
            ),
        ],
      ),
    );
  }
}
