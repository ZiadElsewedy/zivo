import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/motion/springs.dart';
import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/reactive_state_views.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/diet_day.dart';
import '../../domain/diet_format.dart';
import '../../domain/diet_plan.dart';
import '../../domain/diet_goal.dart';
import '../../domain/diet_summary.dart';
import '../../domain/meal.dart';
import '../../domain/nutrition_targets.dart';
import '../../domain/target_progress.dart';
import '../today_diet.dart';
import 'diet_pdf_import_page.dart';
import 'diet_plan_edit_page.dart';
import 'diet_targets_page.dart';
import 'grocery_list_page.dart';
import 'meal_detail_page.dart';

/// The Diet Plan page, built to the design handoff's **Diet** screen (4b):
/// the green screen wash, a hero card whose 104px ring reports **one number**
/// — calories left — with the three macros as bars beneath it rather than
/// three competing fractions, then today's meals as tickable rows, and the
/// full plan as a reference card.
///
/// Ticking a meal recomputes the ring and all three bars live.
///
/// The row's two affordances are deliberately split the way the handoff draws
/// them: the 24px check **ticks the meal**, and the row body **opens the
/// meal**. The old layout gave the body the toggle and hid "open" behind a
/// small View link, which made the most-used action the least visible one.
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
        return TrainScreen(
          tint: TrainColors.dietTint,
          floatingActionButton: loading || planSnapshot.hasError
              ? null
              : TrainFab(
                  icon: plan == null ? Icons.add_rounded : Icons.edit_rounded,
                  semanticLabel: plan == null ? 'Create plan' : 'Edit plan',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DietPlanEditPage(initialPlan: plan),
                    ),
                  ),
                ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                child: TrainPageHeader(
                  title: 'Diet',
                  action: plan == null || planSnapshot.hasError
                      ? null
                      : TrainHeaderAction(
                          icon: Icons.shopping_basket_outlined,
                          semanticLabel: 'Groceries',
                          accent: TrainColors.green,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => GroceryListPage(plan: plan),
                            ),
                          ),
                        ),
                ),
              ),
              Expanded(
                child: planSnapshot.hasError
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
                          MaterialPageRoute(
                            builder: (_) => const DietPlanEditPage(),
                          ),
                        ),
                      )
                    : _PlanBody(plan: plan),
              ),
            ],
          ),
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
              color: TrainColors.ink3,
            ),
            const SizedBox(height: 12),
            Text('No diet plan yet.', style: AppText.aside),
            const SizedBox(height: 6),
            Text(
              "Import a PDF or photo and I'll estimate calories and macros "
              'for you, or build one from scratch.',
              style: AppText.meta.copyWith(color: TrainColors.ink3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 220,
              child: PillButton(
                label: 'Import a plan',
                icon: Icons.upload_file_rounded,
                color: TrainColors.green,
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
                  style: AppText.meta.copyWith(color: TrainColors.ink2),
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
    return StreamBuilder<NutritionTargets?>(
      stream: diet.watchTargets(),
      initialData: diet.currentTargets,
      builder: (context, targetsSnapshot) {
        return _PlanBodyForTargets(
          plan: plan,
          today: today,
          now: now,
          targets: targetsSnapshot.data,
        );
      },
    );
  }
}

/// The plan body once the user's targets are known. Split out so the
/// consumed-stream builder below doesn't nest three deep.
class _PlanBodyForTargets extends StatelessWidget {
  const _PlanBodyForTargets({
    required this.plan,
    required this.today,
    required this.now,
    required this.targets,
  });

  final DietPlan plan;
  final DietDay? today;
  final DateTime now;

  /// Null when the user hasn't set an objective. **Not defaulted** — the
  /// screen says "not set" rather than quietly treating the plan's own total
  /// as a target nobody chose.
  final NutritionTargets? targets;

  @override
  Widget build(BuildContext context) {
    final diet = AppScope.of(context).diet;
    final today = this.today;
    return StreamBuilder<Set<String>>(
      stream: diet.watchConsumed(now),
      initialData: const <String>{},
      builder: (context, consumedSnapshot) {
        final consumed = consumedSnapshot.data ?? const <String>{};
        final consumedLoading =
            consumedSnapshot.connectionState == ConnectionState.waiting;
        final target = today == null ? null : dayCalories(today);
        return ListView(
          padding: EdgeInsets.fromLTRB(
            22,
            14,
            22,
            TrainBottomInset.of(context),
          ),
          children: [
            // The plan's own identity, and what TODAY actually plans — one
            // mono caption, not a card.
            //
            // This used to hide the planned figure whenever the plan's *name*
            // already carried one ("Balanced — 2200 kcal"), to avoid two
            // calorie numbers on one line. But a name's number is free text:
            // it's the whole plan's headline, it can be stale, and it often
            // disagrees with what this particular day sums to — which left the
            // ring counting down "1270 LEFT" against a header that said 2200,
            // with nothing on screen explaining which was which. Two numbers
            // are fine when they're labelled differently; two unlabelled ones
            // are not. So the day's real planned total is always shown, and
            // always says that's what it is.
            Text(
              [
                plan.name.toUpperCase(),
                // Two figures, each labelled — the target the user set, and
                // what this particular day's plan adds up to. They are
                // different things and routinely disagree; an unlabelled pair
                // is what makes a screen unreadable.
                if (targets != null)
                  'TARGET ${targets!.calories} KCAL',
                if (target != null)
                  'PLANNED ${approx(dayEstimated(today!))}$target KCAL',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TrainType.mono(
                size: 11.5,
                tracking: 0.06,
                color: TrainColors.ink3,
              ),
            ),
            const SizedBox(height: 18),
            if (today == null)
              Text(
                'No plan for today.',
                style: TrainType.ui(
                  size: 14,
                  weight: FontWeight.w400,
                  color: TrainColors.ink2,
                ),
              )
            else ...[
              _DietHero(
                day: today,
                consumed: consumed,
                loading: consumedLoading,
                targets: targets,
              ),
              const SizedBox(height: 12),
              if (targets == null)
                _NoTargetCard(
                  onSet: () => _openTargets(context, null),
                )
              else
                _TargetSummaryRow(
                  targets: targets!,
                  onEdit: () => _openTargets(context, targets),
                ),
              const SizedBox(height: 20),
              const TrainSectionLabel('Meals'),
              const SizedBox(height: 11),
              for (final meal in [
                ...regularMeals(today.meals),
              ]..sort((a, b) => a.order.compareTo(b.order)))
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _MealRow(
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
                const SizedBox(height: 15),
                const TrainSectionLabel('Supplements'),
                const SizedBox(height: 11),
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
            const SizedBox(height: 24),
            TrainSectionLabel(
              'Full plan',
              // The day count, not an "EDIT" link: editing is the ember FAB,
              // and a caption styled like an action that isn't one is worse
              // than no caption at all.
              trailing: plan.days.length == 1
                  ? '1 DAY'
                  : '${plan.days.length} DAYS',
            ),
            const SizedBox(height: 11),
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

/// Opens the target editor. Kept as one function so the empty-state card and
/// the summary row can't drift apart.
void _openTargets(BuildContext context, NutritionTargets? current) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => DietTargetsPage(initial: current)),
  );
}

/// Shown when the user has no target. Says plainly what the coach can't do
/// without one, rather than filling the gap with the plan's own total and
/// letting the user believe someone chose it for them.
class _NoTargetCard extends StatelessWidget {
  const _NoTargetCard({required this.onSet});

  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    return TrainDashedCard(
      key: const Key('no-target-card'),
      onTap: onSet,
      child: Row(
        children: [
          const Icon(
            Icons.flag_outlined,
            size: 18,
            color: TrainColors.ink2,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No daily target set', style: AppText.rowTitle),
                const SizedBox(height: 3),
                Text(
                  "Set one and the numbers above become progress toward a "
                  "goal — and your coach can tell you where you stand.",
                  style: AppText.meta.copyWith(color: TrainColors.ink3),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: TrainColors.ink3,
          ),
        ],
      ),
    );
  }
}

/// The one-line statement of what the user is working toward, under the hero:
/// the goal, the calorie target, and where the number came from. Provenance is
/// on the surface here for the same reason "~" is on an estimated calorie —
/// a target the user typed and one a formula proposed are different things.
class _TargetSummaryRow extends StatelessWidget {
  const _TargetSummaryRow({required this.targets, required this.onEdit});

  final NutritionTargets targets;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final low = targetIsBelowSafetyFloor(targets.calories);
    return PressableScale(
      scale: 0.99,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onEdit,
        child: Padding(
          key: const Key('target-summary-row'),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${dietGoalLabel(targets.goal).toUpperCase()} · '
                      '${targets.calories} KCAL/DAY',
                      style: TrainType.mono(
                        size: 11.5,
                        tracking: 0.06,
                        color: TrainColors.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      low
                          ? '${targetSourceLabel(targets.source)} · below '
                                '$kMinimumSafeCalories kcal — worth checking '
                                'with a professional'
                          : targetSourceLabel(targets.source),
                      style: AppText.meta.copyWith(
                        color: low ? TrainColors.ember : TrainColors.ink3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: TrainColors.ink3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Diet hero — the screen's **one hero number**: calories left, inside a
/// 104px green ring. Everything else demotes: the meals-eaten line, the mono
/// eaten/plan caption, and the three macros as bars.
///
/// Bars, not three more fractions. The handoff's own note on this screen is
/// that a ring plus three competing numeric fractions gives the eye four
/// things claiming to be the headline; a bar states "how far along" without
/// asking to be read as a figure.
///
/// Degrades calmly when the plan carries no calorie or macro data yet — see
/// [dayCalories]/[macroTotals]'s null-means-absent semantics.
///
/// **It measures against whichever yardstick actually exists.** With
/// [targets] set, the ring counts down the user's own daily objective and the
/// bars use their macro targets. Without them, it falls back to the day's plan
/// total — clearly labelled as "of plan", because a plan's sum is not a goal
/// anyone chose. The two are never mixed in one figure.
class _DietHero extends StatefulWidget {
  const _DietHero({
    required this.day,
    required this.consumed,
    required this.loading,
    required this.targets,
  });

  final DietDay day;
  final Set<String> consumed;
  final bool loading;

  /// The user's objective, or null when unset.
  final NutritionTargets? targets;

  @override
  State<_DietHero> createState() => _DietHeroState();
}

class _DietHeroState extends State<_DietHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    value: _target(),
  );

  /// Today's progress, as it should be built for the user's own targets.
  /// Null when they have none.
  TargetProgress? get _progressAgainstTargets {
    final targets = widget.targets;
    if (targets == null) return null;
    return buildTargetProgress(
      targets: targets,
      day: widget.day,
      consumed: widget.consumed,
    );
  }

  double _target() {
    final progress = _progressAgainstTargets;
    if (progress != null) {
      return progress.calorieFraction.clamp(0.0, 1.0);
    }
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
    // Macro totals sum every item on the day (supplements included), so ask
    // the same set whether any of it was estimated.
    final macrosEstimated = anyEstimated(day.meals.expand((m) => m.items));
    final hasMacros =
        targetMacros.proteinG != null ||
        targetMacros.carbsG != null ||
        targetMacros.fatG != null;
    final eatenKcal = totalKcal == null ? null : totalKcal - summary.kcalLeft;

    return TrainCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (totalKcal != null) ...[
            SizedBox(
              width: 104,
              height: 104,
              child: AnimatedBuilder(
                animation: _progress,
                builder: (context, _) => Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(104, 104),
                      painter: _CalorieRingPainter(progress: _progress.value),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.loading
                              ? '…'
                              : '${approx(summary.kcalLeftEstimated)}'
                                    '${summary.kcalLeft}',
                          style: TrainType.mono(
                            size: 30,
                            weight: FontWeight.w300,
                            tracking: -0.05,
                            color: const Color(0xFFF9F9F5),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          // The one hero number says out loud when it rests on
                          // AI-estimated values — a bare "1400" claims a
                          // precision an imported plan's guessed figures don't
                          // have.
                          summary.kcalLeftEstimated
                              ? 'EST. KCAL LEFT'
                              : 'KCAL LEFT',
                          style: TrainType.caption(
                            size: 8,
                            tracking: 0.16,
                            color: const Color(0x59F4F4F0),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.loading
                      ? 'Today'
                      : '${summary.eaten} of ${summary.total} meals eaten',
                  style: TrainType.ui(
                    size: 17,
                    weight: FontWeight.w700,
                    color: TrainColors.inkPlain,
                    height: 1.2,
                  ),
                ),
                if (totalKcal == null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'NO CALORIE DATA YET',
                    style: TrainType.mono(
                      size: 10.5,
                      tracking: 0.06,
                      color: TrainColors.ink4,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.loading
                        ? 'PLAN $totalKcal'
                        : '$eatenKcal EATEN · PLAN $totalKcal',
                    style: TrainType.mono(
                      size: 10.5,
                      tracking: 0.06,
                      color: TrainColors.ink4,
                    ),
                  ),
                ],
                if (hasMacros) ...[
                  const SizedBox(height: 15),
                  // Green protein, violet carbs, amber fat — one hue each, so
                  // three bars read as three different things at a glance.
                  // Amber is money everywhere else in the app; here it is the
                  // third macro and nothing about money is on this screen.
                  if (targetMacros.proteinG != null)
                    _MacroBar(
                      label: 'PROTEIN',
                      eaten: consumedMacros.proteinG ?? 0,
                      target: targetMacros.proteinG!,
                      estimated: macrosEstimated,
                      color: TrainColors.green,
                      loading: widget.loading,
                    ),
                  if (targetMacros.carbsG != null)
                    _MacroBar(
                      label: 'CARBS',
                      eaten: consumedMacros.carbsG ?? 0,
                      target: targetMacros.carbsG!,
                      estimated: macrosEstimated,
                      color: TrainColors.violetGlyph,
                      loading: widget.loading,
                    ),
                  if (targetMacros.fatG != null)
                    _MacroBar(
                      label: 'FAT',
                      eaten: consumedMacros.fatG ?? 0,
                      target: targetMacros.fatG!,
                      estimated: macrosEstimated,
                      color: TrainColors.amber,
                      loading: widget.loading,
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

/// One macro: a mono caption and its `eaten/target` figure on one line, with
/// a 3px bar beneath. The figure stays dimmer than the meals line above it —
/// this is context for the hero number, not a second headline.
class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.label,
    required this.eaten,
    required this.target,
    required this.color,
    required this.loading,
    required this.estimated,
  });

  final String label;

  /// Grams consumed. Zero is a real reading (nothing eaten yet) — only
  /// [loading] means "not known", and a `macroTotals` null over an empty
  /// consumed set is the former, not the latter.
  final double eaten;
  final double target;
  final Color color;

  /// Whether the target grams rest on any AI-estimated item — rendered as the
  /// same "~" the calorie figures use, so one convention covers both.
  final bool estimated;

  /// While the consumed set is still resolving, a dash beats a "0g" that
  /// might be wrong the moment the stream lands.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TrainType.caption(
                    size: 8.5,
                    tracking: 0.14,
                    color: const Color(0x59F4F4F0),
                  ),
                ),
              ),
              Text(
                '${loading ? '–' : eaten.round()}'
                    '/${approx(estimated)}${target.round()}g',
                style: TrainType.mono(
                  size: 9.5,
                  color: const Color(0x99F4F4F0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          TrainBar(
            progress: target <= 0 || loading ? 0 : eaten / target,
            color: color,
            height: 3,
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
    final radius = size.shortestSide / 2 - 6;
    // The track carries the whole ring at 0% — nothing else is drawn — so it
    // has to read as "a ring with nothing in it yet" rather than as a ring
    // that failed to render. A hairline is the right weight for a card edge
    // and too quiet for that job.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = TrainColors.hairlineStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * clamped,
      false,
      Paint()
        ..color = TrainColors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CalorieRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// One of today's meals, as the handoff draws it: a 24px check on the left,
/// the meal's name with its items as a mono caption, and its calories with a
/// `KCAL · P n G` caption right-aligned.
///
/// Two affordances, both visible: the **check ticks it eaten** (and drives
/// the hero ring and macro bars live), the **row body opens the meal**. The
/// check's visible circle is 24px but its tap target is the full 44px the
/// accessibility floor asks for.
class _MealRow extends StatefulWidget {
  const _MealRow({
    required this.meal,
    required this.eaten,
    required this.onToggle,
  });

  final Meal meal;
  final bool eaten;
  final VoidCallback onToggle;

  @override
  State<_MealRow> createState() => _MealRowState();
}

class _MealRowState extends State<_MealRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    value: widget.eaten ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _MealRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.eaten == oldWidget.eaten) return;
    final target = widget.eaten ? 1.0 : 0.0;
    if (reducedMotion(context)) {
      _fill.value = target;
    } else {
      _fill.springTo(target, spring: AppSprings.standard);
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    widget.onToggle();
  }

  void _open() {
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
    final macros = macroTotals(meal.items);
    // "OATS · BANANA" — what's in it, without opening it.
    final items = meal.items.map((i) => i.name.toUpperCase()).join(' · ');

    return AnimatedBuilder(
      animation: _fill,
      builder: (context, _) {
        final t = _fill.value.clamp(0.0, 1.0);
        return PressableScale(
          scale: 0.99,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _open,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 8),
              decoration: BoxDecoration(
                color: Color.lerp(
                  const Color(0x0BFFFFFF),
                  TrainColors.green.withValues(alpha: 0.07),
                  t,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Color.lerp(
                    TrainColors.hairline,
                    TrainColors.green.withValues(alpha: 0.28),
                    t,
                  )!,
                ),
              ),
              child: Row(
                children: [
                  _CompletionMark(
                    key: Key('meal-tick-${meal.id}'),
                    progress: t,
                    onTap: _toggle,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          meal.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TrainType.ui(
                            size: 15,
                            weight: FontWeight.w700,
                            color: TrainColors.inkPlain,
                            height: 1,
                          ),
                        ),
                        if (items.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text(
                            items,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TrainType.mono(
                              size: 10,
                              tracking: 0.06,
                              color: TrainColors.ink4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (kcal != null) ...[
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${approx(mealEstimated(meal))}$kcal',
                          style: TrainType.mono(
                            size: 15,
                            color: TrainColors.ink,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          macros.proteinG == null
                              ? 'KCAL'
                              : 'KCAL · P ${macros.proteinG!.round()}G',
                          style: TrainType.caption(
                            size: 8.5,
                            tracking: 0.12,
                            color: TrainColors.ink4,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
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
        color: const Color(0x06FFFFFF),
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
                    ? TrainColors.green.withValues(alpha: 0.24)
                    : TrainColors.hairline,
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
                    color: taken
                        ? TrainColors.green.withValues(alpha: 0.75)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: taken
                          ? TrainColors.green.withValues(alpha: 0.75)
                          : const Color(0x2EFFFFFF),
                      width: 1.5,
                    ),
                  ),
                  child: taken
                      ? const Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: Color(0xFF04140D),
                        )
                      : null,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    meal.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TrainType.ui(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: taken
                              ? TrainColors.ink4
                              : TrainColors.inkPlain,
                        ).copyWith(
                          decoration: taken ? TextDecoration.lineThrough : null,
                        ),
                  ),
                ),
                if (meal.items.length > 1) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${meal.items.length} items',
                    style: AppText.meta.copyWith(
                      fontSize: 11.5,
                      color: TrainColors.ink3,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'View details',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          MealDetailPage(meal: meal, isSupplement: true),
                    ),
                  ),
                  icon: const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: TrainColors.ink3,
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

/// The meal row's tick — a 24px circle that fills green when eaten, with the
/// check drawing in at the raw (unclamped) spring value so completion reads
/// as a small pop.
///
/// Its visible circle is 24px, but the widget claims the full 44px minimum
/// tap target around it — the handoff's accessibility floor — so ticking a
/// meal never demands a precise tap.
class _CompletionMark extends StatelessWidget {
  const _CompletionMark({
    required this.progress,
    required this.onTap,
    super.key,
  });

  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tc = progress.clamp(0.0, 1.0);
    return Semantics(
      checked: tc > 0.5,
      button: true,
      label: 'Eaten',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(Colors.transparent, TrainColors.green, tc),
                border: Border.all(
                  color: Color.lerp(
                    const Color(0x2EFFFFFF),
                    TrainColors.green,
                    tc,
                  )!,
                  width: 1.5,
                ),
              ),
              child: tc > 0.01
                  ? Center(
                      child: Transform.scale(
                        scale: progress,
                        child: Opacity(
                          opacity: tc,
                          child: const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Color(0xFF04140D),
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// One day of the full plan, as a reference card: the day's name and its
/// calorie total on one line, a rule, then a label-value line per meal —
/// mono caption on the left, the food itself in Manrope on the right.
class _DaySummaryCard extends StatelessWidget {
  const _DaySummaryCard({required this.day});

  final DietDay day;

  @override
  Widget build(BuildContext context) {
    final kcal = dayCalories(day);
    final meals = [...day.meals]..sort((a, b) => a.order.compareTo(b.order));
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TrainColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  day.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TrainType.ui(
                    size: 14,
                    weight: FontWeight.w700,
                    color: TrainColors.inkPlain,
                    height: 1,
                  ),
                ),
              ),
              if (kcal != null)
                Text(
                  '${approx(dayEstimated(day))}$kcal kcal',
                  style: TrainType.mono(size: 13, color: TrainColors.green),
                ),
            ],
          ),
          if (meals.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 13, bottom: 12),
              child: Divider(
                height: 1,
                thickness: 1,
                color: TrainColors.hairline,
              ),
            ),
            for (var i = 0; i < meals.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 86,
                      child: Text(
                        meals[i].label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TrainType.caption(
                          size: 8.5,
                          tracking: 0.14,
                          color: TrainColors.ink4,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        meals[i].items.map((it) => it.name).join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TrainType.ui(
                          size: 12,
                          weight: FontWeight.w400,
                          color: const Color(0xA6F4F4F0),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Whether a plan's own name already states a calorie figure — "Balanced —
/// 2200 kcal", "1800kcal cut". Used to keep the header caption from stating
