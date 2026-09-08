import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/util/bidi.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/diet_format.dart';
import '../../domain/food_item.dart';
import '../../domain/meal.dart';

/// The dedicated view behind a meal card's "View" affordance — everything
/// IN the meal, and nothing else: its items with quantities, calories and
/// macros, the meal's totals, and one big Done/Undo action.
///
/// Subscribes to the day's consumed set itself, so toggling from either
/// surface (card or here) keeps both in sync live.
///
/// ## Why the page looks the way it does
///
/// It used to be the one diet screen on a Material `AppBar` over the bare
/// base — no screen wash, a 24px title where its siblings run 27, and its
/// items drawn as one floating rounded card each. Three drills into the same
/// feature, three different dresses. It is on [TrainScreen] +
/// [TrainPageHeader] now, the items are rows of a single hairline card, and
/// the meal's calories are the screen's **one hero number** with everything
/// else demoted to a mono caption under it — the house rule the rest of the
/// app already follows.
///
/// Supplements used to tint this page **amber**, which is money's hue and
/// nothing else's (ADR-006). Worse, it disagreed with the row you tapped to
/// get here: the supplement list on the Diet screen ticks *green*. Both
/// surfaces read green now, and "this is not food" is carried by the label
/// instead of by a hue that already means something.
class MealDetailPage extends StatelessWidget {
  const MealDetailPage({
    super.key,
    required this.meal,
    required this.isSupplement,
  });

  final Meal meal;

  /// Supplements say so in words. Kept as a parameter because the caller
  /// knows which list the meal came out of and the meal itself does not.
  final bool isSupplement;

  @override
  Widget build(BuildContext context) {
    final diet = AppScope.of(context).diet;
    final now = DateTime.now();
    return TrainScreen(
      tint: TrainColors.dietTint,
      child: StreamBuilder<Set<String>>(
        stream: diet.watchConsumed(now),
        initialData: const <String>{},
        builder: (context, snapshot) {
          final eaten = (snapshot.data ?? const <String>{}).contains(meal.id);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  12,
                  AppSpacing.screen,
                  0,
                ),
                child: TrainPageHeader(title: isolate(meal.label)),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    18,
                    AppSpacing.screen,
                    AppSpacing.s,
                  ),
                  children: [
                    _Totals(meal: meal, isSupplement: isSupplement),
                    const SizedBox(height: AppSpacing.l),
                    TrainSectionLabel(
                      l(context).dietWhatsInIt,
                      trailing: meal.items.isEmpty
                          ? null
                          : ltrFor(
                              context,
                              l(context).dietItemCount(meal.items.length),
                            ),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    if (meal.items.isEmpty)
                      Text(
                        l(context).dietNoItemsListed,
                        style: AppText.body.copyWith(color: TrainColors.ink3),
                      )
                    else
                      TrainListCard(
                        rows: [
                          for (final item in meal.items) _ItemRow(item: item),
                        ],
                      ),
                  ],
                ),
              ),
              _ActionDock(meal: meal, eaten: eaten),
            ],
          );
        },
      ),
    );
  }
}

/// The hero band: the meal's calories at hero scale, its macros beneath a
/// hairline. One number carries the screen; the macros are its footnote, not
/// a second headline (identity §5).
class _Totals extends StatelessWidget {
  const _Totals({required this.meal, required this.isSupplement});

  final Meal meal;
  final bool isSupplement;

  @override
  Widget build(BuildContext context) {
    final strings = l(context);
    final kcal = mealCalories(meal);
    final macros = macroTotals(meal.items);
    final estimated = meal.items.any((i) => i.estimated);
    final stats = <TrainStat>[
      if (macros.proteinG != null)
        TrainStat(
          strings.dietGramsValue(macros.proteinG!.round()),
          strings.dietMacroP,
        ),
      if (macros.carbsG != null)
        TrainStat(
          strings.dietGramsValue(macros.carbsG!.round()),
          strings.dietMacroC,
        ),
      if (macros.fatG != null)
        TrainStat(
          strings.dietGramsValue(macros.fatG!.round()),
          strings.dietMacroF,
        ),
    ];

    return TrainCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // The estimate tilde rides with the figure and at the figure's
              // dim, so "about" is legible without stealing the number's
              // weight.
              if (kcal != null && estimated)
                Text(
                  '~',
                  style: TrainType.mono(
                    size: 34,
                    weight: FontWeight.w300,
                    color: TrainColors.ink4,
                    height: 1,
                  ),
                ),
              Text(
                kcal?.toString() ?? '—',
                style: TrainType.mono(
                  size: 46,
                  weight: FontWeight.w300,
                  tracking: -0.04,
                  color: TrainColors.ink,
                  height: 1,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                strings.unitKcal,
                style: TrainType.mono(
                  size: 13,
                  weight: FontWeight.w500,
                  color: TrainColors.ink4,
                  height: 1,
                ),
              ),
              const Spacer(),
              if (isSupplement)
                Text(
                  strings.dietSupplementMark.toUpperCase(),
                  style: TrainType.caption(
                    size: 9.5,
                    tracking: 0.2,
                    color: TrainColors.ink4,
                  ),
                ),
            ],
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(height: 1, thickness: 1, color: TrainColors.hairline),
            const SizedBox(height: 14),
            TrainStatStrip(items: stats, valueSize: 17),
          ],
        ],
      ),
    );
  }
}

/// One food item as a row of the items card: name on top, quantity · macros
/// beneath, calories on the right.
///
/// This used to be its own bordered, rounded, tinted card — so a five-item
/// meal was five stacked cards saying nothing five times. A meal's items are
/// one list, and a list is one card.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final FoodItem item;

  @override
  Widget build(BuildContext context) {
    final detail = [foodQtyLabel(item), ?macroLabel(item)].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isolate(item.name),
                  style: TrainType.ui(
                    size: 15,
                    weight: FontWeight.w600,
                    color: TrainColors.inkPlain,
                    height: 1.25,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    ltrFor(context, detail),
                    style: TrainType.mono(
                      size: 11.5,
                      weight: FontWeight.w400,
                      color: TrainColors.ink4,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (item.calories != null) ...[
            const SizedBox(width: 12),
            Padding(
              // Optically aligns the figure with the name's cap height rather
              // than with the top of its line box.
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                ltrFor(
                  context,
                  '${item.estimated ? '~' : ''}${item.calories}',
                ),
                style: TrainType.mono(
                  size: 13,
                  weight: FontWeight.w500,
                  color: TrainColors.ink2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The one committing action on this screen, docked below the list.
///
/// It used to sit inside the totals card at the top, which put the screen's
/// only control at the furthest point from the thumb and made the card do two
/// jobs. Docking it is the same call the Sleep page made, for the same reason.
class _ActionDock extends StatefulWidget {
  const _ActionDock({required this.meal, required this.eaten});

  final Meal meal;
  final bool eaten;

  @override
  State<_ActionDock> createState() => _ActionDockState();
}

class _ActionDockState extends State<_ActionDock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    value: widget.eaten ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _ActionDock oldWidget) {
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
    final strings = l(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.base,
        AppSpacing.screen,
        TrainBottomInset.of(context),
      ),
      decoration: BoxDecoration(
        // The list scrolls under the dock; the scrim keeps a row of text from
        // ending mid-fade against the pill.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00080908), TrainColors.base, TrainColors.base],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          // Undo is not a commit, so it drops to the ghost pill rather than
          // staying a filled green one. The spring drives the crossfade so the
          // two states read as one control changing, not two swapping.
          final tc = _t.value.clamp(0.0, 1.0);
          return Stack(
            children: [
              Opacity(
                opacity: 1 - tc,
                child: IgnorePointer(
                  ignoring: widget.eaten,
                  child: TrainPrimaryButton(
                    label: strings.dietMarkEaten,
                    icon: const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Color(0xFF04140D),
                    ),
                    color: TrainColors.green,
                    labelColor: const Color(0xFF04140D),
                    height: 56,
                    onTap: _toggle,
                  ),
                ),
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: tc,
                  child: IgnorePointer(
                    ignoring: !widget.eaten,
                    child: TrainGhostButton(
                      label: strings.dietMarkNotEaten,
                      mono: false,
                      height: 56,
                      icon: Icon(
                        Icons.undo_rounded,
                        size: 17,
                        color: TrainColors.ink2,
                      ),
                      onTap: _toggle,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
