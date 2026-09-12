import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/widgets/zivo_sheet.dart';
import '../../../../workout/presentation/widgets/staggered_reveal.dart';
import '../../../domain/ai_model_selection.dart';
import '../../../domain/ai_response_style.dart';
import '../../ai_labels.dart';
import '../../../../../l10n/l10n.dart';

/// Opens the Ask settings sheet — the one-level-deeper home for the two
/// preferences that used to sit as separate header controls: which **model**
/// answers, and the **reply style**. Grouping them under a single entry point
/// keeps the header uncluttered and puts related choices side by side.
///
/// Unlike a one-shot picker, this sheet does NOT dismiss on a tap: with two
/// groups a person may adjust both, so each selection applies in place (via
/// [onSelectModel]/[onSelectStyle]) and the sheet stays until dismissed.
Future<void> showAskSettingsSheet(
  BuildContext context, {
  required String model,
  required String style,
  required void Function(String) onSelectModel,
  required void Function(String) onSelectStyle,
}) {
  return showZivoSheet<void>(
    context: context,
    builder: (_) => ZivoSheetSurface(
      child: AskSettingsSheet(
        initialModel: model,
        initialStyle: style,
        onSelectModel: onSelectModel,
        onSelectStyle: onSelectStyle,
      ),
    ),
  );
}

/// The body of the Ask settings sheet: a **Model** section (Auto / Claude /
/// Gemini) and a **Reply style** section (Concise / Balanced / Detailed), each
/// row naming the option and what it does, with the active one highlighted and
/// checked. Local state mirrors each pick for instant feedback while the
/// callback persists it.
class AskSettingsSheet extends StatefulWidget {
  const AskSettingsSheet({
    required this.initialModel,
    required this.initialStyle,
    required this.onSelectModel,
    required this.onSelectStyle,
    super.key,
  });

  final String initialModel;
  final String initialStyle;
  final void Function(String) onSelectModel;
  final void Function(String) onSelectStyle;

  @override
  State<AskSettingsSheet> createState() => _AskSettingsSheetState();
}

class _AskSettingsSheetState extends State<AskSettingsSheet> {
  late String _model = widget.initialModel;
  late String _style = widget.initialStyle;

  void _pickModel(String selection) {
    if (selection == _model) return;
    HapticFeedback.selectionClick();
    setState(() => _model = selection);
    widget.onSelectModel(selection);
  }

  void _pickStyle(String selection) {
    if (selection == _style) return;
    HapticFeedback.selectionClick();
    setState(() => _style = selection);
    widget.onSelectStyle(selection);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: TrainColors.hairlineStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screen,
              ),
              child: Text(
                l(context).askSettings,
                style: AppText.cardTitle.copyWith(fontSize: 19),
              ),
            ),
            const SizedBox(height: 16),
            // --- Model ---------------------------------------------------
            _SectionHeader(
              title: l(context).askModel,
              subtitle: l(context).askModelSheetSubtitle,
            ),
            const SizedBox(height: 8),
            _OptionGroup(
              baseIndex: 0,
              options: kAiModelSelections,
              current: _model,
              labelOf: aiModelSelectionText,
              descriptionOf: aiModelSelectionDescription,
              onTap: _pickModel,
            ),
            const SizedBox(height: 20),
            // --- Reply style ---------------------------------------------
            _SectionHeader(title: l(context).askReplyStyle),
            const SizedBox(height: 8),
            _OptionGroup(
              baseIndex: kAiModelSelections.length,
              options: kResponseStyles,
              current: _style,
              labelOf: responseStyleText,
              descriptionOf: responseStyleDescription,
              onTap: _pickStyle,
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

/// A grouped section header: a title, and an optional one-line subtitle.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppText.meta.copyWith(
              color: TrainColors.ink3,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: AppText.meta.copyWith(
                color: TrainColors.ink3,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One section's list of selectable rows. [baseIndex] keeps the staggered
/// reveal running continuously across both groups instead of restarting.
class _OptionGroup extends StatelessWidget {
  const _OptionGroup({
    required this.baseIndex,
    required this.options,
    required this.current,
    required this.labelOf,
    required this.descriptionOf,
    required this.onTap,
  });

  final int baseIndex;
  final List<String> options;
  final String current;
  final String Function(BuildContext, String) labelOf;
  final String Function(BuildContext, String) descriptionOf;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
      child: Column(
        children: [
          for (var i = 0; i < options.length; i++)
            StaggeredReveal(
              index: baseIndex + i,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _SettingRow(
                  title: labelOf(context, options[i]),
                  description: descriptionOf(context, options[i]),
                  isSelected: options[i] == current,
                  onTap: () => onTap(options[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One selectable settings row: title, one-line description, and — when
/// active — a raised fill and an iris check. Presses scale instantly.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: isSelected ? TrainColors.raisedStrong : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppText.rowTitle.copyWith(
                          color: isSelected
                              ? TrainColors.ink
                              : TrainColors.ink2,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: AppText.meta.copyWith(
                          color: TrainColors.ink3,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (isSelected)
                  Icon(AppIcons.check, size: 17, color: TrainColors.violet),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
