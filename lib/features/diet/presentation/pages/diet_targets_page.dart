import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../domain/diet_goal.dart';
import '../../domain/nutrition_targets.dart';
import '../../domain/target_calculator.dart';

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

  int? get _caloriesValue {
    final parsed = int.tryParse(_calories.text.trim());
    return (parsed == null || parsed <= 0) ? null : parsed;
  }

  double? _grams(TextEditingController c) {
    final parsed = double.tryParse(c.text.trim().replaceAll(',', '.'));
    return (parsed == null || parsed <= 0) ? null : parsed;
  }

  bool get _canSave => _goal != null && _caloriesValue != null && !_saving;

  bool get _belowFloor {
    final calories = _caloriesValue;
    return calories != null && targetIsBelowSafetyFloor(calories);
  }

  Future<void> _openCalculator() async {
    final scope = AppScope.of(context);

    // Prefill from what the app already knows rather than asking twice: the
    // most recent weigh-in from the workout feature's body-weight log, and
    // age from the profile's date of birth. Both are best-effort — a failure
    // to read either just means an empty field, never a guessed value.
    final weights = scope.bodyWeight?.current ?? const [];
    final latestWeight = weights.isEmpty ? null : weights.first.weightKg;

    int? age;
    final uid = scope.auth.currentUser?.uid;
    if (uid != null) {
      try {
        final profile = await scope.profiles.fetchProfile(uid);
        if (profile != null) age = ageFrom(profile.dateOfBirth, DateTime.now());
      } catch (_) {
        // Offline or unreadable: fall through with no prefill.
      }
    }
    if (!mounted) return;

    final proposal = await showModalBottomSheet<TargetProposal>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CalculatorSheet(
        goal: _goal ?? DietGoal.maintain,
        initialWeightKg: latestWeight,
        initialAge: age,
      ),
    );
    if (proposal == null || !mounted) return;

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
            title: widget.initial == null ? 'Set your target' : 'Daily target',
            onClose: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              key: const Key('targets-list'),
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
              children: [
                Text(
                  'Your coach uses these numbers for everything it tells you. '
                  "Until they're set, it can describe your plan but not how "
                  "you're doing against it.",
                  style: AppText.body.copyWith(
                    color: TrainColors.ink2,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                const TrainSectionLabel('Goal'),
                const SizedBox(height: 11),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final goal in DietGoal.values)
                      SelectChip(
                        key: Key('goal-${goal.name}'),
                        label: dietGoalLabel(goal),
                        selected: _goal == goal,
                        onTap: () => setState(() => _goal = goal),
                      ),
                  ],
                ),
                if (_goal != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    dietGoalDescription(_goal!),
                    style: AppText.meta.copyWith(color: TrainColors.ink3),
                  ),
                ],
                const SizedBox(height: 26),
                TrainSectionLabel(
                  'Daily numbers',
                  trailing: _source == TargetSource.calculated
                      ? 'CALCULATED'
                      : null,
                ),
                const SizedBox(height: 11),
                Row(
                  children: [
                    _TargetField(
                      label: 'Calories',
                      controller: _calories,
                      hint: '2200',
                      fieldKey: const Key('target-calories'),
                      decimal: false,
                    ),
                    const SizedBox(width: 12),
                    _TargetField(
                      label: 'Protein (g)',
                      controller: _protein,
                      hint: '—',
                      fieldKey: const Key('target-protein'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _TargetField(
                      label: 'Carbs (g)',
                      controller: _carbs,
                      hint: '—',
                      fieldKey: const Key('target-carbs'),
                    ),
                    const SizedBox(width: 12),
                    _TargetField(
                      label: 'Fat (g)',
                      controller: _fat,
                      hint: '—',
                      fieldKey: const Key('target-fat'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Only calories are required. Leave a macro blank if you '
                  "aren't tracking it — blank means untracked, not zero.",
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
                              'Work it out from my body data',
                              style: AppText.rowTitle,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Fills the fields with a starting point you can '
                              'edit. Nothing is saved until you tap Save.',
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
                  label: 'Save target',
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
                        'Remove target',
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
        border: Border.all(
          color: TrainColors.ember.withValues(alpha: 0.30),
        ),
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
              '$calories kcal is below $kMinimumSafeCalories, which is under '
              'what ZIVO should be coaching. You can still save it, but eating '
              'this low is worth talking through with a doctor or a registered '
              'dietitian first.',
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
      'From ${weight}kg at ${activityLabel(basis.activity).toLowerCase()} '
      'activity: ${basis.bmr} kcal at rest, '
      '${basis.maintenanceCalories} kcal to maintain, adjusted for '
      '${dietGoalLabel(goal).toLowerCase()}. These are population estimates — '
      'adjust them from what the scale actually does.',
      style: AppText.meta.copyWith(color: TrainColors.ink3, height: 1.45),
    );
  }
}

/// A labelled number field. Mirrors the plan editor's `_NumberField` so the
/// two capture surfaces read as one system.
class _TargetField extends StatelessWidget {
  const _TargetField({
    required this.label,
    required this.controller,
    required this.fieldKey,
    this.hint,
    this.decimal = true,
  });

  final String label;
  final TextEditingController controller;
  final Key fieldKey;
  final String? hint;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppText.meta.copyWith(
              color: TrainColors.ink3,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: fieldKey,
            controller: controller,
            keyboardType: TextInputType.numberWithOptions(decimal: decimal),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
              ),
            ],
            cursorColor: TrainColors.green,
            style: AppText.rowTitle,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: AppText.rowTitle.copyWith(color: TrainColors.ink3),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 12,
              ),
              filled: true,
              fillColor: TrainColors.base,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Collects the inputs Mifflin-St Jeor needs and returns a [TargetProposal].
/// Returns null if the user backs out — and returns a proposal, never a saved
/// target: the caller puts the numbers in front of the user to approve.
class _CalculatorSheet extends StatefulWidget {
  const _CalculatorSheet({
    required this.goal,
    this.initialWeightKg,
    this.initialAge,
  });

  final DietGoal goal;

  /// Prefilled from the user's most recent weigh-in, so they aren't asked for
  /// something the app already knows.
  final double? initialWeightKg;

  /// Prefilled from the profile's date of birth.
  final int? initialAge;

  @override
  State<_CalculatorSheet> createState() => _CalculatorSheetState();
}

class _CalculatorSheetState extends State<_CalculatorSheet> {
  late final TextEditingController _weight = TextEditingController(
    text: widget.initialWeightKg == null
        ? ''
        : widget.initialWeightKg!.toStringAsFixed(
            widget.initialWeightKg! == widget.initialWeightKg!.roundToDouble()
                ? 0
                : 1,
          ),
  );
  late final TextEditingController _height = TextEditingController();
  late final TextEditingController _age = TextEditingController(
    text: widget.initialAge?.toString() ?? '',
  );
  TargetSex? _sex;
  ActivityLevel _activity = ActivityLevel.moderate;

  @override
  void dispose() {
    _weight.dispose();
    _height.dispose();
    _age.dispose();
    super.dispose();
  }

  double? get _weightKg {
    final v = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    return (v == null || v <= 0) ? null : v;
  }

  double? get _heightCm {
    final v = double.tryParse(_height.text.trim().replaceAll(',', '.'));
    return (v == null || v <= 0) ? null : v;
  }

  int? get _ageYears {
    final v = int.tryParse(_age.text.trim());
    return (v == null || v <= 0) ? null : v;
  }

  bool get _canCalculate =>
      _weightKg != null && _heightCm != null && _ageYears != null && _sex != null;

  void _calculate() {
    if (!_canCalculate) return;
    Navigator.of(context).pop(
      calculateTargets(
        weightKg: _weightKg!,
        heightCm: _heightCm!,
        age: _ageYears!,
        sex: _sex!,
        activity: _activity,
        goal: widget.goal,
        now: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: TrainColors.raised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 22,
        right: 22,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        key: const Key('calculator-scroll'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your numbers', style: AppText.rowTitle),
            const SizedBox(height: 4),
            Text(
              'Used once, on this device, to work out a starting point.',
              style: AppText.meta.copyWith(color: TrainColors.ink3),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _TargetField(
                  label: 'Weight (kg)',
                  controller: _weight,
                  hint: '82',
                  fieldKey: const Key('calc-weight'),
                ),
                const SizedBox(width: 12),
                _TargetField(
                  label: 'Height (cm)',
                  controller: _height,
                  hint: '178',
                  fieldKey: const Key('calc-height'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _TargetField(
                  label: 'Age',
                  controller: _age,
                  hint: '27',
                  fieldKey: const Key('calc-age'),
                  decimal: false,
                ),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              // Said plainly, because being asked for this without a reason
              // is a fair thing to wonder about.
              'THE BMR FORMULA USES THIS',
              style: AppText.meta.copyWith(
                color: TrainColors.ink3,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              children: [
                for (final sex in TargetSex.values)
                  SelectChip(
                    key: Key('calc-sex-${sex.name}'),
                    label: sex == TargetSex.male ? 'Male' : 'Female',
                    selected: _sex == sex,
                    onTap: () => setState(() => _sex = sex),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'ACTIVITY',
              style: AppText.meta.copyWith(
                color: TrainColors.ink3,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final level in ActivityLevel.values)
                  SelectChip(
                    key: Key('calc-activity-${level.name}'),
                    label: activityLabel(level),
                    selected: _activity == level,
                    onTap: () => setState(() => _activity = level),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              activityDescription(_activity),
              style: AppText.meta.copyWith(color: TrainColors.ink3),
            ),
            const SizedBox(height: 22),
            PillButton(
              key: const Key('run-calculator'),
              label: 'Fill the fields',
              icon: Icons.arrow_forward_rounded,
              enabled: _canCalculate,
              onTap: _calculate,
            ),
          ],
        ),
      ),
    );
  }
}
