import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../core/widgets/pressable_scale.dart';
import '../../../../../core/widgets/rise_in.dart';
import '../../ask_constants.dart';
import '../../../../../l10n/l10n.dart';

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
          // Neutral, not violet: the signature repeats above every reply,
          // and a hue there would tint the whole conversation.
          Icon(AppIcons.ask, size: 13, color: TrainColors.ink2),
          const SizedBox(width: 7),
          Text(
            'ZIVO',
            style: TrainType.caption(
              size: 9,
              tracking: 0.2,
              weight: FontWeight.w600,
              color: TrainColors.ink3,
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

  /// The example prompts. Each is both the chip's label AND the text that
  /// gets sent, so these are localized: an Arabic reader taps an Arabic
  /// question and ZIVO is asked it in Arabic.
  static List<String> _suggestions(BuildContext context) => [
    l(context).askSuggestSpend,
    l(context).askSuggestTraining,
    l(context).askSuggestDiet,
    l(context).askSuggestWeek,
  ];

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    final suggestions = _suggestions(context);
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
                  // The hero is a violet glyph tile, not an illustration:
                  // identity §1.4 is "text over imagery", and the one thing
                  // this screen should lead with is ZIVO's VOICE — the
                  // Instrument Serif line below — rather than a picture of it.
                  _HeroGlyph(reduceMotion: still),
                  const SizedBox(height: 26),
                  // Instrument Serif italic — the assistant's voice, used here
                  // and in its answers, and nowhere else in the app. Confident
                  // and still: a display size, tight tracking, solid voice-ink,
                  // and a quiet focus-in reveal — no shine, no gradient.
                  _GreetingText(
                    text: l(context).askGreeting,
                    reduceMotion: still,
                  ),
                  const SizedBox(height: 16),
                  RiseIn(
                    delay: still
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 288),
                      child: Text(
                        l(context).askIntro,
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
                  const SizedBox(height: 36),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (index, prompt) in suggestions.indexed)
                          Padding(
                            padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
                            child: RiseIn(
                              delay: still
                                  ? Duration.zero
                                  : Duration(milliseconds: 320 + index * 60),
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

/// The empty-state hero: a violet sparkle tile lit from the top. It settles in
/// with a calm fade + a small scale — critically damped, no bounce, no glow
/// smudge — so it reads as arriving, not performing. Honors reduce motion.
class _HeroGlyph extends StatefulWidget {
  const _HeroGlyph({required this.reduceMotion});

  final bool reduceMotion;

  @override
  State<_HeroGlyph> createState() => _HeroGlyphState();
}

class _HeroGlyphState extends State<_HeroGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
    value: widget.reduceMotion ? 1 : 0,
  );

  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) {
      _delay = Timer(const Duration(milliseconds: 60), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
        );
      },
      child: Container(
        width: 60,
        height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          // Depth from light, not shadow (identity §5): a top-lit violet wash.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              TrainColors.violetGlyph.withValues(alpha: 0.20),
              TrainColors.violetGlyph.withValues(alpha: 0.09),
            ],
          ),
          border: Border.all(
            color: TrainColors.violetGlyph.withValues(alpha: 0.28),
          ),
        ),
        child: Icon(AppIcons.ask, size: 25, color: TrainColors.violetGlyph),
      ),
    );
  }
}

/// ZIVO's greeting in the Instrument Serif voice, given the confidence a hero
/// line earns: a display size with tight display tracking (apple-design §15),
/// solid voice-ink — and a quiet **focus-in** on first appearance (starts a
/// touch soft and low, resolves crisp). One `Text`, one short reveal, no shine
/// and no perpetual motion. Honors reduce motion (renders crisp, no reveal).
class _GreetingText extends StatefulWidget {
  const _GreetingText({required this.text, required this.reduceMotion});

  final String text;
  final bool reduceMotion;

  @override
  State<_GreetingText> createState() => _GreetingTextState();
}

class _GreetingTextState extends State<_GreetingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
    value: widget.reduceMotion ? 1 : 0,
  );

  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) {
      _delay = Timer(const Duration(milliseconds: 120), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      textAlign: TextAlign.center,
      style: TrainType.serifVoice(
        context,
        size: 35,
        height: 1.05,
        tracking: -0.02,
      ),
    );

    if (widget.reduceMotion) return text;

    return AnimatedBuilder(
      animation: _c,
      child: text,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        final blur = (1 - t) * 6;
        var content = child!;
        // Skip the filter once it's effectively sharp — a 0-sigma blur is pure
        // cost, and it keeps the settled line pixel-crisp.
        if (blur > 0.15) {
          content = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: blur,
              sigmaY: blur,
              tileMode: TileMode.decal,
            ),
            child: content,
          );
        }
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 7),
            child: content,
          ),
        );
      },
    );
  }
}

/// A tappable suggestion pill — a tap sends the prompt immediately, the same
/// as typing it and hitting send. A pure text pill: the label centred in a
/// flat glass capsule inside a hairline, sized to its content. Press feedback
/// is an instant physical scale-down ([PressableScale]) plus a light haptic —
/// the Apple press, which is the only "animation" it needs.
class SuggestionChip extends StatelessWidget {
  const SuggestionChip({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Material(
        color: Colors.transparent,
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
              color: TrainColors.glass,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: TrainColors.liftAt(0.08)),
            ),
            child: Text(
              label,
              style: TrainType.ui(
                size: 14,
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
