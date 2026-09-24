import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/util/bidi.dart';
import '../../../../../l10n/l10n.dart';
import '../../../domain/ai_choice_request.dart';

/// The value of the "none of these — show me others" option ZIVO adds itself
/// to a card built from verified options (`functions/ai/chat/choices.js`).
const kMoreOptionsValue = '__more__';

/// What a question message says in the conversation: ZIVO's lead-in, then the
/// question — or just the question when there was no lead-in (and just the
/// lead-in when it already ends by asking it).
String choiceMessageText(AiChoiceRequest request, String? preface) {
  final lead = preface?.trim() ?? '';
  final ask = request.prompt.trim();
  if (lead.isEmpty) return ask;
  if (ask.isEmpty || lead.contains(ask)) return lead;
  return '$lead\n\n$ask';
}

/// ZIVO's open question, answered by tapping — its options as chips docked
/// just above the composer, on the user's side of the screen, because they
/// are the user's possible replies. The question itself stays in the
/// conversation as ZIVO's words ([choiceMessageText]); only the answers live
/// here, where the thumb already is.
///
/// A tap sends the option's stable id (`AskController.answerChoice`), never
/// its label. Tapping "Other options" asks ZIVO for different ones. Typing a
/// reply instead still works — the chips stay until something is sent.
///
/// The chips rise in from the composer once, staggered — the tray's only
/// motion, and one that answers ZIVO asking.
class ChoiceTray extends StatefulWidget {
  const ChoiceTray({required this.request, required this.onSelect, super.key});

  final AiChoiceRequest request;

  /// Called with the chosen option's (value, label).
  final void Function(String value, String label) onSelect;

  @override
  State<ChoiceTray> createState() => _ChoiceTrayState();
}

class _ChoiceTrayState extends State<ChoiceTray>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _enter.value = 1;
    } else if (_enter.value == 0 && !_enter.isAnimating) {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.request.options;
    final n = options.length;
    return Semantics(
      container: true,
      label: l(context).askChoiceTray,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.base,
          0,
          AppSpacing.base,
          2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, o) in options.indexed)
              _Staggered(
                animation: _enter,
                // The chip nearest the composer rises first.
                index: n - 1 - i,
                count: n,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _Chip(
                    key: ValueKey('choice-option-${o.value}'),
                    option: o,
                    secondary: o.value == kMoreOptionsValue,
                    onTap: () => widget.onSelect(o.value, o.label),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A slice of the tray's one entrance — each chip lifts and fades in a beat
/// after the one below it.
class _Staggered extends StatelessWidget {
  const _Staggered({
    required this.animation,
    required this.index,
    required this.count,
    required this.child,
  });

  final Animation<double> animation;
  final int index;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.12).clamp(0.0, 0.6);
    final curve = CurvedAnimation(
      parent: animation,
      curve: Interval(
        start,
        (start + 0.55).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: curve,
      child: child,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - curve.value)),
          child: child,
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
String? choiceOptionDetail(BuildContext context, AiChoiceOption o) {
  final m = o.metadata;
  final grams = m['grams'];
  final kcal = m['kcal'];
  final protein = m['proteinG'];
  if (grams != null && kcal != null && protein != null) {
    return ltrFor(
      context,
      l(context).askChoiceNutrition(_num(grams), _num(kcal), _num(protein)),
    );
  }
  return o.subtitle;
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.option,
    required this.secondary,
    required this.onTap,
    super.key,
  });

  final AiChoiceOption option;

  /// "Other options" — asks for more rather than answering, so it recedes.
  final bool secondary;
  final VoidCallback onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final detail = widget.secondary
        ? null
        : choiceOptionDetail(context, widget.option);
    final radius = BorderRadius.circular(20);
    final still = MediaQuery.of(context).disableAnimations;
    final label = Text(
      isolate(widget.option.label),
      style: TrainType.ui(
        size: 14,
        weight: FontWeight.w600,
        color: widget.secondary ? TrainColors.ink2 : TrainColors.inkPlain,
        height: 1.25,
      ),
    );
    return Semantics(
      button: true,
      label: detail == null
          ? widget.option.label
          : '${widget.option.label}, $detail',
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: still ? Duration.zero : const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
              minHeight: 44,
            ),
            // The same frosted material as the composer below it: the chips
            // float over the conversation as part of the input, not in it.
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: AnimatedContainer(
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 110),
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: detail == null ? 11 : 9,
                  ),
                  decoration: BoxDecoration(
                    color: widget.secondary
                        ? TrainColors.glass
                        : (_down
                              ? TrainColors.raisedStrong
                              : TrainColors.raised),
                    borderRadius: radius,
                    border: Border.all(color: TrainColors.hairlineStrong),
                  ),
                  child: detail == null
                      ? label
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            label,
                            const SizedBox(height: 2),
                            Text(
                              detail,
                              style: TrainType.mono(
                                size: 11,
                                color: TrainColors.ink3,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
