import 'package:flutter/material.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/util/bidi.dart';
import '../../../../../l10n/l10n.dart';
import '../../../domain/ai_choice_request.dart';

/// The Ask question card: a question the coach asked instead of guessing, with
/// its 2–5 options as native, tappable rows — never text the user has to
/// retype. A tap sends the option's stable id back as a structured answer
/// (`AskController.answerChoice`); there is no confirm/cancel, unlike a
/// proposal.
///
/// Once answered ([pickedValue] non-null — this session's tap, or the answer
/// the server recorded) the chosen row wears a violet wash and a check, the
/// rest recede, and none stay tappable.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    required this.request,
    required this.pickedValue,
    required this.onSelect,
    super.key,
  });

  final AiChoiceRequest request;

  /// The value of the option the user picked, or null while unanswered.
  final String? pickedValue;

  /// Called with the chosen option's (value, label) when a row is tapped.
  final void Function(String value, String label) onSelect;

  bool get _answered => pickedValue != null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: TrainColors.raised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _answered
                ? TrainColors.hairline
                : TrainColors.violet.withValues(alpha: 0.22),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
              child: Text(
                request.prompt,
                textDirection: directionOfFor(context, request.prompt),
                style: AppText.rowTitle.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            for (final (i, o) in request.options.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              _OptionRow(
                key: ValueKey('choice-option-${o.value}'),
                option: o,
                picked: pickedValue == o.value,
                dimmed: _answered && pickedValue != o.value,
                onTap: _answered ? null : () => onSelect(o.value, o.label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A number as a person writes it: `90`, `12.8` — never `90.0`.
String _num(num n) {
  if (n == n.roundToDouble()) return n.round().toString();
  return n.toStringAsFixed(1);
}

/// The option's second line: its verified figures in the reader's language
/// when the server attached them, else the server's own subtitle.
String? _detailFor(BuildContext context, AiChoiceOption o) {
  final m = o.metadata;
  final grams = m['grams'];
  final kcal = m['kcal'];
  final protein = m['proteinG'];
  if (grams != null && kcal != null && protein != null) {
    return l(
      context,
    ).askChoiceNutrition(_num(grams), _num(kcal), _num(protein));
  }
  return o.subtitle;
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.picked,
    required this.dimmed,
    required this.onTap,
    super.key,
  });

  final AiChoiceOption option;
  final bool picked;
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final detail = _detailFor(context, option);
    final titleColor = picked
        ? TrainColors.violetGlyph
        : (dimmed ? TrainColors.ink3 : TrainColors.ink);
    final radius = BorderRadius.circular(14);
    return Semantics(
      button: true,
      selected: picked,
      enabled: onTap != null,
      label: detail == null ? option.label : '${option.label}, $detail',
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: AppMotion.tap,
        opacity: dimmed ? 0.55 : 1,
        child: Material(
          color: picked ? TrainColors.violetWash : TrainColors.sectionFill,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            splashColor: TrainColors.violet.withValues(alpha: 0.12),
            highlightColor: TrainColors.violet.withValues(alpha: 0.06),
            child: AnimatedContainer(
              duration: AppMotion.tap,
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: picked
                      ? TrainColors.violet.withValues(alpha: 0.45)
                      : TrainColors.hairlineStrong,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isolate(option.label),
                          style: AppText.button.copyWith(
                            color: titleColor,
                            fontSize: 15,
                          ),
                        ),
                        if (detail != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            detail,
                            style: AppText.meta.copyWith(
                              color: picked
                                  ? TrainColors.violetGlyph.withValues(
                                      alpha: 0.75,
                                    )
                                  : TrainColors.ink3,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _Indicator(picked: picked, dimmed: dimmed),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The trailing mark: an empty ring while open (reads as "pick one"), a
/// filled violet check once this row is the answer.
class _Indicator extends StatelessWidget {
  const _Indicator({required this.picked, required this.dimmed});

  final bool picked;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.tap,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: picked ? TrainColors.violet : Colors.transparent,
        border: Border.all(
          color: picked
              ? TrainColors.violet
              : (dimmed ? TrainColors.hairline : TrainColors.hairlineStrong),
          width: 1.5,
        ),
      ),
      child: picked
          ? const Icon(AppIcons.check, size: 13, color: Colors.white)
          : null,
    );
  }
}
