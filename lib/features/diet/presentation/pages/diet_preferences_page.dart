import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/scope/app_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/train_surfaces.dart';
import '../../../../core/widgets/zivo_field.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/common_foods.dart';
import '../../domain/nutrition_targets.dart';
import '../../domain/plan_preferences.dart';
import '../widgets/food_chip_picker.dart';
import 'diet_import_page.dart';
import 'diet_targets_page.dart';

/// What ZIVO asks before it builds someone a diet.
///
/// Everything on this screen is something **only the user knows**. Their
/// calories come from their target and their body data; their foods' calories
/// come from the catalog. What is left — how often they eat, what they like,
/// what they won't touch, what they can't touch — is the whole of it, and
/// asking for anything more would be a form.
///
/// Allergies sit apart from "won't eat" on purpose, in their own section with
/// their own words: one is a preference the model is asked to respect, the
/// other is a limit the server checks deterministically after generation and
/// refuses the plan over.
class DietPreferencesPage extends StatefulWidget {
  const DietPreferencesPage({super.key});

  @override
  State<DietPreferencesPage> createState() => _DietPreferencesPageState();
}

class _DietPreferencesPageState extends State<DietPreferencesPage> {
  // Tapped, not typed. Held as English chip ids (see `common_foods.dart`) —
  // the generator resolves against an English catalog, so the id is what
  // travels and only the label is localized.
  List<String> _likes = const [];
  List<String> _avoid = const [];
  List<String> _allergies = const [];

  /// The one thing a chip genuinely can't carry: whatever this person knows
  /// about their eating that no fixed list anticipated.
  final TextEditingController _notes = TextEditingController();

  int _mealsPerDay = 3;
  String? _cuisine;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  PlanPreferences get _preferences => PlanPreferences(
    mealsPerDay: _mealsPerDay,
    likes: _likes,
    avoid: _avoid,
    allergies: _allergies,
    cuisine: _cuisine,
    notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
  );

  Future<void> _build() async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DietImportPage(generateFrom: _preferences),
      ),
    );
    // The proposal flow pops itself once the review editor closes, so landing
    // back here means it is finished either way.
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openTargets(NutritionTargets? current) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DietTargetsPage(initial: current)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final targets = AppScope.of(context).diet.currentTargets;

    return TrainScreen(
      tint: TrainColors.dietTint,
      child: Column(
        children: [
          CaptureTopBar(
            title: l(context).prefsBuildTitle,
            onClose: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ListView(
              key: const Key('preferences-list'),
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
              children: [
                Text(
                  'ZIVO picks the foods and looks up what they actually '
                  "weigh in calories — it doesn't guess them. Tell it what "
                  'you eat and it will build a day you can review before '
                  'anything is saved.',
                  style: AppText.body.copyWith(
                    color: TrainColors.ink2,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                _TargetNote(
                  targets: targets,
                  onSetTarget: () => _openTargets(targets),
                ),
                const SizedBox(height: 26),
                const TrainSectionLabel('Meals a day'),
                const SizedBox(height: 11),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (var n = kMinMealsPerDay; n <= 6; n++)
                      SelectChip(
                        key: Key('meals-$n'),
                        label: '$n',
                        selected: _mealsPerDay == n,
                        onTap: () => setState(() => _mealsPerDay = n),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'The single biggest reason a plan survives a working week, '
                  'or does not.',
                  style: AppText.meta.copyWith(color: TrainColors.ink3),
                ),
                const SizedBox(height: 26),
                const TrainSectionLabel('Kitchen', trailing: 'OPTIONAL'),
                const SizedBox(height: 11),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final cuisine in _kCuisines)
                      SelectChip(
                        key: Key('cuisine-${cuisine.toLowerCase()}'),
                        label: cuisine,
                        selected: _cuisine == cuisine,
                        // Tapping the selected one clears it — a steer you
                        // can't take back is a trap.
                        onTap: () => setState(
                          () => _cuisine = _cuisine == cuisine ? null : cuisine,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 26),
                FoodChipPicker(
                  keyPrefix: 'prefs-likes',
                  heading: l(context).prefsLikes,
                  note: l(context).prefsLikesNote,
                  optionIds: kCommonFoodIds,
                  labelFor: commonFoodLabel,
                  selected: _likes,
                  onChanged: (v) => setState(() => _likes = v),
                ),
                const SizedBox(height: 24),
                FoodChipPicker(
                  keyPrefix: 'prefs-avoid',
                  heading: l(context).prefsAvoid,
                  note: l(context).prefsAvoidNote,
                  optionIds: kCommonFoodIds,
                  labelFor: commonFoodLabel,
                  selected: _avoid,
                  onChanged: (v) => setState(() => _avoid = v),
                ),
                const SizedBox(height: 24),
                // Its own list and its own words: "won't eat" is a preference
                // the model is asked to respect, an allergy is a gate the
                // server enforces after generation and refuses the plan over.
                FoodChipPicker(
                  keyPrefix: 'prefs-allergies',
                  heading: l(context).prefsAllergies,
                  note: l(context).prefsAllergiesNote,
                  noteColor: TrainColors.ember,
                  optionIds: kCommonAllergenIds,
                  labelFor: commonAllergenLabel,
                  selected: _allergies,
                  onChanged: (v) => setState(() => _allergies = v),
                ),
                const SizedBox(height: 24),
                _NotesField(
                  label: l(context).prefsNotes,
                  hint: l(context).prefsNotesHint,
                  controller: _notes,
                  fieldKey: const Key('prefs-notes'),
                ),
                const SizedBox(height: 26),
                PillButton(
                  key: const Key('prefs-build'),
                  label: l(context).prefsBuild,
                  icon: Icons.auto_awesome_rounded,
                  enabled: _preferences.isUsable,
                  onTap: _build,
                ),
                const SizedBox(height: 10),
                Text(
                  'Nothing is saved until you review the plan and tap Save.',
                  style: AppText.meta.copyWith(color: TrainColors.ink3),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The kitchens worth offering as one tap. Not exhaustive — "Anything else"
/// takes the rest — but a generator with no steer produces the same
/// chicken-and-broccoli plan for everybody, so the common ones are here.
const _kCuisines = [
  'Egyptian',
  'Mediterranean',
  'Levantine',
  'Indian',
  'Asian',
  'Western',
];

/// Whether the plan will be sized to anything. A target is not required — a
/// plan built without one is still a plan — but the difference is worth
/// saying before the build rather than explaining after it.
class _TargetNote extends StatelessWidget {
  const _TargetNote({required this.targets, required this.onSetTarget});

  final NutritionTargets? targets;
  final VoidCallback onSetTarget;

  @override
  Widget build(BuildContext context) {
    if (targets != null) {
      return Row(
        children: [
          const Icon(Icons.flag_outlined, size: 16, color: TrainColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sized to your target — ${targets!.calories} kcal a day.',
              key: const Key('prefs-target-note'),
              style: AppText.meta.copyWith(color: TrainColors.ink2),
            ),
          ),
        ],
      );
    }
    return TrainDashedCard(
      key: const Key('prefs-no-target'),
      onTap: onSetTarget,
      child: Row(
        children: [
          const Icon(Icons.flag_outlined, size: 18, color: TrainColors.ink2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l(context).targetsNoneSet, style: AppText.rowTitle),
                const SizedBox(height: 3),
                Text(
                  'ZIVO will still build the plan, but it has no figure to '
                  'size the portions to. Set one first and the day comes out '
                  'fitted to it.',
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

/// The screen's one free-text field — and the only one it should ever have.
///
/// Everything else here is a chip, because everything else here has a common
/// answer. This doesn't: "I train at 6am and eat straight after" is a fact no
/// fixed list anticipates, and losing it to make the screen uniform would cost
/// the generator the most useful thing on the page.
class _NotesField extends StatelessWidget {
  const _NotesField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.fieldKey,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final Key fieldKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.rowTitle),
        const SizedBox(height: 11),
        TextField(
          key: fieldKey,
          controller: controller,
          maxLines: null,
          minLines: 3,
          textCapitalization: TextCapitalization.sentences,
          cursorColor: TrainColors.green,
          style: AppText.body.copyWith(color: TrainColors.ink, height: 1.5),
          decoration: zivoFieldDecoration(
            hintText: hint,
            hintStyle: AppText.body.copyWith(color: TrainColors.ink3),
            contentPadding: const EdgeInsets.all(14),
            radius: 14,
            focusRing: false,
          ),
        ),
      ],
    );
  }
}
