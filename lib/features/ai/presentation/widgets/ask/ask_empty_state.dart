import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/motion/springs.dart';
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
          Icon(AppIcons.ask, size: 13, color: TrainColors.violetGlyph),
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

  /// The example prompts. Each is both the chip's label AND the text that
  /// gets sent, so these are localized: an Arabic reader taps an Arabic
  /// question and ZIVO is asked it in Arabic.
  static List<String> _suggestions(BuildContext context) => [
    l(context).askSuggestSpend,
    l(context).askSuggestTraining,
    l(context).askSuggestDiet,
    l(context).askSuggestWeek,
  ];

  /// The glyph + hue each suggestion wears, in the SAME fixed order as
  /// [_suggestions]. Each topic carries the hue it owns in the app's colour
  /// language — money is amber, training and diet are the training green,
  /// and a week summary is the assistant/system violet — so the row reads as
  /// ZIVO's own surfaces rather than four identical grey pills. Resolved at
  /// build (never cached) so both skins stay honest (ADR-011).
  static List<(IconData, Color)> _visuals() => [
    (AppIcons.expenses, TrainColors.amber),
    (AppIcons.workout, TrainColors.green),
    (AppIcons.diet, TrainColors.green),
    (AppIcons.analysis, TrainColors.violetGlyph),
  ];

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    final suggestions = _suggestions(context);
    final visuals = _visuals();
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
                  // The tile springs in and blooms a soft violet glow; the
                  // sentence is still the hero.
                  _HeroGlyph(reduceMotion: still),
                  const SizedBox(height: 22),
                  // Instrument Serif italic — the assistant's voice, used here
                  // and in its answers, and nowhere else in the app. Given the
                  // display treatment a hero line earns: larger, tighter
                  // tracking, a violet-lit gradient, and a one-shot shimmer
                  // that sweeps across it once as it settles.
                  RiseIn(
                    delay: still
                        ? Duration.zero
                        : const Duration(milliseconds: 120),
                    child: _GreetingText(
                      text: l(context).askGreeting,
                      reduceMotion: still,
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
                  const SizedBox(height: 34),
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
                                  : Duration(milliseconds: 300 + index * 70),
                              child: SuggestionChip(
                                label: prompt,
                                icon: visuals[index].$1,
                                tint: visuals[index].$2,
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

/// The empty-state hero: a violet sparkle tile that springs into place with a
/// momentum-earned overshoot and blooms a soft radial glow behind it. A
/// one-shot entrance — no perpetual oscillation to distract from the greeting.
/// Honors reduce motion (renders settled, no animation).
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
    // Value drives both scale and glow; a spring can push it past 1 for the
    // landing pop, so the build clamps where a raw [0,1] is needed.
    value: widget.reduceMotion ? 1 : 0,
  );

  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) {
      // Lands just before the greeting rises, so the eye is on the tile as the
      // sentence arrives beneath it.
      _delay = Timer(const Duration(milliseconds: 80), () {
        if (mounted) _c.springTo(1, spring: AppSprings.bounce);
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
        final t = _c.value;
        final glow = t.clamp(0.0, 1.0);
        // The tile sets the layout box (60×60); the bloom is a non-positioned
        // overflow so its 132px spread never inflates the gap to the greeting.
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              width: 132,
              height: 132,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        TrainColors.violetGlyph.withValues(
                          alpha: 0.26 * glow,
                        ),
                        TrainColors.violetGlyph.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Opacity(
              opacity: glow,
              // 0.72 → 1.0 (with the spring's slight overshoot), so it reads as
              // arriving under its own momentum rather than fading in flat.
              child: Transform.scale(scale: 0.72 + 0.28 * t, child: child),
            ),
          ],
        );
      },
      child: _tile(),
    );
  }

  Widget _tile() {
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        // A top-lit violet wash: depth from light, not shadow (identity §5).
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            TrainColors.violetGlyph.withValues(alpha: 0.22),
            TrainColors.violetGlyph.withValues(alpha: 0.10),
          ],
        ),
        border: Border.all(
          color: TrainColors.violetGlyph.withValues(alpha: 0.30),
        ),
      ),
      child: Icon(
        AppIcons.askFill,
        size: 26,
        color: TrainColors.violetGlyph,
      ),
    );
  }
}

/// ZIVO's greeting, rendered in the Instrument Serif voice with the display
/// treatment a hero line earns: a violet-lit ink gradient for depth and a
/// one-shot highlight that sweeps across the text once as it settles — the
/// "premium reveal" you see on a polished onboarding line, played exactly
/// once so nothing loops in the corner of the eye. Honors reduce motion
/// (static gradient, no sweep).
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
    duration: const Duration(milliseconds: 2100),
  );

  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) {
      // Fires after the rise-in has settled, so the sweep reads on a line
      // already in place rather than one still moving.
      _delay = Timer(const Duration(milliseconds: 720), () {
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

  TextStyle get _style => TrainType.serifVoice(
    context,
    size: 40,
    height: 1.0,
    // Negative tracking as display type grows (apple-design §15): the letters
    // read too far apart at 40 otherwise.
    tracking: -0.02,
  );

  /// The whole greeting is ONE `Text` under ONE animated `ShaderMask` — never
  /// two stacked copies — so the string is found exactly once (and there's no
  /// second glyph run to fringe against the first).
  ///
  /// The shader is a single horizontal gradient carrying both the resting look
  /// and the sweep: a bright band whose edge colours are *sampled from the
  /// resting gradient itself*, so it dissolves seamlessly into the ink and,
  /// off-screen (before the sweep starts and after it ends), collapses back to
  /// the plain resting ink → violet-ink gradient with no seam.
  Shader _shader(Rect bounds) {
    final a = TrainColors.voiceInk;
    final b = Color.lerp(a, TrainColors.violetGlyph, 0.34)!;
    Color resting(double x) => Color.lerp(a, b, x.clamp(0.0, 1.0))!;

    final t = Curves.easeInOut.transform(_c.value);
    // Band centre travels from just off the left edge to just off the right.
    final c = -0.25 + 1.5 * t;
    const w = 0.13; // half-width of the highlight band
    final bl = (c - w).clamp(0.0, 1.0);
    final cc = c.clamp(0.0, 1.0);
    final br = (c + w).clamp(0.0, 1.0);
    final highlight = Color.lerp(resting(cc), Colors.white, 0.9)!;

    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [a, resting(bl), highlight, resting(br), b],
      // Non-decreasing by construction: 0 ≤ bl ≤ cc ≤ br ≤ 1.
      stops: [0.0, bl, cc, br, 1.0],
    ).createShader(bounds);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: _shader,
        child: child,
      ),
      child: Text(widget.text, textAlign: TextAlign.center, style: _style),
    );
  }
}

/// A tappable suggestion row in the empty state — a tap sends the prompt
/// immediately, the same as typing it and hitting send. A leading hue-tinted
/// glyph tile names the topic in the app's colour language, and a trailing
/// caret marks it as "use this". Press feedback is an instant physical
/// scale-down ([PressableScale]) plus a light haptic — the Apple press.
class SuggestionChip extends StatelessWidget {
  const SuggestionChip({
    required this.label,
    required this.icon,
    required this.tint,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return PressableScale(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              // Top-lit glass so the row has depth from light, not a shadow.
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  TrainColors.liftAt(0.05),
                  TrainColors.liftAt(0.015),
                ],
              ),
              border: Border.all(color: TrainColors.liftAt(0.09)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    color: tint.withValues(alpha: 0.14),
                    border: Border.all(color: tint.withValues(alpha: 0.22)),
                  ),
                  child: Icon(icon, size: 17, color: tint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TrainType.ui(
                      size: 14,
                      weight: FontWeight.w600,
                      color: TrainColors.inkPlain,
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // The caret is directional — mirror it under RTL so it always
                // points "outward" toward the send, never back at the label.
                Transform.flip(
                  flipX: rtl,
                  child: Icon(
                    AppIcons.chevron,
                    size: 14,
                    color: TrainColors.ink4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
