import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/widgets/rise_in.dart';
import '../../ask_constants.dart';

/// The small "✦ ZIVO" label grouping consecutive assistant content — shown
/// once above a run of assistant bubbles/proposal cards, not per-message.
class ZivoIdentity extends StatelessWidget {
  const ZivoIdentity({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.ask, size: 13, color: TrainColors.violetGlyph),
          const SizedBox(width: 7),
          Text(
            'ZIVO',
            style: TrainType.caption(
              size: 9,
              tracking: 0.2,
              weight: FontWeight.w600,
              color: TrainColors.violetGlyph.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyAsk extends StatelessWidget {
  const EmptyAsk({required this.onSuggestion, super.key});

  final void Function(String prompt) onSuggestion;

  static const _suggestions = [
    'What did I spend this week?',
    'How is my training going?',
    "What's left on my diet today?",
    'Summarise my week',
  ];

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    // The min height is the VIEWPORT's, not a fraction of the screen's.
    // `size.height * 0.6` ignored the header above this surface, the composer
    // below it and the keyboard entirely, so the column it stretched was
    // taller than the space it had: the empty state could not centre itself,
    // and it handed the scroll view an extent with nothing in it — a
    // short screen scrolled through blank ground before reaching the pills,
    // and with the keyboard up it scrolled when it had no reason to.
    // `constraints.maxHeight` is the room actually on offer, so the content
    // centres when it fits and scrolls only when it genuinely doesn't. Same
    // shape the live session's phase scaffold already uses.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // Scrollable rather than a bare Center: with the keyboard rising, a
        // min-height column can overflow — this lets it give instead of
        // throwing yellow stripes over a premium moment.
        // Bottom padding keeps the suggestion pills clear of the floating
        // composer that overlays this surface.
        padding: const EdgeInsets.only(bottom: kComposerFloatClearance),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(
              0,
              constraints.maxHeight - kComposerFloatClearance,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.section,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The hero is a 54px violet glyph tile, not an
                  // illustration: identity §1.4 is "text over imagery", and the
                  // one thing this screen should lead with is ZIVO's VOICE —
                  // the Instrument Serif line below — rather than a picture of
                  // it. The tile marks the assistant; the sentence is the hero.
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: TrainColors.violetGlyph.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: TrainColors.violetGlyph.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Icon(
                      AppIcons.ask,
                      size: 24,
                      color: TrainColors.violetGlyph,
                    ),
                  ),
                  const SizedBox(height: 22),
                  // Instrument Serif italic — the assistant's voice, used here
                  // and in its answers, and nowhere else in the app.
                  RiseIn(
                    delay: still
                        ? Duration.zero
                        : const Duration(milliseconds: 120),
                    child: Text(
                      "Hey, I'm ZIVO.",
                      textAlign: TextAlign.center,
                      style: TrainType.serif(size: 36, height: 1),
                    ),
                  ),
                  const SizedBox(height: 14),
                  RiseIn(
                    delay: still
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Text(
                        'Training, diet and spending. Ask me anything — or let '
                        'me log it for you.',
                        textAlign: TextAlign.center,
                        style: TrainType.ui(
                          size: 14,
                          weight: FontWeight.w400,
                          color: TrainColors.ink2,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (index, prompt) in _suggestions.indexed)
                          Padding(
                            padding: EdgeInsets.only(top: index == 0 ? 0 : 9),
                            child: RiseIn(
                              delay: still
                                  ? Duration.zero
                                  : Duration(milliseconds: 280 + index * 70),
                              child: SuggestionChip(
                                label: prompt,
                                onTap: () => onSuggestion(prompt),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tappable suggestion pill in the empty state — a tap sends the prompt
/// immediately, the same as typing it and hitting send.
class SuggestionChip extends StatelessWidget {
  const SuggestionChip({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: const Color(0x0BFFFFFF),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x17FFFFFF)),
            ),
            child: Text(
              label,
              style: TrainType.ui(
                size: 13.5,
                weight: FontWeight.w600,
                color: TrainColors.inkPlain,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
