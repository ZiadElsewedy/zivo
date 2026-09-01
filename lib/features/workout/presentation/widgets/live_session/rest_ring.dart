import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/motion/springs.dart';
import '../../../../../core/theme/train_tokens.dart';
import '../../../../../l10n/l10n.dart';
import 'live_session_format.dart';

/// The premium rest countdown — a ring sweeping down continuously (not
/// stepped) over the rest window, with the remaining time centered inside
/// at sub-second precision. Warm gray/ink, per the approved "rest" identity
/// (Ember stays reserved for the current set, Pulse for done) — a vivid hue
/// here would compete with that meaning.
///
/// The ring and the digits stay a fixed size at all times — the "alive"
/// feel comes from a slow stroke color/width ease on the sweep itself
/// ([_glow]), never from scaling the whole thing (see M2: constant-size
/// timer).
class RestRing extends StatefulWidget {
  const RestRing({
    required this.remaining,
    required this.total,
    this.animate = true,
    this.accent,
    this.hue = TrainColors.green,
    this.onTap,
    this.isPaused = false,
    super.key,
  });

  final Duration remaining;
  final int total;

  /// False while the session is paused — the ring's breathing glow must
  /// stop with the countdown, or a paused rest still *looks* alive (which
  /// read as "the pause button doesn't work").
  final bool animate;

  /// The live track's colour, foreground-normalised
  /// (`SessionAmbience.vividOf`) — tints the sweep so the countdown carries
  /// the song's identity. Deliberately NOT the ambient accent: that one is
  /// pulled most of the way to the background on purpose, so blending the
  /// arc into it would read as the ring dimming, not as the ring changing
  /// colour. Null → the phase's own [hue].
  final Color? accent;

  /// The phase's colour: green while resting, ember during the warm-up.
  final Color hue;

  /// Pause/resume. The ring is the biggest, most obvious target on either
  /// countdown screen, so it's the one people reach for first.
  final VoidCallback? onTap;

  /// Only reaches the Semantics label — the visible paused state is the
  /// eyebrow pill above the ring (and the header badge). Screen readers get
  /// it here because the ring is itself the toggle.
  final bool isPaused;

  @override
  State<RestRing> createState() => _RestRingState();
}

class _RestRingState extends State<RestRing> with TickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  /// Absorbs a discontinuous jump in [_trueProgress] (a ±15s adjustment) as a
  /// correction that starts at the jump's size and springs back to zero —
  /// the ring keeps tracking wall-clock time exactly every frame, but a
  /// sudden retarget visibly *springs* to the new fraction instead of
  /// snapping. The normal continuous per-frame decay between adjustments
  /// never touches this (it's already smooth by construction).
  late final AnimationController _correction = AnimationController.unbounded(
    vsync: this,
  )..value = 0;

  double? _lastProgress;

  double get _trueProgress {
    final totalMs = widget.total * 1000;
    return totalMs <= 0
        ? 0.0
        : (widget.remaining.inMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(covariant RestRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    final last = _lastProgress;
    final next = _trueProgress;
    // A normal tick decays by a fraction of a percent; only a ±15s jump
    // moves it enough to cross this threshold, so this reliably tells the
    // two apart regardless of exact rebuild cadence.
    if (last != null && (next - last).abs() > 0.01 && !reducedMotion(context)) {
      final jump = last - next;
      _correction.value = _correction.value + jump;
      _correction.springTo(0, spring: AppSprings.standard);
    }
    _lastProgress = next;
    // The breathing glow follows the pause state — frozen ring for a frozen
    // countdown.
    if (widget.animate) {
      if (!_glow.isAnimating) _glow.repeat(reverse: true);
    } else if (_glow.isAnimating) {
      _glow.stop();
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    _correction.dispose();
    super.dispose();
  }

  /// The sweep's colour: the track's, outright, whenever there is one.
  ///
  /// It used to be a blend of the phase hue and the track's, which is what a
  /// "keep both identities" instinct suggests — but RGB-lerping between two
  /// distant hues walks through grey, so green rest + a red song rendered a
  /// muddy tan that was neither. There is no blend weight that fixes that in
  /// general; the mud is the interpolation, not the ratio. So the ring simply
  /// IS the song (which is what was asked for), and the phase keeps its
  /// identity where colour can't be hijacked: the eyebrow pill, the skip
  /// button's label, and the card above the strip. [hue] is the fallback for
  /// no music / no artwork, where the ring is green for rest and ember for
  /// warm-up exactly as before.
  Color get _sweep => widget.accent ?? widget.hue;

  @override
  Widget build(BuildContext context) {
    _lastProgress ??= _trueProgress;
    final time = restTimeParts(widget.remaining);
    final ring = SizedBox(
      width: 290,
      height: 290,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The colour GLIDES between tracks rather than cutting: a hard swap
          // on a 290px ring reads as a glitch, a half-second ease reads as
          // the screen responding to the skip.
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: _sweep),
            duration: reducedMotion(context)
                ? Duration.zero
                : const Duration(milliseconds: 650),
            curve: Curves.easeOut,
            builder: (context, sweep, _) => AnimatedBuilder(
              animation: Listenable.merge([_glow, _correction]),
              builder: (context, _) {
                final t = widget.animate
                    ? Curves.easeInOut.transform(_glow.value)
                    : 0.0;
                final progress = (_trueProgress + _correction.value).clamp(
                  0.0,
                  1.0,
                );
                return CustomPaint(
                  size: const Size(290, 290),
                  painter: RestRingPainter(
                    progress: progress,
                    glow: t,
                    sweep: sweep ?? _sweep,
                  ),
                );
              },
            ),
          ),
          // The numeral owns the ring's exact centre. It used to share a
          // Column with the caption below it, which centred the PAIR — so the
          // digits sat half a caption plus its gap ABOVE the circle's middle.
          // The caption hangs from its own offset now and can't move it.
          RestTimeLabel(time: time),
          Positioned.fill(
            child: Align(
              alignment: const Alignment(0, 0.44),
              child: Text(
                l(context).liveRestPlanned(formatRest(widget.total)),
                style: TrainType.mono(
                  size: 9,
                  weight: FontWeight.w500,
                  tracking: 0.24,
                  color: const Color(0x4DF4F4F0),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final onTap = widget.onTap;
    if (onTap == null) return ring;
    return Semantics(
      button: true,
      label: widget.isPaused
          ? l(context).workoutResume
          : l(context).workoutPause,
      child: GestureDetector(
        key: const Key('rest-ring-pause'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: ring,
      ),
    );
  }
}

/// The rest ring's sub-second readout: a bold whole-second part ("1:54" at/
/// above a minute, "45" under it) plus a quieter ".CC" hundredths suffix.
/// Each part lives in a [_FixedSlot] sized for its widest possible content,
/// so neither the digits nor the ring around them resize or shift as the
/// digit count changes crossing a minute boundary or ticking down — only
/// the glyphs inside each slot update.
class RestTimeLabel extends StatelessWidget {
  const RestTimeLabel({required this.time, super.key});

  final ({String whole, String centis}) time;

  // Both sizes are set against the CIRCLE, not against each other. At the
  // original 74/26 a "3:48.02" ran from the ring's left stroke clean through
  // its right one — the four-character numeral alone nearly spans the inner
  // width, so anything beside it lands on the stroke, and the hundredths sit
  // BELOW centre where the available chord is already shorter than the
  // diameter. 64/17 clears the inner edge by ~17pt at the widest value this
  // can ever show ("9:59.99"), with the numeral still the obvious hero of a
  // 290pt ring.
  static final _wholeStyle = TrainType.mono(
    size: 64,
    weight: FontWeight.w200,
    tracking: -0.06,
    color: const Color(0xFFFBFBF7),
  );
  static final _centisStyle = TrainType.mono(
    size: 17,
    tracking: -0.03,
    color: const Color(0x59F4F4F0),
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${time.whole}${time.centis}',
      excludeSemantics: true,
      // The two slots below reserve their widest content at a FIXED size, so
      // when the pair can't fit — a large Dynamic Type setting, or a font
      // whose digits are wider than Azeret's — the whole readout scales down
      // together rather than overflowing the ring. Scaling down keeps the
      // slots' relative sizes (74 vs 26) and the no-reflow guarantee intact,
      // which clipping or wrapping would both destroy.
      // Centring done in layout rather than by eye, and without pushing the
      // readout out of its circle.
      //
      // The whole-second numeral is the ONLY thing that sizes this widget, so
      // the ring's Stack centres it exactly — it's the mass the eye reads as
      // "the number". The hundredths then hang off its right edge as a
      // zero-width overhang, contributing nothing to the layout.
      //
      // Two earlier arrangements both failed: the original right-aligned the
      // numeral inside a slot reserved for the widest possible "9:59", so
      // every rest under a minute (most of them) drew its digits a full
      // character-width right of centre; balancing that with a mirrored
      // spacer on the left centred it correctly but made the row wide enough
      // that the hundredths crossed the ring's stroke. Overhanging costs
      // neither.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Stack(
          key: const Key('rest-time-label'),
          clipBehavior: Clip.none,
          children: [
            // Tabular figures (see TrainType.mono) hold this steady per tick;
            // only crossing a minute boundary changes its width, and that
            // re-centres symmetrically.
            Text(
              time.whole,
              key: const Key('rest-time-whole'),
              style: _wholeStyle,
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomRight,
                // Right by 100% of its OWN width, so it starts where the
                // numeral ends rather than overlapping it; up by a third of
                // its height to sit near the numeral's baseline instead of
                // hanging off its descender — which also buys back a few
                // points of chord, since the circle is widest at its middle.
                child: FractionalTranslation(
                  translation: const Offset(1, -0.32),
                  child: Text(
                    time.centis,
                    key: const Key('rest-time-centis'),
                    style: _centisStyle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RestRingPainter extends CustomPainter {
  const RestRingPainter({
    required this.progress,
    required this.glow,
    required this.sweep,
  });

  /// 1.0 = the full rest window remains, 0.0 = rest is over.
  final double progress;

  /// 0..1 easing value driving the sweep's stroke width/opacity — the
  /// timer's "alive" pulse. Never affects layout size, only paint.
  final double glow;

  /// The already-resolved arc colour — the phase's hue carried toward the
  /// current track's (see `_RestRingState._sweep`), and tweened by the
  /// caller so a song change glides rather than cuts.
  final Color sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 13;
    final track = Paint()
      ..color = TrainColors.hairline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;
    canvas.drawCircle(center, radius, track);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweepColor = sweep;

    // The bloom under the sweep — a `drop-shadow` in the handoff, a wider,
    // softer arc here. It breathes with [glow] so the countdown reads as
    // alive without anything moving.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * clamped,
      false,
      Paint()
        ..color = sweepColor.withValues(alpha: 0.16 + 0.10 * glow)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 3 * glow),
    );

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * clamped,
      false,
      Paint()
        ..color = sweepColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant RestRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.glow != glow ||
      oldDelegate.sweep != sweep;
}
