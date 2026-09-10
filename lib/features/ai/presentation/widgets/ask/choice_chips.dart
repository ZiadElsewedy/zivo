import 'package:flutter/material.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/util/bidi.dart';
import '../../../domain/ai_choice_request.dart';

/// The Ask elicitation card (Phase 1): a question the coach asked instead of
/// guessing, rendered as tappable option chips. Picking one sends that option
/// back as the user's next message (see `AskController.answerChoice`) — there
/// is no confirm/cancel, unlike a proposal.
///
/// Once answered ([pickedValue] non-null) the chosen chip wears an ember wash
/// and a check, the rest dim, and all become non-tappable — the answer is
/// already on its way as a normal turn.
class ChoiceChips extends StatelessWidget {
  const ChoiceChips({
    required this.request,
    required this.pickedValue,
    required this.onSelect,
    super.key,
  });

  final AiChoiceRequest request;

  /// The value of the option the user picked, or null while unanswered.
  final String? pickedValue;

  /// Called with the chosen option's (value, label) when a chip is tapped.
  final void Function(String value, String label) onSelect;

  bool get _answered => pickedValue != null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AnimatedSize(
        duration: AppMotion.enter,
        curve: AppMotion.ease,
        alignment: Alignment.topCenter,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          decoration: BoxDecoration(
            color: TrainColors.raised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _answered
                  ? TrainColors.hairline
                  : TrainColors.ember.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: TrainColors.emberWash,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      AppIcons.ask,
                      size: 18,
                      color: TrainColors.ember,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      request.prompt,
                      textDirection: directionOfFor(context, request.prompt),
                      style: AppText.cardTitle.copyWith(
                        fontSize: 17,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in request.options)
                    _OptionChip(
                      label: o.label,
                      picked: pickedValue == o.value,
                      dimmed: _answered && pickedValue != o.value,
                      onTap: _answered
                          ? null
                          : () => onSelect(o.value, o.label),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.picked,
    required this.dimmed,
    required this.onTap,
  });

  final String label;
  final bool picked;
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = picked
        ? TrainColors.ember
        : (dimmed ? TrainColors.ink3 : TrainColors.ink);
    return Material(
      color: picked ? TrainColors.emberWash : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: picked
                  ? TrainColors.ember.withValues(alpha: 0.4)
                  : TrainColors.hairlineStrong,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (picked) ...[
                Icon(AppIcons.check, size: 15, color: TrainColors.ember),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AppText.button.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
