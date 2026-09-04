import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/util/parse.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/body_measures.dart';
import '../../domain/diet_goal.dart';
import '../../domain/nutrition_targets.dart';
import '../../domain/target_calculator.dart';
import '../widgets/diet_number_field.dart';
import 'body_profile_page.dart';
import '../../../../l10n/l10n.dart';
import '../diet_labels.dart';

/// Where the user says what they are actually trying to do, and what numbers
/// serve it.
///
/// **The whole point of this screen is that ZIVO does not decide.** Nothing
/// here writes a target the user hasn't looked at: the calculator fills the
/// fields as a proposal they can edit or ignore, and only Save persists
/// anything. An auto-derived target the user never approved would be exactly
/// the trust failure this feature exists to end — a number nobody chose,
/// presented as an objective.
class DietTargetsPage extends StatefulWidget {
  const DietTargetsPage({this.initial, super.key});

  /// The user's current targets, or null when they have none yet.
  final NutritionTargets? initial;

  @override
  State<DietTargetsPage> createState() => _DietTargetsPageState();
}

class _DietTargetsPageState extends State<DietTargetsPage> {
  late DietGoal? _goal = widget.initial?.goal;
  late final TextEditingController _calories = TextEditingController(
    text: widget.initial?.calories.toString() ?? '',
  );
  late final TextEditingController _protein = _gramsController(
    widget.initial?.proteinG,
  );
  late final TextEditingController _carbs = _gramsController(
    widget.initial?.carbsG,
  );
  late final TextEditingController _fat = _gramsController(
    widget.initial?.fatG,
  );

  /// How the numbers currently in the fields came to be there. Starts as
  /// whatever produced the saved target; becomes [TargetSource.calculated]
  /// when the calculator fills them, and drops back to [TargetSource.manual]
  /// the moment the user edits a field — because a hand-edited figure is no
  /// longer the one the formula produced, and claiming otherwise would make
  /// the stored basis a lie.
  late TargetSource _source = widget.initial?.source ?? TargetSource.manual;
  late TargetBasis? _basis = widget.initial?.basis;

  bool _saving = false;

  static TextEditingController _gramsController(double? grams) =>
      TextEditingController(
        text: grams == null
            ? ''
            : (grams == grams.roundToDouble()
                  ? grams.round().toString()
                  : grams.toStringAsFixed(1)),
      );

  @override
  void initState() {
    super.initState();
    for (final c in [_calories, _protein, _carbs, _fat]) {
      c.addListener(_onFieldEdited);
    }
  }

  @override
  void dispose() {
    for (final c in [_calories, _protein, _carbs, _fat]) {
      c.removeListener(_onFieldEdited);
      c.dispose();
    }
    super.dispose();
  }

  /// Any manual edit demotes the source — see [_source].
  void _onFieldEdited() {
    if (_source == TargetSource.calculated && !_applyingProposal) {
      setState(() {
        _source = TargetSource.manual;
        _basis = null;
      });
    } else {
      setState(() {});
    }
  }

  /// Guards [_onFieldEdited] while the calculator is writing into the fields,
  /// so filling them doesn't immediately demote the source it just set.
  bool _applyingProposal = false;

  int? get _caloriesValue => parsePositiveInt(_calories.text);

  double? _grams(TextEditingController c) => parsePositiveDecimal(c.text);

  bool get _canSave => _goal != null && _caloriesValue != null && !_saving;

  bool get _belowFloor {
    final calories = _caloriesValue;
    return calories != null && targetIsBelowSafetyFloor(calories);
  }

  Future<void> _openCalculator() async {
    final scope = AppScope.of(context);

    // Body data is READ here, never asked for. Height, sex and activity live
    // in the body profile; weight is the workout feature's weigh-in log; age
    // comes from the account's date of birth. `resolveBodyMeasures` is the one
    // place that knows how to put those three together.
    //
    // This sheet used to render the same fields again, prefilled — which meant
    // a user could type a weight here that never reached the weigh-in log, and
    // ZIVO would then hold two different weights and disagree with itself
    // about maintenance. Asked once, in one place, or not at all.
    final weights = scope.bodyWeight?.current ?? const [];
    DateTime? dateOfBirth;
    final uid = scope.auth.currentUser?.uid;
    if (uid != null) {
      try {
        final profile = await scope.profiles.fetchProfile(uid);
        dateOfBirth = profile?.dateOfBirth;
      } catch (_) {
        // Offline or unreadable: treated as missing, which routes the user to
        // the body-data screen rather than to a guessed age.
      }
    }
    if (!mounted) return;

    final resolution = resolveBodyMeasures(
      profile: scope.diet.currentBodyProfile,
      latestWeightKg: weights.isEmpty ? null : weights.first.weightKg,
      weighedAt: weights.isEmpty ? null : weights.first.loggedAt,
      dateOfBirth: dateOfBirth,
      now: DateTime.now(),
    );

    // Something's missing: send them to the one screen that collects it,
    // rather than growing a second form here.
    if (!resolution.isComplete) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const BodyProfilePage()));
      return;
    }

    final measures = resolution.measures!;
    final confirmed = await showZivoSheet<bool>(
      context: context,
      builder: (_) => _CalculatorSheet(
        goal: _goal ?? DietGoal.maintain,
        measures: measures,
      ),
    );
    if (confirmed != true || !mounted) return;

    final proposal = calculateTargets(
      weightKg: measures.weightKg,
      heightCm: measures.heightCm,
      age: measures.age,
      sex: measures.sex,
      activity: measures.activity,
      goal: _goal ?? DietGoal.maintain,
      now: DateTime.now(),
    );

    // Fill the fields — a proposal to review, not a saved target.
    _applyingProposal = true;
    _calories.text = proposal.targets.calories.toString();
    _protein.text = _gramsController(proposal.targets.proteinG).text;
    _carbs.text = _gramsController(proposal.targets.carbsG).text;
    _fat.text = _gramsController(proposal.targets.fatG).text;
    _applyingProposal = false;
    setState(() {
      _source = TargetSource.calculated;
      _basis = proposal.basis;
    });
  }

  Future<void> _save() async {
    final goal = _goal;
    final calories = _caloriesValue;
    if (goal == null || calories == null) return;
    setState(() => _saving = true);
    final diet = AppScope.of(context).diet;
    final navigator = Navigator.of(context);
    await diet.saveTargets(
      NutritionTargets(
        goal: goal,
        calories: calories,
        proteinG: _grams(_protein),
        carbsG: _grams(_carbs),
        fatG: _grams(_fat),
        source: _source,
        basis: _source == TargetSource.calculated ? _basis : null,
        updatedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    HapticFeedback.lightImpact();
    navigator.pop();
  }

  Future<void> _remove() async {
    final diet = AppScope.of(context).diet;
    final navigator = Navigator.of(context);
    await diet.clearTargets();
    if (!mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return TrainScreen(
      tint: TrainColors.dietTint,
      child: Column(
        children: [
          CaptureTopBar(
            title: widget.initial == null
                ? l(context).dietSetYourTarget
                : l(context).dietDailyTarget,
            onClose: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              key: const Key('targets-list'),
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
              children: [
                Text(
                  l(context).dietTargetsIntro,
                  style: AppText.body.copyWith(
                    color: TrainColors.ink2,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                TrainSectionLabel(l(context).dietGoal),
                const SizedBox(height: 11),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final goal in DietGoal.values)
                      SelectChip(
                        key: Key('goal-${goal.name}'),
                        label: dietGoalText(context, goal),
                        selected: _goal == goal,
                        onTap: () => setState(() => _goal = goal),
                      ),
                  ],
                ),
                if (_goal != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    dietGoalDetailText(context, _goal!),
                    style: AppText.meta.copyWith(color: TrainColors.ink3),
                  ),
                ],
                const SizedBox(height: 26),
                TrainSectionLabel(
                  l(context).dietDailyNumbers,
                  trailing: _source == TargetSource.calculated
                      ? l(context).dietCalculatedCaps
                      : null,
                ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    DietNumberField(
                      label: l(context).nutritionCalories,
                      controller: _calories,
                      hint: '2200',
                      fieldKey: const Key('target-calories'),
                      decimal: false,
                    ),
                    const SizedBox(width: 12),
                    DietNumberField(
                      label: l(context).nutritionProtein,
                      controller: _protein,
                      hint: '—',
                      fieldKey: const Key('target-protein'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    DietNumberField(
                      label: l(context).nutritionCarbs,
                      controller: _carbs,
                      hint: '—',
                      fieldKey: const Key('target-carbs'),
                    ),
                    const SizedBox(width: 12),
                    DietNumberField(
                      label: l(context).nutritionFat,
                      controller: _fat,
                      hint: '—',
                      fieldKey: const Key('target-fat'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  l(context).dietOnlyCaloriesRequired,
                  style: AppText.meta.copyWith(color: TrainColors.ink3),
                ),
                if (_belowFloor) ...[
                  const SizedBox(height: 16),
                  _SafetyNote(calories: _caloriesValue!),
                ],
                const SizedBox(height: 18),
                TrainDashedCard(
                  onTap: _openCalculator,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calculate_outlined,
                        size: 18,
                        color: TrainColors.ink2,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l(context).targetsFromBodyData,
                              style: AppText.rowTitle,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              l(context).dietFillFieldsHint,
                              style: AppText.meta.copyWith(
                                color: TrainColors.ink3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_basis != null && _source == TargetSource.calculated) ...[
                  const SizedBox(height: 14),
                  _BasisNote(basis: _basis!, goal: _goal ?? DietGoal.maintain),
                ],
                const SizedBox(height: 26),
                PillButton(
                  key: const Key('save-targets'),
                  label: l(context).targetsSave,
                  icon: Icons.check_rounded,
                  enabled: _canSave,
                  onTap: _save,
                ),
                if (widget.initial != null) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      key: const Key('remove-targets'),
                      onPressed: _remove,
                      child: Text(
                        l(context).actionRemove,
                        style: AppText.meta.copyWith(color: TrainColors.ink3),
                      ),
                    ),
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

/// The deterministic low-calorie warning. Shown rather than clamping the
/// number: silently "fixing" it would hide that the user is heading somewhere
/// a training app has no business coaching them through.
class _SafetyNote extends StatelessWidget {
  const _SafetyNote({required this.calories});

  final int calories;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('target-safety-note'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: TrainColors.ember.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TrainColors.ember.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 17,
            color: TrainColors.ember,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              l(context).dietBelowSafeWarning(calories, kMinimumSafeCalories),
              style: AppText.meta.copyWith(
                color: TrainColors.ink2,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the calculator's working, so a calculated figure is never a number
/// out of nowhere.
class _BasisNote extends StatelessWidget {
  const _BasisNote({required this.basis, required this.goal});

  final TargetBasis basis;
  final DietGoal goal;

  @override
  Widget build(BuildContext context) {
    final weight = basis.weightKg == basis.weightKg.roundToDouble()
        ? basis.weightKg.round().toString()
        : basis.weightKg.toStringAsFixed(1);
    return Text(
      l(context).dietCalculatedFrom(
        weight,
        activityText(context, basis.activity).toLowerCase(),
        basis.bmr,
        basis.maintenanceCalories,
        dietGoalText(context, goal).toLowerCase(),
      ),
      style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.45),
    );
  }
}

/// A labelled number field. Mirrors the plan editor's `_NumberField` so the
/// two capture surfaces read as one system.
/// Collects the inputs Mifflin-St Jeor needs and returns a [TargetProposal].
/// Returns null if the user backs out — and returns a proposal, never a saved
/// target: the caller puts the numbers in front of the user to approve.
/// What ZIVO will run the equation on — shown, not asked.
///
/// Everything here is already stored somewhere the user entered it once. The
/// sheet exists so the figures aren't applied invisibly (a stale weigh-in is
/// the common case, and it moves every number downstream), and its "Change"
/// route is the body-data screen — the single place any of this is edited.
class _CalculatorSheet extends StatelessWidget {
  const _CalculatorSheet({required this.goal, required this.measures});

  final DietGoal goal;
  final BodyMeasures measures;

  @override
  Widget build(BuildContext context) {
    final stale = measures.weighInAgeDays(DateTime.now());
    return Container(
      decoration: const BoxDecoration(
        color: TrainColors.raised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
      child: SingleChildScrollView(
        key: const Key('calculator-scroll'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l(context).targetsZivoWillUse, style: AppText.rowTitle),
            const SizedBox(height: 14),
            _Fact(
              factKey: const Key('calc-fact-weight'),
              label: l(context).bodyWeightLabel,
              value: l(context).dietKgValue(_trim(measures.weightKg)),
            ),
            _Fact(
              factKey: const Key('calc-fact-height'),
              label: l(context).bodyHeightLabel,
              value: l(context).dietCmValue(measures.heightCm.round()),
            ),
            _Fact(
              factKey: const Key('calc-fact-age'),
              label: l(context).bodyAgeLabel,
              value: '${measures.age}',
            ),
            _Fact(
              label: l(context).bodySexQuestion,
              value: measures.sex == TargetSex.male
                  ? l(context).dietSexMale
                  : l(context).dietSexFemale,
            ),
            _Fact(
              label: l(context).bodyActivityLabel,
              value: activityText(context, measures.activity),
              last: true,
            ),
            // A four-month-old weigh-in is the usual reason a calculated
            // target is wrong, and it is invisible unless said.
            if (stale > kWeighInStaleAfterDays) ...[
              const SizedBox(height: 14),
              Text(
                l(context).dietStaleWeighInPrompt(stale),
                key: const Key('calc-stale-weight'),
                style: AppText.meta.copyWith(color: TrainColors.ember),
              ),
            ],
            const SizedBox(height: 22),
            PillButton(
              key: const Key('run-calculator'),
              label: l(context).targetsFillFields,
              icon: Icons.arrow_forward_rounded,
              enabled: true,
              onTap: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                key: const Key('calc-change-body-data'),
                onPressed: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(
                    MaterialPageRoute(builder: (_) => const BodyProfilePage()),
                  );
                },
                child: Text(
                  l(context).targetsChangeBodyData,
                  style: AppText.meta.copyWith(color: TrainColors.ink3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One stored fact, stated flatly. Not a field — nothing here is editable on
/// this sheet by design.
/// "82" not "82.0"; "82.4" when the decimal is real.
String _trim(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.factKey,
    this.last = false,
  });

  final String label;
  final String value;
  final Key? factKey;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: factKey,
      padding: EdgeInsets.only(bottom: last ? 0 : 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppText.meta.copyWith(color: TrainColors.ink3),
            ),
          ),
          Text(value, style: AppText.rowTitle),
        ],
      ),
    );
  }
}
