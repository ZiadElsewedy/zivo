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
import '../../domain/analysis/plan_verdict.dart';
import '../../domain/body_measures.dart';
import '../../domain/diet_day.dart';
import '../../domain/diet_format.dart';
import '../../domain/diet_plan.dart';
import '../../domain/food_item.dart';
import '../../domain/diet_goal.dart';
import '../../domain/diet_summary.dart';
import '../../domain/meal.dart';
import '../../domain/nutrition/food_log_entry.dart';
import '../../domain/nutrition/food_reference.dart';
import '../../domain/nutrition_targets.dart';
import '../../domain/diet_state.dart';
import '../../domain/diet_state_builder.dart';
import '../widgets/add_diet_sheet.dart';
import '../widgets/adopt_plan_target_sheet.dart';
import '../widgets/body_measures_builder.dart';
import '../widgets/log_food_sheet.dart';
import '../widgets/todays_read_card.dart';
import '../today_diet.dart';
import 'body_profile_page.dart';
import 'diet_plan_edit_page.dart';
import 'diet_plans_page.dart';
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
                  action: planSnapshot.hasError
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Reachable even with no ACTIVE plan — that is
                            // exactly the case where it matters, because
                            // "everything is archived" and "you have no plans"
                            // look identical from the Diet screen otherwise.
                            TrainHeaderAction(
                              key: const Key('open-plan-library'),
                              icon: Icons.layers_outlined,
                              semanticLabel: 'Your plans',
                              accent: TrainColors.green,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const DietPlansPage(),
                                ),
                              ),
                            ),
                            if (plan != null) ...[
                              const SizedBox(width: 8),
                              TrainHeaderAction(
                                icon: Icons.shopping_basket_outlined,
                                semanticLabel: 'Groceries',
                                accent: TrainColors.green,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => GroceryListPage(plan: plan),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              Expanded(
                child: planSnapshot.hasError
                    ? const ErrorStateView()
                    : loading
                    ? const LoadingStateView()
                    : plan == null
                    // "No plan" and "every plan you have is archived" are
                    // different situations with the same active plan (none),
                    // and telling the second one it has no plans is how a
                    // user concludes their imported plan was lost.
                    ? StreamBuilder<List<DietPlan>>(
                        stream: diet.watchPlans(),
                        initialData: diet.plans,
                        builder: (context, plansSnapshot) => _EmptyState(
                          shelvedPlans:
                              (plansSnapshot.data ?? const <DietPlan>[]).length,
                          onAdd: () => showAddDietSheet(context),
                          onOpenLibrary: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const DietPlansPage(),
                            ),
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
  const _EmptyState({
    required this.onAdd,
    required this.onOpenLibrary,
    this.shelvedPlans = 0,
  });

  /// Opens the capture sheet — the one door, with all four routes behind it
  /// (document, photo, dictation, typing) plus the manual editor. A separate
  /// "create manually" link here would be one of those routes hoisted out of
  /// the list it belongs in.
  final VoidCallback onAdd;
  final VoidCallback onOpenLibrary;

  /// How many plans exist but aren't being followed. Non-zero turns this from
  /// "you have nothing" into "you're not following any of them", which is a
  /// different sentence with a different way out.
  final int shelvedPlans;

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
            Text(
              shelvedPlans == 0
                  ? 'No diet plan yet.'
                  : "You're not following a plan.",
              key: const Key('diet-empty-headline'),
              style: AppText.aside,
            ),
            const SizedBox(height: 6),
            Text(
              shelvedPlans == 0
                  ? 'Import a document or a photo, say it out loud, type it '
                        "out, or build one by hand — I'll fill in the "
                        'calories and macros.'
                  : '$shelvedPlans ${shelvedPlans == 1 ? "plan is" : "plans are"} '
                        'archived — pick one back up, or add another.',
              style: AppText.meta.copyWith(color: TrainColors.ink3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 220,
              child: PillButton(
                key: const Key('diet-empty-add'),
                label: 'Add a diet',
                icon: Icons.add_rounded,
                color: TrainColors.green,
                enabled: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onAdd();
                },
              ),
            ),
            if (shelvedPlans > 0)
              PressableScale(
                child: TextButton(
                  key: const Key('empty-open-library'),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onOpenLibrary();
                  },
                  child: Text(
                    'See your plans',
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
///
/// Stateful purely to own the consumption stream: `watchConsumed(now)` opens a
/// new subscription every time it's called, so building it inside `build`
/// would tear down and re-open it on every rebuild — including the extra
/// rebuild the targets stream now causes, which also resets the stream to
/// `waiting` and blanks the hero's numbers mid-session.
class _PlanBodyForTargets extends StatefulWidget {
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
  State<_PlanBodyForTargets> createState() => _PlanBodyForTargetsState();
}

class _PlanBodyForTargetsState extends State<_PlanBodyForTargets> {
  Stream<Set<String>>? _consumedStream;
  Stream<List<FoodLogEntry>>? _logStream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final diet = AppScope.of(context).diet;
    _consumedStream ??= diet.watchConsumed(widget.now);
    _logStream ??= diet.watchFoodLog(widget.now);
  }

  /// Logs what the sheet produced. The sheet itself never writes — it returns
  /// entries, and persisting them is this page's job.
  Future<void> _logFood() async {
    final diet = AppScope.of(context).diet;
    final entries = await showLogFoodSheet(context, day: widget.now);
    if (entries == null || entries.isEmpty) return;
    await diet.logFood(entries);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FoodLogEntry>>(
      stream: _logStream,
      initialData: const <FoodLogEntry>[],
      builder: (context, logSnapshot) => StreamBuilder<Set<String>>(
        stream: _consumedStream,
        initialData: const <String>{},
        builder: (context, consumedSnapshot) => _buildList(
          context,
          log: logSnapshot.data ?? const <FoodLogEntry>[],
          consumed: consumedSnapshot.data ?? const <String>{},
          consumedLoading:
              consumedSnapshot.connectionState == ConnectionState.waiting,
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context, {
    required List<FoodLogEntry> log,
    required Set<String> consumed,
    required bool consumedLoading,
  }) {
    final diet = AppScope.of(context).diet;
    final plan = widget.plan;
    final now = widget.now;
    final targets = widget.targets;
    final today = widget.today;
    final target = today == null ? null : dayCalories(today);
    // **One state for the whole screen**, built once per frame by the same
    // `buildDietState` the coach reads on the server. The hero draws from it,
    // the read card's findings are derived from it, and neither can therefore
    // quote a figure the other doesn't have. Built even with no targets set —
    // "no objective" is a state the engine has something to say about, not a
    // reason to have no state.
    final state = buildDietState(
      dayKey: dietDayKey(now),
      weekday: now.weekday,
      targets: targets,
      planName: plan.name,
      day: today,
      consumedMealIds: consumed,
      log: log,
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(22, 14, 22, TrainBottomInset.of(context)),
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
            if (targets != null) 'TARGET ${targets.calories} KCAL',
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
        // Said plainly, and said first — but it is not the end of the
        // screen. A day with no plan day is still a day the user has an
        // objective for and may have eaten on, and the hero, the target and
        // the read below all measure the DAY, not the plan.
        if (today == null) ...[
          Text(
            'No plan for today.',
            style: TrainType.ui(
              size: 14,
              weight: FontWeight.w400,
              color: TrainColors.ink2,
            ),
          ),
          const SizedBox(height: 14),
        ],
        // Needs one yardstick or the other. With neither a plan day nor a
        // target there is nothing to draw a ring against and nothing to be
        // left of — and the no-target card's own copy ("the numbers above")
        // would be pointing at a hero that isn't there.
        if (today != null || targets != null) ...[
          _DietHero(
            day: today,
            consumed: consumed,
            loading: consumedLoading,
            state: state,
          ),
          // What the PLAN does to this person — the question a diet is
          // actually for, and the one thing on this screen that isn't about
          // today. It sits under the hero because it explains the plan the
          // hero is counting down, and above the target card because "this
          // makes you gain 0.5 kg a week" is the fact a target is chosen in
          // response to.
          _PlanVerdictSection(
            plan: plan,
            onAddBodyData: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const BodyProfilePage())),
          ),
          const SizedBox(height: 12),
          if (targets == null)
            _NoTargetCard(plan: plan, onSet: () => _openTargets(context, null))
          else
            _TargetSummaryRow(
              targets: targets,
              onEdit: () => _openTargets(context, targets),
            ),
          // What the coaching engine makes of all that — the same findings,
          // from the same state, that the AI coach is handed, each openable
          // to the figures it rests on. Renders nothing when the rules have
          // nothing to say.
          //
          // Held back until there's an objective: with none, the engine's
          // findings are all downstream of that one gap, and the card above
          // already says it — with somewhere to tap. Printing the engine's
          // wording of the same sentence underneath would be the screen
          // repeating itself in a quieter voice.
          if (!consumedLoading && targets != null)
            TodaysReadCard(state: state, localHour: now.hour),
        ],
        // Meals and supplements ARE the plan day, so they end with it.
        if (today != null) ...[
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
                  key: Key('supplement-card-${meal.id}'),
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
        // The ledger sits directly under the meals that feed it: ticking a
        // meal materialises its items here, and anything else eaten is added
        // by hand. Below the meals, not above — ticking is still the primary
        // interaction on this screen.
        TrainSectionLabel(
          'Eaten today',
          trailing: log.isEmpty ? null : '${log.length}',
        ),
        const SizedBox(height: 11),
        _LogFoodButton(onTap: _logFood),
        if (log.isNotEmpty) ...[
          const SizedBox(height: 9),
          for (final entry in log)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _LogEntryRow(
                entry: entry,
                onRemove: () => diet.removeFoodLogEntry(entry.id),
              ),
            ),
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
  }
}

/// The one way into the food log. Quiet, not ember: the committing action on
/// this screen is still the plan editor's Save, and a second glowing button
/// would make neither read as primary.
class _LogFoodButton extends StatelessWidget {
  const _LogFoodButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TrainDashedCard(
      key: const Key('log-food-button'),
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      child: Row(
        children: [
          const Icon(Icons.add_rounded, size: 18, color: TrainColors.ink2),
          const SizedBox(width: 11),
          Expanded(
            child: Text('Log something you ate', style: AppText.rowTitle),
          ),
        ],
      ),
    );
  }
}

/// One logged food: what it was, what it came to, and where that came from.
///
/// The provenance line is not decoration. An entry resolved from the USDA
/// catalog, one the user defined themselves, and one materialised from a
/// ticked plan meal are three different kinds of claim, and the row says which
/// it is rather than rendering them identically.
class _LogEntryRow extends StatelessWidget {
  const _LogEntryRow({required this.entry, required this.onRemove});

  final FoodLogEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final fromPlan = entry.origin == FoodLogOrigin.plannedMeal;
    return Container(
      key: Key('log-entry-${entry.id}'),
      padding: const EdgeInsets.fromLTRB(15, 11, 9, 11),
      decoration: BoxDecoration(
        color: const Color(0x0BFFFFFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.foodName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.rowTitle.copyWith(fontSize: 13.5),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    '${_trim(entry.quantity)} ${entry.unit}',
                    fromPlan
                        ? 'from your plan'
                        : nutritionSourceLabel(entry.source),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.meta.copyWith(color: TrainColors.ink3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${approx(entry.estimated)}${entry.kcal}',
            style: TrainType.mono(size: 14, color: TrainColors.ink),
          ),
          IconButton(
            key: Key('remove-log-${entry.id}'),
            onPressed: onRemove,
            iconSize: 17,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, color: TrainColors.ink4),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }

  static String _trim(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);
}

/// Opens the target editor. Kept as one function so the empty-state card and
/// the summary row can't drift apart.
void _openTargets(BuildContext context, NutritionTargets? current) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => DietTargetsPage(initial: current)));
}

/// Shown when the user has no target. Says plainly what the coach can't do
/// without one, rather than filling the gap with the plan's own total and
/// letting the user believe someone chose it for them.
class _NoTargetCard extends StatelessWidget {
  const _NoTargetCard({required this.plan, required this.onSet});

  final DietPlan plan;
  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    // The plan already states a daily figure. Offering it as the target is
    // the shortest route out of this state and it invents nothing — the
    // number is the user's own plan's, and the sheet asks for the one thing
    // the plan can't say (what it's for) before anything is saved.
    final planKcal = planDailyEnergy(plan).kcalPerDay;
    return TrainDashedCard(
      key: const Key('no-target-card'),
      onTap: onSet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          if (planKcal != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('adopt-plan-target'),
                onPressed: () async {
                  HapticFeedback.selectionClick();
                  await showAdoptPlanTargetSheet(context, plan: plan);
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(
                  "Use this plan's ${approx(planDailyEnergy(plan).estimated)}"
                  '$planKcal kcal',
                  style: AppText.meta.copyWith(color: TrainColors.green),
                ),
              ),
            ),
          ],
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
                    // A calculated target explains itself. "Calculated from
                    // your body data" says a formula ran; this says which
                    // numbers went into it — which is also how a user notices
                    // the figure is still resting on a weight from March.
                    if (targets.basis != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        targetBasisSummary(targets.basis!),
                        key: const Key('target-basis'),
                        style: AppText.meta.copyWith(color: TrainColors.ink4),
                      ),
                    ],
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
/// [dayCalories]/[macroTotals]'s null-means-absent semantics — and when there
/// is no plan day at all: with a target set, everything it draws comes from
/// the log, which doesn't need a plan to exist.
///
/// **It measures against whichever yardstick actually exists.** With targets
/// set, the ring counts down the user's own daily objective and the bars use
/// their macro targets. Without them, it falls back to the day's plan total —
/// clearly labelled as "of plan", because a plan's sum is not a goal anyone
/// chose. The two are never mixed in one figure.
class _DietHero extends StatefulWidget {
  const _DietHero({
    required this.day,
    required this.consumed,
    required this.loading,
    required this.state,
  });

  /// Today's plan day, or null when none applies. Null is only reachable
  /// with targets set — see the caller: with neither a plan day nor a target
  /// there is no yardstick, and the hero isn't built at all.
  final DietDay? day;

  final Set<String> consumed;
  final bool loading;

  /// The screen's one [DietState] — built by the page, shared with the read
  /// card below. The hero doesn't build its own: two objects claiming to
  /// describe the same day is how a ring and a sentence end up disagreeing.
  final DietState state;

  @override
  State<_DietHero> createState() => _DietHeroState();
}

class _DietHeroState extends State<_DietHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    value: _target(),
  );

  /// The state to measure against, or null when the user has set no objective
  /// — with nothing to measure against, the hero falls back to the plan's own
  /// total and says so.
  ///
  /// The state itself always exists (the page builds it either way); what's
  /// absent without targets is a *yardstick*, and null here is how the rest of
  /// this widget asks that question.
  DietState? get _state =>
      widget.state.quality.targetsUnset ? null : widget.state;

  double _target() {
    final state = _state;
    if (state != null) {
      return state.calorieFraction.clamp(0.0, 1.0);
    }
    final day = widget.day;
    if (day == null) return 0;
    final total = dayCalories(day);
    if (total == null || total <= 0) return 0;
    final kcalLeft = dietDaySummary(day, widget.consumed).kcalLeft;
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
    // Everything derived from the PLAN is absent when no plan day applies —
    // absent, not zero. The target-driven path below reads none of it.
    final planItems = day == null
        ? const <FoodItem>[]
        : day.meals.expand((m) => m.items).toList();
    final totalKcal = day == null ? null : dayCalories(day);
    final summary = day == null ? null : dietDaySummary(day, widget.consumed);
    final targetMacros = macroTotals(planItems);
    final consumedMacros = macroTotals(
      day == null
          ? const <FoodItem>[]
          : day.meals
                .where((m) => widget.consumed.contains(m.id))
                .expand((m) => m.items),
    );
    // Macro totals sum every item on the day (supplements included), so ask
    // the same set whether any of it was estimated.
    final macrosEstimated = anyEstimated(planItems);
    final hasMacros =
        targetMacros.proteinG != null ||
        targetMacros.carbsG != null ||
        targetMacros.fatG != null;
    final eatenKcal = totalKcal == null || summary == null
        ? null
        : totalKcal - summary.kcalLeft;

    // Today measured against the user's OWN objective, when they have one.
    // Everything below prefers it and falls back to the plan's totals only in
    // its absence — and says which it used, either way.
    final progress = _state;
    final macroBars = progress?.trackedMacros ?? const <MacroProgress>[];

    return TrainCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (totalKcal != null || progress != null) ...[
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
                    // The block has to stay INSIDE the ring, and both of its
                    // lines are variable-length: a four-figure "~3356" is
                    // wider at 30pt than the circle is, and the longest label
                    // ("EST. KCAL LEFT OF PLAN") wraps. So the content is
                    // boxed to the ring's inner width and the figure scales
                    // down to fit it — 30pt stays the size for everything
                    // that fits, rather than every number being shrunk for
                    // the worst case.
                    SizedBox(
                      width: _kRingInnerWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              widget.loading
                                  ? '…'
                                  : _heroNumber(progress, summary),
                              maxLines: 1,
                              style: TrainType.mono(
                                size: 30,
                                weight: FontWeight.w300,
                                tracking: -0.05,
                                color: const Color(0xFFF9F9F5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            // The one hero number says out loud both what it
                            // is measured against and whether it rests on
                            // AI-estimated values — a bare "1400" claims a
                            // precision an imported plan's guessed figures
                            // don't have, and "left" means nothing until you
                            // know "left of what". It is allowed to wrap, so
                            // it is centred: the longest label's second line
                            // ("PLAN") hung off to the left otherwise.
                            _heroLabel(progress, summary),
                            textAlign: TextAlign.center,
                            style: TrainType.caption(
                              size: 8,
                              tracking: 0.16,
                              color: const Color(0x59F4F4F0),
                            ),
                          ),
                        ],
                      ),
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
                  // No plan day means no meals to count — "0 of 0 meals
                  // eaten" would read as a failure rather than as an absence,
                  // and the line above the card has already said why.
                  widget.loading || summary == null
                      ? 'Today'
                      : '${summary.eaten} of ${summary.total} meals eaten',
                  style: TrainType.ui(
                    size: 17,
                    weight: FontWeight.w700,
                    color: TrainColors.inkPlain,
                    height: 1.2,
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.loading
                        ? 'TARGET ${progress.targets!.calories}'
                        : '${approx(progress.consumed.estimated)}'
                              '${progress.consumed.kcal} EATEN · '
                              'TARGET ${progress.targets!.calories}',
                    style: TrainType.mono(
                      size: 10.5,
                      tracking: 0.06,
                      color: TrainColors.ink4,
                    ),
                  ),
                  // What "EATEN" actually rests on. The figure above is the
                  // same one the coach is handed, and the coach is never
                  // allowed to say "you ate" about ticked plan meals — the
                  // screen showing the bare number with no such qualifier
                  // would be the app making the claim its own coach is
                  // forbidden to make.
                  if (!widget.loading) ...[
                    const SizedBox(height: 4),
                    Text(
                      consumedBasisShortLabel(
                        progress.consumed.basis,
                      ).toUpperCase(),
                      key: const Key('hero-consumed-basis'),
                      style: TrainType.caption(
                        size: 8.5,
                        tracking: 0.14,
                        color: TrainColors.ink4,
                      ),
                    ),
                  ],
                ] else if (totalKcal == null) ...[
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
                if (progress != null) ...[
                  if (macroBars.isNotEmpty) ...[
                    const SizedBox(height: 15),
                    // Same three hues, now measuring the user's own macro
                    // targets. A macro they didn't set a target for gets no
                    // bar at all — better a missing row than one silently
                    // measured against a different yardstick than its
                    // neighbours.
                    for (final macro in macroBars)
                      _MacroBar(
                        label: macro.label.toUpperCase(),
                        eaten: macro.consumed,
                        target: macro.target!,
                        estimated: macro.estimated,
                        color: _macroColor(macro.label),
                        loading: widget.loading,
                      ),
                  ],
                ] else if (hasMacros) ...[
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

/// The hero's figure: calories left against the user's target when they have
/// one (its magnitude — "over by 120" reads better than "-120"), otherwise
/// calories left of the day's plan. Marked "~" whenever it rests on estimated
/// values.
String _heroNumber(
  DietState? progress,
  ({int eaten, int total, int kcalLeft, bool kcalLeftEstimated})? summary,
) {
  if (progress != null) {
    return '${approx(progress.consumed.estimated)}${progress.remainingKcal.abs()}';
  }
  // No target: then there is a plan day, and so a summary — the hero isn't
  // built when both are missing.
  return '${approx(summary!.kcalLeftEstimated)}${summary.kcalLeft}';
}

/// What that figure is measured against — never left implicit.
String _heroLabel(
  DietState? progress,
  ({int eaten, int total, int kcalLeft, bool kcalLeftEstimated})? summary,
) {
  if (progress != null) {
    final estimated = progress.consumed.estimated ? 'EST. ' : '';
    return progress.overTarget
        ? '${estimated}KCAL OVER'
        : '${estimated}KCAL LEFT';
  }
  return summary!.kcalLeftEstimated
      ? 'EST. KCAL LEFT OF PLAN'
      : 'KCAL LEFT OF PLAN';
}

/// The hue that owns each macro, so a target-driven bar and a plan-driven one
/// never disagree about which colour protein is.
Color _macroColor(String label) => switch (label) {
  'Protein' => TrainColors.green,
  'Carbs' => TrainColors.violetGlyph,
  _ => TrainColors.amber,
};

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

/// The plan's verdict, or the honest reason there isn't one yet.
///
/// Three states, and each is a real answer:
/// - **Body data missing** — a prompt naming exactly what's needed. ZIVO does
///   not fill in an average body and produce a number from it.
/// - **Plan has no calorie figures** — nothing rendered; the hero already
///   says "NO CALORIE DATA YET" and a second empty card would just repeat it.
/// - **A verdict** — the headline, the arithmetic under it, and the two
///   things that qualify it (protein, and the safety floor).
class _PlanVerdictSection extends StatelessWidget {
  const _PlanVerdictSection({required this.plan, required this.onAddBodyData});

  final DietPlan plan;
  final VoidCallback onAddBodyData;

  @override
  Widget build(BuildContext context) => BodyMeasuresBuilder(builder: _build);

  Widget _build(BuildContext context, BodyMeasuresResolution measures) {
    final resolved = measures.measures;
    if (resolved == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _BodyDataPrompt(missing: measures.missing, onTap: onAddBodyData),
      );
    }
    final verdict = analysePlan(plan: plan, measures: resolved);
    if (verdict == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _VerdictCard(
        verdict: verdict,
        weighInAgeDays: resolved.weighInAgeDays(DateTime.now()),
        onEditBodyData: onAddBodyData,
      ),
    );
  }
}

/// The ask, when ZIVO can't answer yet. Dashed rather than solid: it is an
/// outline waiting on data, not a card reporting something (identity §8).
class _BodyDataPrompt extends StatelessWidget {
  const _BodyDataPrompt({required this.missing, required this.onTap});

  final Set<MissingBodyData> missing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TrainDashedCard(
      key: const Key('body-data-prompt'),
      onTap: onTap,
      child: Row(
        children: [
          const Icon(
            Icons.straighten_rounded,
            size: 18,
            color: TrainColors.ink2,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Is this plan making you gain or lose?',
                  style: AppText.rowTitle,
                ),
                const SizedBox(height: 3),
                Text(
                  // Names what is actually missing rather than "complete your
                  // profile" — one of these is usually already known, and
                  // being asked again for something you gave is what makes a
                  // prompt feel like a wall.
                  'ZIVO needs ${_missingPhrase(missing)} to work it out.',
                  key: const Key('body-data-missing'),
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

  /// "your height" · "your height and your current weight" · "your height,
  /// your current weight and how active your week is".
  static String _missingPhrase(Set<MissingBodyData> missing) {
    // The three that arrive together (an absent body profile) read as one
    // ask, not three.
    final labels = missing.map(missingBodyDataLabel).toList();
    if (labels.length == 1) return labels.first;
    if (labels.length == 2) return '${labels[0]} and ${labels[1]}';
    return '${labels.sublist(0, labels.length - 1).join(', ')} '
        'and ${labels.last}';
  }
}

/// The answer. One headline, its working underneath, and only the caveats
/// that change what the user should do about it.
class _VerdictCard extends StatelessWidget {
  const _VerdictCard({
    required this.verdict,
    required this.weighInAgeDays,
    required this.onEditBodyData,
  });

  final PlanVerdict verdict;
  final int weighInAgeDays;
  final VoidCallback onEditBodyData;

  Color get _hue => switch (verdict.direction) {
    // Green is state everywhere in this app, and "holding" is the state of
    // being on maintenance. Gaining and losing are not good or bad — a bulk
    // and a cut are both goals — so neither gets a judgement colour; they
    // take the neutral mark and let the words carry the meaning.
    EnergyDirection.holding => TrainColors.green,
    _ => TrainColors.neutralMark,
  };

  @override
  Widget build(BuildContext context) {
    return TrainCard(
      key: const Key('plan-verdict-card'),
      radius: 20,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'THIS PLAN',
                style: TrainType.caption(size: 9, tracking: 0.16),
              ),
              const Spacer(),
              GestureDetector(
                key: const Key('verdict-edit-body-data'),
                onTap: onEditBodyData,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  'BODY DATA',
                  style: TrainType.caption(
                    size: 9,
                    tracking: 0.16,
                    color: TrainColors.ink3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: _hue, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  verdictHeadline(verdict),
                  key: const Key('verdict-headline'),
                  style: TrainType.ui(
                    size: 16,
                    weight: FontWeight.w700,
                    color: TrainColors.inkPlain,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            verdictDetail(verdict),
            key: const Key('verdict-detail'),
            style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.4),
          ),
          if (verdict.daysWithoutCalories > 0) ...[
            const SizedBox(height: 6),
            Text(
              // The average speaks for part of the plan, and says so — the
              // alternative is a figure that quietly stands in for days it
              // never counted.
              'Averaged over ${verdict.daysCounted} '
              '${verdict.daysCounted == 1 ? "day" : "days"}; '
              '${verdict.daysWithoutCalories} '
              '${verdict.daysWithoutCalories == 1 ? "day has" : "days have"} '
              'no calorie figures.',
              key: const Key('verdict-partial'),
              style: AppText.meta.copyWith(color: TrainColors.ink3),
            ),
          ],
          if (verdict.proteinGPerKg != null) ...[
            const SizedBox(height: 6),
            Text(
              'Protein ${verdict.proteinGPerKg!.toStringAsFixed(1)} g per kg '
              'of bodyweight.',
              key: const Key('verdict-protein'),
              style: AppText.meta.copyWith(color: TrainColors.ink3),
            ),
          ],
          if (weighInAgeDays > kWeighInStaleAfterDays) ...[
            const SizedBox(height: 6),
            Text(
              'Your last weigh-in is $weighInAgeDays days old — weight drives '
              'this figure, so it is worth updating.',
              key: const Key('verdict-stale-weight'),
              style: AppText.meta.copyWith(color: TrainColors.ink3),
            ),
          ],
          if (verdict.belowSafetyFloor) ...[
            const SizedBox(height: 10),
            Text(
              'This plan is under $kMinimumSafeCalories kcal a day. Sustained '
              'intake down here belongs with a doctor, not an app.',
              key: const Key('verdict-safety-floor'),
              style: AppText.meta.copyWith(
                color: TrainColors.ember,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The widest the hero's figure + label may be inside the 104px ring.
///
/// The ring's stroke sits at radius 46 with a 5px width, so its inner edge is
/// at 43.5; a centred block two lines tall has to fit within the chord at that
/// height, not the diameter. 76 is that chord with a little air — anything
/// wider starts crossing the stroke, which is exactly what "~3356" at 30pt did.
const double _kRingInnerWidth = 76;

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
    super.key,
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
