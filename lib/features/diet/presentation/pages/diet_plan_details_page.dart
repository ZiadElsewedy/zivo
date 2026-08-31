import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/train_chrome.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/analysis/maintenance_calibration.dart';
import '../../domain/analysis/plan_verdict.dart';
import '../../domain/body_measures.dart';
import '../../domain/diet_day.dart';
import '../../domain/diet_format.dart';
import '../../domain/diet_goal.dart';
import '../../domain/diet_plan.dart';
import '../../domain/diet_state.dart';
import '../../domain/diet_state_builder.dart';
import '../../domain/nutrition/food_log_entry.dart';
import '../../domain/nutrition_targets.dart';
import '../widgets/adopt_plan_target_sheet.dart';
import '../widgets/body_measures_builder.dart';
import '../today_diet.dart';
import '../widgets/todays_read_card.dart';
import 'body_profile_page.dart';
import 'diet_targets_page.dart';

/// **Plan details** — everything the Diet screen used to stack on top of the
/// meals, moved one level down.
///
/// The Diet screen answers "what do I eat, and what have I eaten". This page
/// answers the questions underneath it: what am I working toward, what is this
/// plan actually doing to my weight, what does the coaching engine make of
/// today, and what does the whole plan look like. All of it is real and none of
/// it is per-meal, which is exactly why it reads as clutter on the surface a
/// user opens five times a day and why it belongs here.
///
/// It builds its **own** streams rather than taking a snapshot from the Diet
/// screen: a target edited here has to be visible here the moment it's saved,
/// and a page rendering a frozen copy of its parent's state is how "I changed
/// it and nothing happened" happens.
class DietPlanDetailsPage extends StatefulWidget {
  const DietPlanDetailsPage({required this.plan, super.key});

  final DietPlan plan;

  @override
  State<DietPlanDetailsPage> createState() => _DietPlanDetailsPageState();
}

class _DietPlanDetailsPageState extends State<DietPlanDetailsPage> {
  Stream<Set<String>>? _consumedStream;
  Stream<List<FoodLogEntry>>? _logStream;
  final DateTime _now = DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final diet = AppScope.of(context).diet;
    _consumedStream ??= diet.watchConsumed(_now);
    _logStream ??= diet.watchFoodLog(_now);
  }

  @override
  Widget build(BuildContext context) {
    final diet = AppScope.of(context).diet;
    final plan = widget.plan;
    final today = dayForDate(plan, _now);
    return TrainScreen(
      tint: TrainColors.dietTint,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
            child: TrainPageHeader(title: l(context).dietPlanDetails),
          ),
          Expanded(
            child: StreamBuilder<NutritionTargets?>(
              stream: diet.watchTargets(),
              initialData: diet.currentTargets,
              builder: (context, targetsSnapshot) {
                final targets = targetsSnapshot.data;
                return StreamBuilder<List<FoodLogEntry>>(
                  stream: _logStream,
                  initialData: const <FoodLogEntry>[],
                  builder: (context, logSnapshot) =>
                      StreamBuilder<Set<String>>(
                        stream: _consumedStream,
                        initialData: const <String>{},
                        builder: (context, consumedSnapshot) =>
                            BodyMeasuresBuilder(
                              builder: (context, measures, calibration) =>
                                  _body(
                                    context,
                                    plan: plan,
                                    today: today,
                                    targets: targets,
                                    log:
                                        logSnapshot.data ??
                                        const <FoodLogEntry>[],
                                    consumed:
                                        consumedSnapshot.data ??
                                        const <String>{},
                                    measures: measures,
                                    calibration: calibration,
                                  ),
                            ),
                      ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context, {
    required DietPlan plan,
    required DietDay? today,
    required NutritionTargets? targets,
    required List<FoodLogEntry> log,
    required Set<String> consumed,
    required BodyMeasuresResolution measures,
    required CalibrationResult calibration,
  }) {
    // One state for this page, exactly as the Diet screen builds one for its
    // own frame — same builder, same inputs, so the two screens cannot quote
    // different figures for the same day.
    final body = measures.measures;
    final state = buildDietState(
      dayKey: dietDayKey(_now),
      weekday: _now.weekday,
      energy: body == null
          ? null
          : EnergyState(
              maintenanceKcal: body.maintenanceKcal,
              source: body.maintenanceSource,
            ),
      targets: targets,
      planName: plan.name,
      day: today,
      consumedMealIds: consumed,
      log: log,
    );
    final macroBars = state.quality.targetsUnset
        ? const <MacroProgress>[]
        : state.trackedMacros;
    return ListView(
      padding: EdgeInsets.fromLTRB(22, 14, 22, TrainBottomInset.of(context)),
      children: [
        // The day's consumed figure, and — inseparably — what it rests on.
        // The Diet screen shows only "kcal left", which asserts nothing about
        // how you got there; this says "eaten", so it owes the user the
        // qualifier the coach is also held to: ticking plan meals is not
        // weighed food (see diet/FEATURE.md).
        const TrainSectionLabel('Today so far'),
        const SizedBox(height: 11),
        TrainCard(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${approx(state.consumed.estimated)}${state.consumed.kcal} '
                '${l(context).unitKcal} eaten',
                style: TrainType.ui(
                  size: 17,
                  weight: FontWeight.w700,
                  color: TrainColors.inkPlain,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                consumedBasisShortLabel(state.consumed.basis).toUpperCase(),
                key: const Key('consumed-basis'),
                style: TrainType.caption(
                  size: 8.5,
                  tracking: 0.14,
                  color: TrainColors.ink4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const TrainSectionLabel('Your target'),
        const SizedBox(height: 11),
        if (targets == null)
          _NoTargetCard(plan: plan, onSet: () => _openTargets(context, null))
        else
          _TargetSummaryRow(
            targets: targets,
            onEdit: () => _openTargets(context, targets),
          ),
        if (macroBars.isNotEmpty) ...[
          const SizedBox(height: 20),
          const TrainSectionLabel('Macros today'),
          const SizedBox(height: 11),
          TrainCard(
            radius: 20,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Column(
              children: [
                for (final macro in macroBars)
                  _MacroBar(
                    label: macro.label.toUpperCase(),
                    eaten: macro.consumed,
                    target: macro.target!,
                    estimated: macro.estimated,
                    color: _macroColor(macro.label),
                    loading: false,
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        const TrainSectionLabel('What this plan does'),
        const SizedBox(height: 11),
        _PlanVerdictSection(
          plan: plan,
          measures: measures,
          calibration: calibration,
          onAddBodyData: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const BodyProfilePage())),
        ),
        if (targets != null) ...[
          const SizedBox(height: 20),
          const TrainSectionLabel("Today's read"),
          const SizedBox(height: 11),
          TodaysReadCard(state: state, localHour: _now.hour),
        ],
        const SizedBox(height: 20),
        TrainSectionLabel(
          'Full plan',
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
                    Text(l(context).targetsNoneSet, style: AppText.rowTitle),
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
  const _PlanVerdictSection({
    required this.plan,
    required this.measures,
    required this.calibration,
    required this.onAddBodyData,
  });

  final DietPlan plan;

  /// Assembled once by the screen above and passed in — see the note at the
  /// `BodyMeasuresBuilder` call site.
  final BodyMeasuresResolution measures;
  final CalibrationResult calibration;
  final VoidCallback onAddBodyData;

  @override
  Widget build(BuildContext context) {
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
        calibration: calibration,
        measures: resolved,
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
    required this.calibration,
    required this.measures,
    required this.onEditBodyData,
  });

  final PlanVerdict verdict;
  final int weighInAgeDays;

  /// The measurement of what this person actually burns, or what it's short
  /// of. Shown either way: a measured figure is the strongest thing on this
  /// card, and the reason there isn't one yet is actionable.
  final CalibrationResult calibration;
  final BodyMeasures measures;
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
          _CalibrationLine(calibration: calibration, measures: measures),
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

/// What this person's own data says they burn — or what it would take to know.
///
/// This is the strongest line on the card when it's there: every other figure
/// on this screen is a projection from a population equation, and this one is
/// an observation of them. When it disagrees materially with the figure the
/// verdict actually used, the disagreement is stated rather than resolved
/// silently — that only happens when the user gave a maintenance figure of
/// their own, and overriding what they told ZIVO is not the app's call.
class _CalibrationLine extends StatelessWidget {
  const _CalibrationLine({required this.calibration, required this.measures});

  final CalibrationResult calibration;
  final BodyMeasures measures;

  @override
  Widget build(BuildContext context) {
    final measured = calibration.measured;
    if (measured == null) {
      final gap = calibration.gap;
      if (gap == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Log ${calibrationGapLabel(gap)} and ZIVO can measure what you '
          'actually burn, instead of estimating it.',
          key: const Key('verdict-calibration-gap'),
          style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.4),
        ),
      );
    }

    final used = measures.maintenanceKcal;
    final disagrees =
        measures.maintenanceSource != MaintenanceSource.measured &&
        maintenanceDisagrees(measured.maintenanceKcal, used);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        disagrees
            ? 'Your last ${measured.days} days say you actually burn about '
                  '${measured.maintenanceKcal} — not the $used above. Worth '
                  'updating.'
            : 'Measured from your last ${measured.days} days: '
                  '${measured.averageIntakeKcal} kcal a day eaten, '
                  '${_change(measured)}.',
        key: const Key('verdict-calibration'),
        style: AppText.meta.copyWith(
          color: disagrees ? TrainColors.ember : TrainColors.ink3,
          height: 1.4,
        ),
      ),
    );
  }

  static String _change(MeasuredMaintenance measured) {
    final kg = measured.weightChangeKg;
    if (kg.abs() < 0.2) return 'weight steady';
    final direction = kg > 0 ? 'up' : 'down';
    return 'weight $direction ${formatKgPerWeek(kg)} kg';
  }
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
