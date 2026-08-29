import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/motion/springs.dart';
import '../../../core/theme/train_tokens.dart';

/// The animated equalizer that carries "something is playing" (and, frozen,
/// "it's paused") wherever the music appears.
///
/// It began as a *replacement* for album artwork: the design handoff was
/// explicit that Spotify should be text-first with no cover tile, so nothing
/// competed with each screen's hero number. The owner has since asked for the
/// artwork back on the session strips ([SpotifyStrip]), where recognising the
/// track at a glance matters more than that restraint did — so this glyph is
/// no longer the stand-in for a cover. It rides ON one now (a small overlay
/// at the tile's foot), and still stands alone wherever there are no bytes to
/// show: a track whose artwork hasn't arrived yet, or the lozenge.
///
/// Each bar breathes on its own period (0.9s / 0.7s / 1.1s / 0.8s, staggered
/// 0.15s apart, exactly as the prototype's CSS) so the group never pulses in
/// lockstep. One ticker drives all of them.
class EqualizerGlyph extends StatefulWidget {
  const EqualizerGlyph({
    this.bars = 3,
    this.width = 17,
    this.height = 15,
    this.color = TrainColors.green,
    this.playing = true,
    super.key,
  });

  final int bars;
  final double width;
  final double height;
  final Color color;

  /// Freezes the animation mid-height when false — a paused track should not
  /// keep dancing.
  final bool playing;

  @override
  State<EqualizerGlyph> createState() => _EqualizerGlyphState();
}

class _EqualizerGlyphState extends State<EqualizerGlyph>
    with SingleTickerProviderStateMixin {
  // A 10s loop the per-bar periods are sampled out of, rather than one
  // controller per bar — same motion, a quarter of the tickers.
  static const _loopSeconds = 10.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );

  static const _periods = <double>[0.9, 0.7, 1.1, 0.8];
  static const _delays = <double>[0, 0.15, 0.3, 0.45];

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant EqualizerGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing && !reducedMotion(context)) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The CSS keyframe `scaleY(.25) → 1 → scaleY(.25)` on an ease-in-out
  /// alternate, which a raised cosine reproduces almost exactly.
  double _scaleFor(int i, double seconds) {
    final period = _periods[i % _periods.length];
    final phase = ((seconds - _delays[i % _delays.length]) / period) % 1.0;
    return 0.25 + 0.75 * (0.5 - 0.5 * math.cos(2 * math.pi * phase));
  }

  @override
  Widget build(BuildContext context) {
    const gap = 2.5;
    final barWidth =
        (widget.width - gap * (widget.bars - 1)) / widget.bars;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final seconds = _controller.value * _loopSeconds;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < widget.bars; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Container(
                  width: barWidth,
                  // Frozen bars sit at a calm two-thirds rather than
                  // wherever the loop happened to stop.
                  height:
                      widget.height *
                      (widget.playing ? _scaleFor(i, seconds) : 0.62),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
