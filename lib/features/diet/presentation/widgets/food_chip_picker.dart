import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/train_tokens.dart';
import '../../../../core/widgets/zivo_sheet.dart';
import '../../../../core/widgets/zivo_field.dart';
import '../../../../l10n/l10n.dart';
import '../../../capture/presentation/widgets/capture_widgets.dart';

/// Picking foods by tapping, with typing kept for the cases tapping can't
/// reach.
///
/// The rule this encodes: **a user should not have to spell a food to tell
/// ZIVO about it.** A comma-separated text box asks them to produce the
/// vocabulary, punctuate it, and spell it in a second language — on a phone,
/// before they have a plan at all. The chips carry the common answers; `Other`
/// is there because a fixed list can never cover an allergy or a regional
/// staple, and refusing those would be worse than the box was.
///
/// Chip ids are English and travel to the generator unchanged (see
/// `domain/common_foods.dart`); [labelFor] is only what the user reads.
class FoodChipPicker extends StatelessWidget {
  const FoodChipPicker({
    required this.heading,
    required this.note,
    required this.optionIds,
    required this.labelFor,
    required this.selected,
    required this.onChanged,
    required this.keyPrefix,
    this.noteColor,
    super.key,
  });

  final String heading;
  final String note;
  final Color? noteColor;

  /// The offered ids, in the order they're shown.
  final List<String> optionIds;

  /// Turns an id into what this user reads.
  final String Function(BuildContext, String) labelFor;

  /// The chosen ids — offered ones and typed ones alike, so a custom entry
  /// behaves exactly like a listed one once it exists.
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  final String keyPrefix;

  void _toggle(String id) {
    HapticFeedback.selectionClick();
    onChanged(
      selected.contains(id)
          ? (List<String>.from(selected)..remove(id))
          : (List<String>.from(selected)..add(id)),
    );
  }

  Future<void> _addCustom(BuildContext context) async {
    final value = await showZivoSheet<String>(
      context: context,
      builder: (_) => _CustomEntrySheet(title: l(context).prefsAddYourOwn),
    );
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty || selected.contains(trimmed)) return;
    onChanged(List<String>.from(selected)..add(trimmed));
  }

  @override
  Widget build(BuildContext context) {
    // Anything chosen that isn't one of the offered ids was typed, so it needs
    // a chip of its own — otherwise it would vanish the moment it was added.
    final custom = selected.where((s) => !optionIds.contains(s)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: AppText.rowTitle),
        const SizedBox(height: 11),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final id in optionIds)
              SelectChip(
                key: Key('$keyPrefix-${id.replaceAll(' ', '-')}'),
                label: labelFor(context, id),
                selected: selected.contains(id),
                onTap: () => _toggle(id),
              ),
            for (final entry in custom)
              SelectChip(
                key: Key('$keyPrefix-custom-${entry.toLowerCase()}'),
                label: entry,
                selected: true,
                onTap: () => _toggle(entry),
              ),
            SelectChip(
              key: Key('$keyPrefix-other'),
              label: l(context).prefsOther,
              selected: false,
              onTap: () => _addCustom(context),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          note,
          style: AppText.meta.copyWith(color: noteColor ?? TrainColors.ink3),
        ),
      ],
    );
  }
}

/// The one keyboard on this screen, and only once the user asks for it.
class _CustomEntrySheet extends StatefulWidget {
  const _CustomEntrySheet({required this.title});

  final String title;

  @override
  State<_CustomEntrySheet> createState() => _CustomEntrySheetState();
}

class _CustomEntrySheetState extends State<_CustomEntrySheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: AppText.rowTitle),
          const SizedBox(height: 14),
          TextField(
            key: const Key('custom-entry-field'),
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: AppText.body,
            decoration: zivoFieldDecoration(
              fill: const Color(0x08FFFFFF),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              radius: 14,
              focusRing: false,
            ),
          ),
          const SizedBox(height: 16),
          PillButton(
            key: const Key('custom-entry-add'),
            label: l(context).actionAdd,
            icon: Icons.check_rounded,
            enabled: true,
            onTap: _submit,
          ),
        ],
      ),
    );
  }
}

/// Chip id → the label this user reads. A `switch` rather than a map so a new
/// id in `common_foods.dart` fails to compile until it has been translated.
String commonFoodLabel(BuildContext context, String id) {
  final s = l(context);
  return switch (id) {
    'chicken' => s.foodChicken,
    'beef' => s.foodBeef,
    'fish' => s.foodFish,
    'tuna' => s.foodTuna,
    'eggs' => s.foodEggs,
    'rice' => s.foodRice,
    'pasta' => s.foodPasta,
    'bread' => s.foodBread,
    'potato' => s.foodPotato,
    'oats' => s.foodOats,
    'yoghurt' => s.foodYoghurt,
    'cheese' => s.foodCheese,
    'beans' => s.foodBeans,
    'vegetables' => s.foodVegetables,
    'fruit' => s.foodFruit,
    'nuts' => s.foodNuts,
    // A typed entry is its own label — the user's words, unchanged.
    _ => id,
  };
}

String commonAllergenLabel(BuildContext context, String id) {
  final s = l(context);
  return switch (id) {
    'peanuts' => s.allergenPeanuts,
    'tree nuts' => s.allergenTreeNuts,
    'milk' => s.allergenMilk,
    'eggs' => s.allergenEggs,
    'fish' => s.allergenFish,
    'shellfish' => s.allergenShellfish,
    'soy' => s.allergenSoy,
    'gluten' => s.allergenGluten,
    'sesame' => s.allergenSesame,
    _ => id,
  };
}
